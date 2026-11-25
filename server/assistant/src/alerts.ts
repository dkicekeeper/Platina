// Trophy notifications' endpoints (docs/assistant.md §9). Each request carries an App Attest
// assertion over its body, as the builds do; the watcher is the install's own.
//
//   POST   /v1/alerts        {code, pushToken, environment, language}: turn on (or renew)
//   PUT    /v1/alerts/token  {pushToken, environment}: a new device token
//   DELETE /v1/alerts        {}: turn off; the server forgets the grant and everything else
//
// The code is an authorization code the app asked Sony for from its sign-in: the server
// exchanges it for its own tokens here, so the phone's tokens never leave the phone.

import type { Env } from "./config";
import type { AlertLanguage } from "./alerts-text";
import { accountId, exchangeCode, SonyError, type Fetcher } from "./sony";
import type { SubscribeRequest } from "./watcher";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
const fail = (status: number, code: string, extra: Record<string, unknown> = {}) => json({ error: code, ...extra }, status);

export type Authenticate = (request: Request, bytes: Uint8Array) => Promise<string | Response>;

const MAX_BODY = 8 * 1024;

type Environment = SubscribeRequest["environment"];

const isPushToken = (value: unknown): value is string => typeof value === "string" && /^[0-9a-fA-F]{64,200}$/.test(value);
const isEnvironment = (value: unknown): value is Environment => value === "sandbox" || value === "production";
const isLanguage = (value: unknown): value is AlertLanguage => value === "ru" || value === "en";
const isCode = (value: unknown): value is string => typeof value === "string" && /^[A-Za-z0-9._~-]{4,512}$/.test(value);

/** Answers /v1/alerts and /v1/alerts/token, or null for another path. */
export async function handleAlerts(request: Request, env: Env, authenticate: Authenticate, fetcher: Fetcher = (i, init) => fetch(i, init)): Promise<Response | null> {
  const path = new URL(request.url).pathname;
  const route =
    path === "/v1/alerts" && request.method === "POST"
      ? "subscribe"
      : path === "/v1/alerts" && request.method === "DELETE"
        ? "unsubscribe"
        : path === "/v1/alerts/token" && request.method === "PUT"
          ? "token"
          : null;
  if (path !== "/v1/alerts" && path !== "/v1/alerts/token") return null;
  if (!route) return fail(405, "method");
  if (!env.WATCHERS || !env.TOKEN_KEY || !env.APNS_KEY_P8 || !env.APNS_KEY_ID) return fail(503, "alerts_unavailable");

  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.length > MAX_BODY) return fail(400, "invalid", { reason: "too_large" });
  let body: Record<string, unknown>;
  try {
    const parsed: unknown = bytes.length === 0 ? {} : JSON.parse(new TextDecoder().decode(bytes));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
    body = parsed as Record<string, unknown>;
  } catch {
    return fail(400, "invalid", { reason: "json" });
  }
  const caller = await authenticate(request, bytes);
  if (caller instanceof Response) return caller;
  const watcher = env.WATCHERS.get(env.WATCHERS.idFromName(caller));
  const call = (name: string, payload: unknown = {}) =>
    watcher.fetch(`https://watcher/${name}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(payload) });

  if (route === "unsubscribe") {
    await call("unsubscribe");
    return json({ ok: true });
  }
  if (route === "token") {
    if (!isPushToken(body.pushToken) || !isEnvironment(body.environment)) return fail(400, "invalid", { reason: "fields" });
    const answer = await call("token", { pushToken: body.pushToken, environment: body.environment });
    return answer.ok ? json({ ok: true }) : fail(404, "not_subscribed");
  }

  if (!isCode(body.code) || !isPushToken(body.pushToken) || !isEnvironment(body.environment) || !isLanguage(body.language)) {
    return fail(400, "invalid", { reason: "fields" });
  }
  let subscribe: SubscribeRequest;
  try {
    const grant = await exchangeCode(body.code, fetcher);
    subscribe = {
      grant,
      accountId: await accountId(grant.accessToken, fetcher),
      pushToken: body.pushToken,
      environment: body.environment,
      language: body.language,
    };
  } catch (error) {
    if (error instanceof SonyError) {
      console.log(`alerts ${error.message}`);
      return error.kind === "refused" ? fail(400, "invalid", { reason: "code" }) : fail(502, "psn_unavailable");
    }
    throw error;
  }
  await call("subscribe", subscribe);
  return json({ ok: true });
}
