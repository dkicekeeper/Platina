import Anthropic from "@anthropic-ai/sdk";
import { AttestError, checkAssertion, isValidKeyId, issueChallenge, registerKey } from "./appattest";
import { buildParams, donePayload, errorPayload, normalizeForEcho, TurnEventMapper } from "./claude";
import { readConfig, type Config, type Env } from "./config";
import { equalBytes } from "./der";
import { buildGuide, GUIDE_PROMPT_VERSION, GuideError, readGuide, storeGuide, type ModelCall } from "./guide";
import { PROMPT_VERSION } from "./prompt";
import { consumeCall, consumeGuide, refund, type QuotaStatus } from "./quota";
import { eventStream } from "./sse";
import { isValidGameId, LIMITS, parseGuideRequest, parseTurnRequest, PROTOCOL_VERSION, resolveLanguage, ValidationError, type TurnMessage } from "./validate";

// Plati's server: a Cloudflare Worker between the Platina app and Claude (docs/assistant.md).
//
//   GET  /v1/health                    protocol and prompt versions
//   GET  /v1/attest/challenge          App Attest: a one-time challenge
//   POST /v1/attest                    App Attest: register the install's key
//   POST /v1/turn                      one model call of the chat, as server-sent events
//   POST /v1/guide                     a game's guide: from the cache, or built now (SSE)
//   GET  /v1/guide/{id}?language=ru    a cached guide, or 404
//
// /v1/turn and POST /v1/guide come only from the real app: each carries an App Attest
// assertion over its body (x-platina-key, x-platina-assertion), or, while the DEV_TOKEN secret
// is set, `x-platina-dev: <DEV_TOKEN>` for the simulator. Quotas count per attested key.
//
// Nothing about the conversation or the person is logged: only status and error codes.

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

const fail = (status: number, code: string, extra: Record<string, unknown> = {}) => json({ error: code, ...extra }, status);

/** How many times a turn paused by a long server-side web search is resumed within the call. */
const MAX_CONTINUATIONS = 2;

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const config = readConfig(env);

    if (url.pathname === "/v1/health") return json({ ok: true, protocol: PROTOCOL_VERSION, prompt: PROMPT_VERSION, guide_prompt: GUIDE_PROMPT_VERSION });

    // Registering a key calls no model: it answers everywhere, always.
    if (url.pathname === "/v1/attest/challenge") {
      if (request.method !== "GET") return fail(405, "method");
      return json({ challenge: await issueChallenge(env.ATTEST) });
    }
    if (url.pathname === "/v1/attest") {
      if (request.method !== "POST") return fail(405, "method");
      return attest(request, env, config.appId);
    }

    const guidePath = /^\/v1\/guide\/([^/]+)$/.exec(url.pathname);
    if (url.pathname !== "/v1/turn" && url.pathname !== "/v1/guide" && !guidePath) return fail(404, "not_found");

    if (!config.enabled) return fail(503, "disabled");
    // request.cf is set on every request; the cf-ipcountry header only with IP Geolocation on
    // the zone, which a workers.dev route doesn't have.
    const country = ((request.cf?.country as string | undefined) ?? request.headers.get("cf-ipcountry") ?? undefined)?.toUpperCase();
    if (country && config.blockedCountries.has(country)) return fail(451, "region_unavailable");

    if (guidePath) {
      if (request.method !== "GET") return fail(405, "method");
      return cachedGuide(env, decodeURIComponent(guidePath[1]!), url.searchParams.get("language"));
    }
    if (request.method !== "POST") return fail(405, "method");
    const length = Number(request.headers.get("content-length") ?? "0");
    if (length > LIMITS.bodyBytes * 2) return fail(400, "invalid", { reason: "too_large" });
    if (url.pathname === "/v1/turn") return turn(request, env, ctx, config);
    return guide(request, env, ctx, config);
  },
} satisfies ExportedHandler<Env>;

// MARK: - The caller

const sha256 = async (text: string) => new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));

/** Who is calling, as the quotas count them (`key:<App Attest key id>`, or `dev`), or the
 * refusal: the request is not from the app. */
async function authenticate(request: Request, env: Env, config: Config, bytes: Uint8Array): Promise<string | Response> {
  // The simulator has no App Attest: a debug build sends the developer token instead. Only
  // while the secret is set; compared as digests, so the time taken says nothing about it.
  const dev = request.headers.get("x-platina-dev");
  if (env.DEV_TOKEN && dev !== null) {
    if (equalBytes(await sha256(dev), await sha256(env.DEV_TOKEN))) return "dev";
    return fail(401, "attest", { reason: "dev_token" });
  }
  const keyId = request.headers.get("x-platina-key");
  const assertion = request.headers.get("x-platina-assertion");
  if (!isValidKeyId(keyId) || !assertion || assertion.length > 4096) return fail(401, "attest", { reason: "missing" });
  try {
    await checkAssertion(env.ATTEST, keyId, assertion, bytes, config.appId);
  } catch (error) {
    if (error instanceof AttestError) return fail(401, "attest", { reason: error.reason });
    throw error;
  }
  return `key:${keyId}`;
}

const quotaRefusal = (quota: QuotaStatus) => fail(429, "quota", { reason: quota.reason, used: quota.used, limit: quota.limit });

async function readBody<T>(request: Request, parse: (raw: string) => T): Promise<{ bytes: Uint8Array; body: T } | Response> {
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.length > LIMITS.bodyBytes) return fail(400, "invalid", { reason: "too_large" });
  try {
    return { bytes, body: parse(new TextDecoder().decode(bytes)) };
  } catch (error) {
    if (error instanceof ValidationError) return fail(400, "invalid", { reason: error.code });
    throw error;
  }
}

// MARK: - POST /v1/turn

// One model call of the chat. The app runs the loop: it sends the conversation, runs the tools
// Claude asks for on the phone, and calls again with their results. Events:
//   text   {text}                            a piece of the reply
//   tool   {name}                            a phone tool call started
//   search {query}                           a web search, with its query
//   done   {content, stop_reason, usage...}  the assistant turn to append verbatim
//   error  {code, retryable}
async function turn(request: Request, env: Env, ctx: ExecutionContext, config: Config): Promise<Response> {
  const read = await readBody(request, parseTurnRequest);
  if (read instanceof Response) return read;
  const { bytes, body } = read;

  const caller = await authenticate(request, env, config, bytes);
  if (caller instanceof Response) return caller;
  const quota = await consumeCall(env.QUOTA, caller, config);
  if (!quota.allowed) return quotaRefusal(quota);

  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, maxRetries: 1 });
  const sse = eventStream({ "x-platina-prompt": PROMPT_VERSION });

  // Set by the first event of the model's stream. A call that fails before it (Anthropic down,
  // overloaded, or refusing the request) produced nothing and costs nothing: its count is given
  // back. One that fails mid-answer keeps it, since part of it was generated.
  let started = false;
  // The app closed the chat or lost the connection: the model's stream is stopped instead of
  // being paid for to its end. The call keeps its count: the model may have read the request.
  let disconnected = false;
  let current: ReturnType<typeof client.beta.messages.stream> | undefined;
  sse.onDisconnect(() => {
    disconnected = true;
    current?.abort();
  });

  ctx.waitUntil(
    (async () => {
      try {
        let messages: TurnMessage[] = body.messages;
        const results: Anthropic.Beta.BetaMessage[] = [];
        for (let call = 0; call <= MAX_CONTINUATIONS; call++) {
          const stream = client.beta.messages.stream(buildParams(config, body.language, messages));
          current = stream;
          if (disconnected) stream.abort();
          const mapper = new TurnEventMapper();
          for await (const event of stream) {
            started = true;
            for (const out of mapper.map(event)) await sse.send(out.event, out.data);
          }
          const message = await stream.finalMessage();
          results.push(message);
          // A long server-side search paused the turn: sent back as it is, the server goes on.
          if (message.stop_reason !== "pause_turn") break;
          messages = [...messages, { role: "assistant", content: normalizeForEcho(message.content) as Anthropic.Beta.BetaContentBlockParam[] }];
        }
        await sse.send("done", { ...donePayload(results), quota: { used: quota.used, limit: quota.limit } });
      } catch (error) {
        if (disconnected) {
          console.log(`turn stopped: the app left${started ? "" : " before the answer"}`);
          return;
        }
        const payload = errorPayload(error);
        const refunded = !started && quota.charge !== undefined;
        console.log(`turn error ${payload.code}${error instanceof Anthropic.APIError ? ` ${error.status}` : ""}${refunded ? " refunded" : ""}`);
        await sse.send("error", payload);
        if (refunded && quota.charge) await refund(env.QUOTA, quota.charge);
      } finally {
        await sse.close();
      }
    })(),
  );
  return sse.response;
}

// MARK: - Guides

// POST /v1/guide: the cached guide at once, or a new one built (src/guide.ts). Events:
//   progress {step}          stratege, search, writing
//   guide    {...Guide}
//   error    {code, retryable}
// A guide from the cache costs nothing; a build counts in DAILY_GUIDES. The build goes on when
// the app leaves (while the platform lets it), so the next request finds it in the cache.
async function guide(request: Request, env: Env, ctx: ExecutionContext, config: Config): Promise<Response> {
  const read = await readBody(request, parseGuideRequest);
  if (read instanceof Response) return read;
  const { bytes, body } = read;

  const caller = await authenticate(request, env, config, bytes);
  if (caller instanceof Response) return caller;

  const headers = { "x-platina-prompt": GUIDE_PROMPT_VERSION };
  if (!body.refresh) {
    const cached = await readGuide(env.GUIDES, body.game.npCommunicationId, body.language).catch(() => undefined);
    if (cached) {
      const sse = eventStream(headers);
      ctx.waitUntil(sse.send("guide", cached).then(() => sse.close()));
      return sse.response;
    }
  }

  const quota = await consumeGuide(env.QUOTA, caller, config);
  if (!quota.allowed) return quotaRefusal(quota);

  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, maxRetries: 1 });
  const call: ModelCall = async (params, onEvent) => {
    const stream = client.beta.messages.stream(params);
    for await (const event of stream) onEvent(event);
    return stream.finalMessage();
  };
  const sse = eventStream(headers);
  let started = false;

  ctx.waitUntil(
    (async () => {
      try {
        const result = await buildGuide(body.game, body.language, {
          config,
          call,
          fetch: (input, init) => fetch(input, init),
          kv: env.GUIDES,
          refresh: body.refresh,
          onProgress: (step) => sse.send("progress", { step }),
          onModelStarted: () => {
            started = true;
          },
        });
        await storeGuide(env.GUIDES, result.guide).catch(() => console.log("guide not cached"));
        console.log(`guide built: calls ${result.calls}, stratege pages ${result.strategeFetches}, searches ${result.usage.web_search_requests}`);
        await sse.send("guide", result.guide);
      } catch (error) {
        const payload = error instanceof GuideError ? { code: error.code, retryable: error.retryable } : errorPayload(error);
        const refunded = !started && quota.charge !== undefined;
        console.log(`guide error ${payload.code}${error instanceof Anthropic.APIError ? ` ${error.status}` : ""}${refunded ? " refunded" : ""}`);
        await sse.send("error", payload);
        if (refunded && quota.charge) await refund(env.QUOTA, quota.charge);
      } finally {
        await sse.close();
      }
    })(),
  );
  return sse.response;
}

/** GET /v1/guide/{npCommunicationId}?language=ru: the cached guide, or 404. */
async function cachedGuide(env: Env, gameId: string, languageParam: string | null): Promise<Response> {
  if (!isValidGameId(gameId)) return fail(400, "invalid", { reason: "game_id" });
  const language = resolveLanguage(languageParam);
  if (!language) return fail(400, "invalid", { reason: "language" });
  const found = await readGuide(env.GUIDES, gameId, language);
  return found ? json(found) : fail(404, "not_found");
}

// MARK: - App Attest registration

async function attest(request: Request, env: Env, appId: string): Promise<Response> {
  let input: { keyId?: unknown; attestation?: unknown; challenge?: unknown };
  try {
    const text = await request.text();
    if (text.length > 64 * 1024) return fail(400, "invalid", { reason: "size" });
    input = JSON.parse(text);
  } catch {
    return fail(400, "invalid", { reason: "json" });
  }
  const { keyId, attestation, challenge } = input;
  if (typeof keyId !== "string" || !isValidKeyId(keyId) || typeof attestation !== "string" || typeof challenge !== "string") {
    return fail(400, "invalid", { reason: "fields" });
  }
  try {
    const stored = await registerKey(env.ATTEST, { keyId, attestation, challenge }, { appId });
    return json({ ok: true, environment: stored.environment });
  } catch (error) {
    if (error instanceof AttestError) {
      console.log(`attest ${error.reason}`);
      return fail(400, "attestation", { reason: error.reason });
    }
    throw error;
  }
}
