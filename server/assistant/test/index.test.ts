import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { signedHeaders, storedKey } from "./attest-helpers";
import fixture from "./fixtures/appattest.json";
import { body, MemoryKV, parseSSE, userTurn } from "./helpers";

// Routing, the gates before any model call, App Attest, the developer token and cached guides.
// Turns and guide builds with a (fake) model are in turn.test.ts and guide-endpoint.test.ts.

interface Spaces {
  attest?: MemoryKV;
  quota?: MemoryKV;
  guides?: MemoryKV;
}

const env = (overrides: Record<string, string> = {}, kv: Spaces = {}) =>
  ({
    ATTEST: kv.attest ?? new MemoryKV(),
    QUOTA: kv.quota ?? new MemoryKV(),
    GUIDES: kv.guides ?? new MemoryKV(),
    ANTHROPIC_API_KEY: "test",
    APP_ID: fixture.appId,
    ...overrides,
  }) as never;

const pending: Promise<unknown>[] = [];
const ctx = { waitUntil: (p: Promise<unknown>) => pending.push(p), passThroughOnException() {} } as never;

const post = (path: string, headers: Record<string, string>, payload: string) =>
  new Request(`https://assistant.example${path}`, { method: "POST", headers, body: payload });

const GUIDE = {
  gameId: "NPWR28536_00",
  language: "ru",
  generatedAt: "2026-11-20T10:00:00Z",
  summary: { difficulty: 4, hoursMin: 10, hoursMax: null, playthroughs: 1, onlineTrophies: 0, missableTrophies: 1, glitchedTrophies: 0, difficultyAffects: false, overview: "…" },
  steps: [],
  missable: [],
  tips: [],
  sources: [],
  stratege: null,
};

const guideBody = (refresh = false) =>
  JSON.stringify({
    protocol: 1,
    language: "ru",
    refresh,
    game: { npCommunicationId: "NPWR28536_00", name: "Cult of the Lamb", platform: "PS5", trophies: [{ id: 0, name: "Божественность", detail: "", type: "platinum", hidden: false, groupId: "default" }] },
  });

async function registered(): Promise<MemoryKV> {
  const attest = new MemoryKV();
  await attest.put(`attest-key:${fixture.keyId}`, await storedKey());
  return attest;
}

describe("worker routing", () => {
  it("answers health checks with the protocol and prompt versions", async () => {
    const response = await worker.fetch(new Request("https://assistant.example/v1/health"), env(), ctx);
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ ok: true, protocol: 1, prompt: expect.any(String), guide_prompt: expect.any(String) });
  });

  it("knows only its routes and methods", async () => {
    expect((await worker.fetch(new Request("https://assistant.example/v1/feedback"), env(), ctx)).status).toBe(404);
    expect((await worker.fetch(new Request("https://assistant.example/v1/turn"), env(), ctx)).status).toBe(405);
    expect((await worker.fetch(post("/v1/guide/NPWR28536_00", {}, ""), env(), ctx)).status).toBe(405);
    expect((await worker.fetch(post("/v1/attest/challenge", {}, ""), env(), ctx)).status).toBe(405);
  });

  it("is switched off by ASSISTANT_ENABLED", async () => {
    const off = env({ ASSISTANT_ENABLED: "false" });
    expect((await worker.fetch(post("/v1/turn", {}, body([userTurn("hi")])), off, ctx)).status).toBe(503);
    expect((await worker.fetch(post("/v1/guide", {}, guideBody()), off, ctx)).status).toBe(503);
    const get = await worker.fetch(new Request("https://assistant.example/v1/guide/NPWR28536_00?language=ru"), off, ctx);
    expect(await get.json()).toEqual({ error: "disabled" });
  });

  it("refuses countries the Anthropic API does not serve", async () => {
    const response = await worker.fetch(post("/v1/turn", { "cf-ipcountry": "RU" }, body([userTurn("hi")])), env(), ctx);
    expect(response.status).toBe(451);
    expect(await response.json()).toEqual({ error: "region_unavailable" });
    const kz = await worker.fetch(post("/v1/turn", { "cf-ipcountry": "KZ" }, body([userTurn("hi")])), env(), ctx);
    expect(kz.status).toBe(401); // passes the country gate, stops at App Attest
  });

  it("rejects malformed requests before anything else", async () => {
    const response = await worker.fetch(post("/v1/turn", {}, body([userTurn("hi")], { protocol: 9 })), env(), ctx);
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid", reason: "protocol" });
    const guide = await worker.fetch(post("/v1/guide", {}, JSON.stringify({ protocol: 1, language: "ru", game: { npCommunicationId: "x" } })), env(), ctx);
    expect(await guide.json()).toEqual({ error: "invalid", reason: "game_id" });
  });
});

describe("App Attest", () => {
  it("issues a one-time challenge", async () => {
    const attest = new MemoryKV();
    const response = await worker.fetch(new Request("https://assistant.example/v1/attest/challenge"), env({}, { attest }), ctx);
    const { challenge } = (await response.json()) as { challenge: string };
    expect(attest.store.get(`attest-challenge:${challenge}`)).toBe("1");
  });

  it("refuses an attestation that does not chain to Apple's root", async () => {
    const attest = new MemoryKV();
    await attest.put(`attest-challenge:${fixture.challenge}`, "1");
    const request = post("/v1/attest", {}, JSON.stringify({ keyId: fixture.keyId, attestation: "oA==", challenge: fixture.challenge }));
    const response = await worker.fetch(request, env({}, { attest }), ctx);
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: "attestation" });
  });

  it("asks for an assertion, checks it, then counts the key", async () => {
    const attest = await registered();
    const quota = new MemoryKV();
    const config = { MONTHLY_CALLS: "0" };
    const payload = body([userTurn("hi")]);

    const missing = await worker.fetch(post("/v1/turn", {}, payload), env(config, { attest, quota }), ctx);
    expect(missing.status).toBe(401);
    expect(await missing.json()).toEqual({ error: "attest", reason: "missing" });

    const forged = await worker.fetch(post("/v1/turn", await signedHeaders("other", 1), payload), env(config, { attest, quota }), ctx);
    expect(await forged.json()).toEqual({ error: "attest", reason: "signature" });

    const unknown = await worker.fetch(post("/v1/turn", await signedHeaders(payload, 1), payload), env(config, { quota }), ctx);
    expect(await unknown.json()).toEqual({ error: "attest", reason: "unknown_key" });

    // A valid assertion passes; the quota (0 here) is then counted on the key.
    const signed = await worker.fetch(post("/v1/turn", await signedHeaders(payload, 1), payload), env(config, { attest, quota }), ctx);
    expect(signed.status).toBe(429);
    expect(await signed.json()).toEqual({ error: "quota", reason: "monthly", used: 0, limit: 0 });
    expect(JSON.parse(attest.store.get(`attest-key:${fixture.keyId}`)!).counter).toBe(1);
  });
});

describe("the developer token", () => {
  it("lets the simulator past App Attest only while DEV_TOKEN is set", async () => {
    const payload = body([userTurn("hi")]);
    const quota = new MemoryKV();
    const withToken = env({ DEV_TOKEN: "s3cret-dev-token", MONTHLY_CALLS: "0" }, { quota });

    const passed = await worker.fetch(post("/v1/turn", { "x-platina-dev": "s3cret-dev-token" }, payload), withToken, ctx);
    expect(passed.status).toBe(429); // past App Attest, counted as "dev"
    expect(await passed.json()).toMatchObject({ error: "quota", reason: "monthly" });

    const wrong = await worker.fetch(post("/v1/turn", { "x-platina-dev": "guess" }, payload), withToken, ctx);
    expect(await wrong.json()).toEqual({ error: "attest", reason: "dev_token" });

    // Without the secret the header means nothing: App Attest is asked for.
    const unset = await worker.fetch(post("/v1/turn", { "x-platina-dev": "s3cret-dev-token" }, payload), env({ MONTHLY_CALLS: "0" }), ctx);
    expect(await unset.json()).toEqual({ error: "attest", reason: "missing" });
    const empty = await worker.fetch(post("/v1/turn", { "x-platina-dev": "" }, payload), env({ DEV_TOKEN: "", MONTHLY_CALLS: "0" }), ctx);
    expect(await empty.json()).toEqual({ error: "attest", reason: "missing" });
  });
});

describe("cached guides", () => {
  it("GET answers from the cache or 404", async () => {
    const guides = new MemoryKV();
    await guides.put("NPWR28536_00:ru", JSON.stringify(GUIDE));
    const get = (path: string) => worker.fetch(new Request(`https://assistant.example${path}`), env({}, { guides }), ctx);

    const found = await get("/v1/guide/NPWR28536_00?language=ru-RU");
    expect(found.status).toBe(200);
    expect(await found.json()).toEqual(GUIDE);
    expect((await get("/v1/guide/NPWR28536_00?language=en")).status).toBe(404);
    expect(await (await get("/v1/guide/NPWR99999_00?language=ru")).json()).toEqual({ error: "not_found" });
    expect(await (await get("/v1/guide/..%2Fetc?language=ru")).json()).toEqual({ error: "invalid", reason: "game_id" });
    expect(await (await get("/v1/guide/%E0%A4%A?language=ru")).json()).toEqual({ error: "invalid", reason: "game_id" });
    expect(await (await get("/v1/guide/NPWR28536_00")).json()).toEqual({ error: "invalid", reason: "language" });
  });

  it("POST returns a cached guide without building or counting it", async () => {
    const guides = new MemoryKV();
    const quota = new MemoryKV();
    await guides.put("NPWR28536_00:ru", JSON.stringify(GUIDE));
    const response = await worker.fetch(post("/v1/guide", { "x-platina-dev": "t" }, guideBody()), env({ DEV_TOKEN: "t", DAILY_GUIDES: "0" }, { guides, quota }), ctx);
    expect(response.headers.get("content-type")).toBe("text/event-stream");
    expect(parseSSE(await response.text())).toEqual([{ event: "guide", data: GUIDE }]);
    expect(quota.store.size).toBe(0);

    // refresh: true skips the cache and needs the quota.
    const refresh = await worker.fetch(post("/v1/guide", { "x-platina-dev": "t" }, guideBody(true)), env({ DEV_TOKEN: "t", DAILY_GUIDES: "0" }, { guides, quota }), ctx);
    expect(refresh.status).toBe(429);
    expect(await refresh.json()).toEqual({ error: "quota", reason: "daily", used: 0, limit: 0 });
  });
});
