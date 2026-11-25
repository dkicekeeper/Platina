import { beforeEach, describe, expect, it } from "vitest";
import { resetProviderToken, sendPush, providerToken, type ApnsConfig } from "../src/apns";
import { ruTrophies, signInAgainAlert, trophyAlerts } from "../src/alerts-text";
import worker from "../src/index";
import { earnedSince, exchangeCode, recentLists, SonyError, type EarnedTrophy } from "../src/sony";
import { open, seal } from "../src/vault";
import { TrophyWatcher, WATCH, type Subscription, type WatcherStorage } from "../src/watcher";
import { MemoryKV } from "./helpers";

// Trophy notifications (docs/assistant.md §9): texts, the token vault, APNs, Sony's grant and
// reads, the watcher's state machine on a fake clock and a fake PSN, and the endpoints.

const KEY = btoa(String.fromCharCode(...new Uint8Array(32).map((_, i) => i + 1)));

async function p8(): Promise<string> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  return `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
}

const trophy = (id: number, type: EarnedTrophy["type"], name: string, earnedAt = "2026-11-25T10:00:00Z"): EarnedTrophy => ({ id, type, name, earnedAt });

describe("notification texts", () => {
  const game = { id: "NPWR1_00", name: "Emberfall" };

  it("names one trophy with its type, the game under it", () => {
    const [alert] = trophyAlerts("en", game, [trophy(3, "gold", "Night Rider")]);
    expect(alert).toMatchObject({ title: "🏆 Gold · Night Rider", body: "Emberfall", threadId: "NPWR1_00", data: { gameId: "NPWR1_00", trophyIds: [3] } });
  });

  it("groups the trophies of one check, the best first", () => {
    const alerts = trophyAlerts("ru", game, [trophy(1, "bronze", "Эхо"), trophy(2, "gold", "Удача"), trophy(3, "silver", "Тень")]);
    expect(alerts).toHaveLength(1);
    expect(alerts[0]).toMatchObject({ title: "🏆 3 трофея · Emberfall", body: "Золото · Удача, Серебро · Тень, Бронза · Эхо" });
  });

  it("counts the trophies past four", () => {
    const many = [1, 2, 3, 4, 5, 6].map((id) => trophy(id, "bronze", `T${id}`));
    expect(trophyAlerts("en", game, many)[0]!.body).toBe("Bronze · T1, Bronze · T2, Bronze · T3, Bronze · T4 and 2 more");
    expect(trophyAlerts("ru", game, many)[0]!.body.endsWith(" и ещё 2")).toBe(true);
  });

  it("gives the platinum a notification of its own", () => {
    const alerts = trophyAlerts("en", game, [trophy(9, "bronze", "Last"), trophy(0, "platinum", "All Lights Lit")]);
    expect(alerts.map((a) => a.title)).toEqual(["🏆 Bronze · Last", "🏆 Platinum · Emberfall"]);
    expect(alerts[1]).toMatchObject({ body: "All Lights Lit", data: { trophyIds: [0], platinum: true } });
  });

  it("declines trophies in Russian", () => {
    expect([1, 2, 5, 11, 21, 22, 25, 112].map(ruTrophies)).toEqual([
      "1 трофей", "2 трофея", "5 трофеев", "11 трофеев", "21 трофей", "22 трофея", "25 трофеев", "112 трофеев",
    ]);
  });
});

describe("token vault", () => {
  it("opens what it sealed, and not with another key", async () => {
    const sealed = await seal(KEY, "refresh-token");
    expect(sealed).not.toContain("refresh-token");
    expect(await open(KEY, sealed)).toBe("refresh-token");
    const other = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));
    await expect(open(other, sealed)).rejects.toThrow();
  });
});

describe("APNs", () => {
  beforeEach(() => resetProviderToken());

  it("signs a provider token with the key id and team, and reuses it for 50 minutes", async () => {
    const config: ApnsConfig = { keyP8: await p8(), keyId: "ABC123DEFG", teamId: "SY2L2VMQP7", topic: "dakacom.Platina" };
    const jwt = await providerToken(config, 1_000_000);
    const [header, payload, signature] = jwt.split(".");
    const decode = (part: string) => JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));
    expect(decode(header!)).toEqual({ alg: "ES256", kid: "ABC123DEFG" });
    expect(decode(payload!)).toEqual({ iss: "SY2L2VMQP7", iat: 1000 });
    expect(signature!.length).toBe(86); // 64 bytes, base64url
    expect(await providerToken(config, 1_000_000 + 49 * 60_000)).toBe(jwt);
    expect(await providerToken(config, 1_000_000 + 51 * 60_000)).not.toBe(jwt);
  });

  it("sends to the app's environment and reads Apple's answer", async () => {
    const config: ApnsConfig = { keyP8: await p8(), keyId: "K", teamId: "T", topic: "dakacom.Platina" };
    const sent: Array<{ url: string; headers: Headers; body: Record<string, unknown> }> = [];
    let status = 200;
    let reason = "";
    const fetcher = async (input: Request | string | URL, init?: RequestInit) => {
      sent.push({ url: String(input), headers: new Headers(init?.headers), body: JSON.parse(String(init?.body)) });
      return new Response(reason ? JSON.stringify({ reason }) : null, { status });
    };
    const content = { title: "t", body: "b", threadId: "NPWR1_00", data: { gameId: "NPWR1_00" } };
    expect(await sendPush(config, { token: "ab".repeat(32), environment: "sandbox" }, content, fetcher)).toBe("sent");
    expect(sent[0]!.url).toBe(`https://api.sandbox.push.apple.com/3/device/${"ab".repeat(32)}`);
    expect(sent[0]!.headers.get("apns-topic")).toBe("dakacom.Platina");
    expect(sent[0]!.headers.get("authorization")).toMatch(/^bearer /);
    expect(sent[0]!.body).toEqual({ aps: { alert: { title: "t", body: "b" }, sound: "default", "thread-id": "NPWR1_00" }, gameId: "NPWR1_00" });

    status = 410;
    expect(await sendPush(config, { token: "ab".repeat(32), environment: "production" }, content, fetcher)).toBe("gone");
    expect(sent[1]!.url.startsWith("https://api.push.apple.com/")).toBe(true);
    status = 400;
    reason = "BadDeviceToken";
    expect(await sendPush(config, { token: "ab".repeat(32), environment: "production" }, content, fetcher)).toBe("gone");
    status = 500;
    reason = "InternalServerError";
    expect(await sendPush(config, { token: "ab".repeat(32), environment: "production" }, content, fetcher)).toBe("failed");
  });
});

// MARK: - A fake PSN

interface FakeList {
  id: string;
  name: string;
  platform?: string;
  earned: Array<{ id: number; type: EarnedTrophy["type"]; name: string; at: string }>;
}

class FakeSony {
  lists: FakeList[] = [];
  playing: boolean | "hidden" = false;
  refreshRefused = false;
  requests: string[] = [];
  pushes: Array<{ title: string; body: string; data: Record<string, unknown> }> = [];
  apnsStatus = 200;

  fetcher = async (input: Request | string | URL, init?: RequestInit): Promise<Response> => {
    const url = new URL(String(input));
    const path = url.pathname;
    this.requests.push(`${url.host}${path}`);
    const ok = (body: unknown) => new Response(JSON.stringify(body), { status: 200 });
    if (url.host === "ca.account.sony.com") {
      const form = new URLSearchParams(String(init?.body));
      if (form.get("grant_type") === "authorization_code" && form.get("code") === "bad-code") return new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 });
      if (form.get("grant_type") === "refresh_token" && this.refreshRefused) return new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 });
      return ok({ access_token: "access-2", expires_in: 3600, refresh_token: "refresh-2", refresh_token_expires_in: 5_000_000 });
    }
    if (url.host.endsWith("push.apple.com")) {
      const body = JSON.parse(String(init?.body)) as { aps: { alert: { title: string; body: string } } } & Record<string, unknown>;
      const { aps, ...data } = body;
      this.pushes.push({ title: aps.alert.title, body: aps.alert.body, data });
      return new Response(null, { status: this.apnsStatus });
    }
    if (path.endsWith("/trophySummary")) return ok({ accountId: "7700000000000000001" });
    if (path.endsWith("/basicPresences")) {
      if (this.playing === "hidden") return new Response(JSON.stringify({ error: { code: 2240526 } }), { status: 403 });
      return ok({ basicPresence: { gameTitleInfoList: this.playing ? [{ npTitleId: "PPSA1" }] : [] } });
    }
    if (path.endsWith("/users/me/trophyTitles")) {
      return ok({
        trophyTitles: this.lists.map((list) => ({
          npCommunicationId: list.id,
          npServiceName: "trophy2",
          trophyTitleName: list.name,
          trophyTitlePlatform: list.platform ?? "PS5",
          earnedTrophies: { bronze: list.earned.length, silver: 0, gold: 0, platinum: 0 },
          lastUpdatedDateTime: list.earned.map((t) => t.at).sort().at(-1) ?? "2026-01-01T00:00:00Z",
        })),
      });
    }
    const listId = /npCommunicationIds\/([^/]+)/.exec(path)?.[1];
    const list = this.lists.find((l) => l.id === listId);
    if (list && path.includes("/users/me/")) {
      return ok({ trophies: list.earned.map((t) => ({ trophyId: t.id, trophyType: t.type, earned: true, earnedDateTime: t.at })) });
    }
    if (list) return ok({ trophies: list.earned.map((t) => ({ trophyId: t.id, trophyType: t.type, trophyName: t.name })) });
    return new Response("{}", { status: 404 });
  };
}

class FakeStorage implements WatcherStorage {
  data = new Map<string, unknown>();
  alarm: number | null = null;
  async get<T>(key: string) {
    return structuredClone(this.data.get(key)) as T | undefined;
  }
  async put<T>(key: string, value: T) {
    this.data.set(key, structuredClone(value));
  }
  async deleteAll() {
    this.data.clear();
  }
  async setAlarm(time: number) {
    this.alarm = time;
  }
  async deleteAlarm() {
    this.alarm = null;
  }
}

describe("Sony", () => {
  it("exchanges a code for the server's own grant, and says when Sony refuses it", async () => {
    const sony = new FakeSony();
    const grant = await exchangeCode("v3.code", sony.fetcher, 1000);
    expect(grant).toEqual({ accessToken: "access-2", accessExpiresAt: 1000 + 3_600_000, refreshToken: "refresh-2", refreshExpiresAt: 1000 + 5_000_000_000 });
    await expect(exchangeCode("bad-code", sony.fetcher)).rejects.toMatchObject({ kind: "refused" });
  });

  it("reads PS5 and PS4 lists only, and the trophies earned since a date with their names", async () => {
    const sony = new FakeSony();
    sony.lists = [
      { id: "NPWR1_00", name: "Emberfall", earned: [{ id: 1, type: "bronze", name: "Old", at: "2026-11-20T10:00:00Z" }, { id: 2, type: "gold", name: "New", at: "2026-11-25T10:00:00Z" }] },
      { id: "NPWR2_00", name: "Old Vita game", platform: "PSVITA", earned: [] },
      { id: "NPWR3_00", name: "PS4 game", platform: "PS4", earned: [] },
    ];
    const lists = await recentLists("token", sony.fetcher);
    expect(lists.map((l) => l.id)).toEqual(["NPWR1_00", "NPWR3_00"]);
    const fresh = await earnedSince(lists[0]!, "2026-11-21T00:00:00Z", "en", "token", sony.fetcher);
    expect(fresh).toEqual([{ id: 2, type: "gold", name: "New", earnedAt: "2026-11-25T10:00:00Z" }]);
  });

  it("calls a private answer hidden", async () => {
    const sony = new FakeSony();
    sony.playing = "hidden";
    const { isPlaying } = await import("../src/sony");
    await expect(isPlaying("1", "token", sony.fetcher)).rejects.toEqual(new SonyError("hidden", 403));
  });
});

// MARK: - The watcher

describe("trophy watcher", () => {
  let clock: number;
  let sony: FakeSony;
  let storage: FakeStorage;
  let watcher: TrophyWatcher;

  beforeEach(async () => {
    resetProviderToken();
    clock = Date.parse("2026-11-25T12:00:00Z");
    sony = new FakeSony();
    sony.lists = [{ id: "NPWR1_00", name: "Emberfall", earned: [{ id: 1, type: "bronze", name: "Old", at: "2026-11-20T10:00:00Z" }] }];
    storage = new FakeStorage();
    watcher = new TrophyWatcher({ storage }, { TOKEN_KEY: KEY, APNS_KEY_P8: await p8(), APNS_KEY_ID: "K" }, { fetcher: sony.fetcher, now: () => clock });
    await watcher.subscribe({
      grant: { accessToken: "access-1", accessExpiresAt: clock + 3_600_000, refreshToken: "refresh-1", refreshExpiresAt: clock + 86_400_000 * 60 },
      accountId: "7700000000000000001",
      pushToken: "ab".repeat(32),
      environment: "sandbox",
      language: "en",
    });
  });

  const tick = async (ms: number) => {
    clock += ms;
    await watcher.alarm();
  };
  const sub = () => storage.data.get("sub") as Subscription | undefined;
  const earn = (id: number, type: EarnedTrophy["type"], name: string) =>
    sony.lists[0]!.earned.push({ id, type, name, at: new Date(clock - 30_000).toISOString() });

  it("keeps the tokens sealed and looks soon after subscribing", async () => {
    expect(JSON.stringify(sub())).not.toContain("refresh-1");
    expect(storage.alarm).toBe(clock + WATCH.first);
  });

  it("only records the lists on the first look", async () => {
    await tick(WATCH.first);
    expect(sony.pushes).toEqual([]);
    expect(storage.data.get("lists")).toEqual({ NPWR1_00: { earned: 1, updated: "2026-11-20T10:00:00Z" } });
    expect(storage.alarm).toBe(clock + WATCH.idle);
  });

  it("asks only presence while nothing runs", async () => {
    await tick(WATCH.first);
    sony.requests = [];
    await tick(WATCH.idle);
    expect(sony.requests.map((r) => r.split("/").at(-1))).toEqual(["basicPresences"]);
    expect(storage.alarm).toBe(clock + WATCH.idle);
  });

  it("checks every minute while a game runs and sends what was earned, the platinum on its own", async () => {
    await tick(WATCH.first);
    sony.playing = true;
    await tick(WATCH.idle);
    expect(sub()!.mode).toBe("active");
    expect(storage.alarm).toBe(clock + WATCH.active);

    earn(2, "gold", "Night Rider");
    earn(0, "platinum", "All Lights Lit");
    await tick(WATCH.active);
    expect(sony.pushes.map((p) => p.title)).toEqual(["🏆 Gold · Night Rider", "🏆 Platinum · Emberfall"]);
    expect(sony.pushes[0]!.data).toEqual({ gameId: "NPWR1_00", trophyIds: [2] });

    sony.pushes = [];
    await tick(WATCH.active);
    expect(sony.pushes).toEqual([]);
  });

  it("goes back to idle after two quiet checks once the game stops", async () => {
    await tick(WATCH.first);
    sony.playing = true;
    await tick(WATCH.idle); // The game started: the first quiet check.
    sony.playing = false;
    sony.requests = [];
    await tick(WATCH.active); // The second: no presence asked yet.
    expect(sub()!.quiet).toBe(2);
    expect(sony.requests.some((r) => r.endsWith("basicPresences"))).toBe(false);
    await tick(WATCH.active);
    expect(sub()!.mode).toBe("idle");
    expect(storage.alarm).toBe(clock + WATCH.idle);
  });

  it("checks the lists every ten minutes when presence is private", async () => {
    await tick(WATCH.first);
    sony.playing = "hidden";
    await tick(WATCH.idle);
    expect(storage.alarm).toBe(clock + WATCH.hidden);
    earn(3, "silver", "Shadow");
    sony.requests = [];
    await tick(WATCH.hidden);
    expect(sony.requests.some((r) => r.endsWith("basicPresences"))).toBe(false);
    expect(sony.pushes.map((p) => p.title)).toEqual(["🏆 Silver · Shadow"]);
  });

  it("refreshes an expired access token", async () => {
    await tick(WATCH.first);
    await tick(3_600_000);
    expect(sony.requests).toContain("ca.account.sony.com/api/authz/v3/oauth/token");
    expect(storage.alarm).not.toBeNull();
  });

  it("says once to sign in again when Sony refuses the refresh token, then forgets everything", async () => {
    await tick(WATCH.first);
    sony.refreshRefused = true;
    await tick(3_600_000);
    expect(sony.pushes.map((p) => p.title)).toEqual(["Trophy notifications paused"]);
    expect(storage.data.size).toBe(0);
    expect(storage.alarm).toBeNull();
    await tick(WATCH.idle);
    expect(sony.pushes).toHaveLength(1);
  });

  it("stops when APNs says the device token is gone", async () => {
    await tick(WATCH.first);
    sony.playing = true;
    await tick(WATCH.idle);
    sony.apnsStatus = 410;
    earn(2, "gold", "Night Rider");
    await tick(WATCH.active);
    expect(storage.data.size).toBe(0);
    expect(storage.alarm).toBeNull();
  });

  it("forgets everything when turned off", async () => {
    await tick(WATCH.first);
    const answer = await watcher.fetch(new Request("https://watcher/unsubscribe", { method: "POST", body: "{}" }));
    expect(answer.status).toBe(200);
    expect(storage.data.size).toBe(0);
    expect(storage.alarm).toBeNull();
  });
});

// MARK: - The endpoints

describe("alerts endpoints", () => {
  const ctx = { waitUntil() {}, passThroughOnException() {} } as never;

  async function setup(withSecrets = true) {
    const sony = new FakeSony();
    const storage = new FakeStorage();
    const keyP8 = await p8();
    const env = {
      ATTEST: new MemoryKV(),
      QUOTA: new MemoryKV(),
      GUIDES: new MemoryKV(),
      ANTHROPIC_API_KEY: "test",
      DEV_TOKEN: "dev-secret",
      ...(withSecrets ? { TOKEN_KEY: KEY, APNS_KEY_P8: keyP8, APNS_KEY_ID: "K" } : {}),
    } as Record<string, unknown>;
    const names: string[] = [];
    const watcher = new TrophyWatcher({ storage }, env as never, { fetcher: sony.fetcher });
    env.WATCHERS = {
      idFromName: (name: string) => (names.push(name), name),
      get: () => ({ fetch: (url: string, init: RequestInit) => watcher.fetch(new Request(url, init)) }),
    };
    return { sony, storage, env: env as never, names };
  }

  const request = (method: string, path: string, body: unknown) =>
    new Request(`https://assistant.example${path}`, { method, headers: { "x-platina-dev": "dev-secret" }, body: JSON.stringify(body) });

  it("turns notifications on: the code becomes the server's own grant, in the install's watcher", async () => {
    const { sony, storage, env, names } = await setup();
    // The Worker's own fetch goes to Sony; route it to the fake.
    const original = globalThis.fetch;
    globalThis.fetch = sony.fetcher as typeof fetch;
    try {
      const answer = await worker.fetch(request("POST", "/v1/alerts", { code: "v3.abc", pushToken: "ab".repeat(32), environment: "sandbox", language: "ru" }), env, ctx);
      expect(answer.status).toBe(200);
      expect(names).toEqual(["dev"]);
      expect((storage.data.get("sub") as Subscription).accountId).toBe("7700000000000000001");
      expect((storage.data.get("sub") as Subscription).language).toBe("ru");

      const bad = await worker.fetch(request("POST", "/v1/alerts", { code: "bad-code", pushToken: "ab".repeat(32), environment: "sandbox", language: "ru" }), env, ctx);
      expect(bad.status).toBe(400);
      expect(await bad.json()).toEqual({ error: "invalid", reason: "code" });
    } finally {
      globalThis.fetch = original;
    }
  });

  it("refuses bad fields, a missing assertion and a server without its secrets", async () => {
    const { env } = await setup();
    const fields = await worker.fetch(request("POST", "/v1/alerts", { code: "v3.abc", pushToken: "nothex", environment: "sandbox", language: "ru" }), env, ctx);
    expect(fields.status).toBe(400);
    const unsigned = await worker.fetch(new Request("https://assistant.example/v1/alerts", { method: "DELETE", body: "{}" }), env, ctx);
    expect(unsigned.status).toBe(401);
    const bare = await setup(false);
    const off = await worker.fetch(request("DELETE", "/v1/alerts", {}), bare.env, ctx);
    expect(off.status).toBe(503);
    expect(await off.json()).toEqual({ error: "alerts_unavailable" });
  });

  it("updates the device token, and turns off", async () => {
    const { storage, env } = await setup();
    const missing = await worker.fetch(request("PUT", "/v1/alerts/token", { pushToken: "cd".repeat(32), environment: "production" }), env, ctx);
    expect(missing.status).toBe(404);
    storage.data.set("sub", { pushToken: "ab".repeat(32), environment: "sandbox" });
    const updated = await worker.fetch(request("PUT", "/v1/alerts/token", { pushToken: "cd".repeat(32), environment: "production" }), env, ctx);
    expect(updated.status).toBe(200);
    expect(storage.data.get("sub")).toEqual({ pushToken: "cd".repeat(32), environment: "production" });
    const off = await worker.fetch(request("DELETE", "/v1/alerts", {}), env, ctx);
    expect(off.status).toBe(200);
    expect(storage.data.size).toBe(0);
  });
});
