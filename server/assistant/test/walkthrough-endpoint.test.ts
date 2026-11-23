import { beforeEach, describe, expect, it, vi } from "vitest";
import { SAVE_CHAPTER, SAVE_WALKTHROUGH, WALKTHROUGH_PROMPT_VERSION } from "../src/walkthrough";
import { fetchResult, fetchUse, MemoryKV, message, parseSSE, scriptedStream, searchResult, searchUse, toolUse } from "./helpers";

// POST /v1/walkthrough and /v1/walkthrough/chapter, GET their cached forms, with a fake client.
const scripted = vi.hoisted(() => ({ streams: [] as (() => unknown)[], params: [] as unknown[] }));

vi.mock("@anthropic-ai/sdk", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@anthropic-ai/sdk")>();
  const Real = actual.default;
  class FakeAnthropic extends Real {
    constructor(options: ConstructorParameters<typeof Real>[0]) {
      super(options);
      Object.defineProperty(this, "beta", {
        value: {
          messages: {
            stream: (params: unknown) => {
              scripted.params.push(params);
              return scripted.streams.shift()!();
            },
          },
        },
      });
    }
  }
  return { ...actual, default: FakeAnthropic };
});

const { default: worker } = await import("../src/index");

const WALK_URL = "https://www.powerpyx.com/test-game-walkthrough/";
const GAME_ID = "NPWR12345_00";

const plan = {
  overview: "Один проход.",
  playthroughs: 1,
  chapters: [
    { id: "c1", title: "Пролог", summary: "Деревня.", missable: [], choices: [], collectibles: [], trophyIds: [1], completionTrophyId: 1, playthrough: 1, sourceIds: ["w1"] },
  ],
  cleanup: "",
  sources: [{ id: "w1", title: "PowerPyx: walkthrough", url: WALK_URL }],
};
const steps = {
  steps: [{ kind: "path", text: "Иди налево.", trophyIds: [], spoiler: false, collectible: null, sourceId: "w1", imageUrl: null, video: null }],
  sources: [{ id: "w1", title: "PowerPyx: walkthrough", url: WALK_URL }],
};

const game = {
  npCommunicationId: GAME_ID,
  name: "Test Game",
  platform: "PS5",
  trophies: [
    { id: 0, name: "Платина", detail: "Все трофеи.", type: "platinum", hidden: false, groupId: "default" },
    { id: 1, name: "Прибытие", detail: "Пройти пролог.", type: "bronze", hidden: false, groupId: "default" },
  ],
};

const post = (path: string, extra: Record<string, unknown> = {}) =>
  new Request(`https://assistant.example${path}`, {
    method: "POST",
    headers: { "x-platina-dev": "dev" },
    body: JSON.stringify({ protocol: 1, language: "ru", refresh: false, game, ...extra }),
  });

async function run(kv: { guides: MemoryKV; quota: MemoryKV }, request: Request) {
  const pending: Promise<unknown>[] = [];
  const ctx = { waitUntil: (p: Promise<unknown>) => pending.push(p), passThroughOnException() {} } as never;
  const env = { ATTEST: new MemoryKV(), QUOTA: kv.quota, GUIDES: kv.guides, ANTHROPIC_API_KEY: "test", DEV_TOKEN: "dev" } as never;
  const response = await worker.fetch(request, env, ctx);
  const text = await response.text();
  await Promise.all(pending);
  return { response, text, events: response.headers.get("content-type") === "text/event-stream" ? parseSSE(text) : [] };
}

describe("walkthrough endpoints", () => {
  beforeEach(() => {
    scripted.streams = [];
    scripted.params = [];
  });

  it("builds the plan, keeps it, serves it from the cache and by GET", async () => {
    scripted.streams.push(() =>
      scriptedStream(
        message(
          [searchUse("srv_1", "Test Game walkthrough"), searchResult("srv_1", [WALK_URL]), fetchUse("srv_2", WALK_URL), fetchResult("srv_2", WALK_URL, "Prologue"), toolUse("toolu_1", SAVE_WALKTHROUGH, plan)],
          "tool_use",
        ),
      ),
    );
    const kv = { guides: new MemoryKV(), quota: new MemoryKV() };
    const { response, events } = await run(kv, post("/v1/walkthrough"));

    expect(response.headers.get("x-platina-prompt")).toBe(WALKTHROUGH_PROMPT_VERSION);
    expect(events.map((e) => e.event)).toEqual(["progress", "progress", "progress", "walkthrough"]);
    expect(events.slice(0, 3).map((e) => e.data.step)).toEqual(["search", "reading", "writing"]);
    const walkthrough = events[3]!.data;
    expect(walkthrough).toMatchObject({ gameId: GAME_ID, language: "ru", chapters: [{ id: "c1", title: "Пролог" }] });
    expect(JSON.parse(kv.guides.store.get(`walk:${GAME_ID}:ru`)!)).toEqual(walkthrough);
    const day = new Date().toISOString().slice(0, 10);
    expect(kv.quota.store.get(`guides:dev:${day}`)).toBe("1");

    const again = await run(kv, post("/v1/walkthrough"));
    expect(again.events).toEqual([{ event: "walkthrough", data: walkthrough }]);
    expect(scripted.params).toHaveLength(1);

    const got = await run(kv, new Request(`https://assistant.example/v1/walkthrough/${GAME_ID}?language=ru`));
    expect(JSON.parse(got.text)).toEqual(walkthrough);
    const none = await run(kv, new Request(`https://assistant.example/v1/walkthrough/${GAME_ID}?language=en`));
    expect(none.response.status).toBe(404);
  });

  it("builds a chapter only after the plan, and serves it by GET", async () => {
    const kv = { guides: new MemoryKV(), quota: new MemoryKV() };
    const first = await run(kv, post("/v1/walkthrough/chapter", { chapterId: "c1" }));
    expect(first.events).toEqual([{ event: "error", data: { code: "no_walkthrough", retryable: false } }]);
    // No model ran: the build is given back.
    const day = new Date().toISOString().slice(0, 10);
    expect(kv.quota.store.get(`guides:dev:${day}`)).toBe("0");

    kv.guides.store.set(`walk:${GAME_ID}:ru`, JSON.stringify({ gameId: GAME_ID, language: "ru", generatedAt: "2026-11-22T10:00:00Z", ...plan }));
    scripted.streams.push(() => scriptedStream(message([toolUse("toolu_1", SAVE_CHAPTER, steps)], "tool_use")));
    const { events } = await run(kv, post("/v1/walkthrough/chapter", { chapterId: "c1" }));
    expect(events.map((e) => e.event)).toEqual(["progress", "chapter"]);
    expect(events[1]!.data).toMatchObject({ chapterId: "c1", walkthroughGeneratedAt: "2026-11-22T10:00:00Z", steps: [{ id: "s1", kind: "path" }] });

    const got = await run(kv, new Request(`https://assistant.example/v1/walkthrough/${GAME_ID}/chapter/c1?language=ru`));
    expect(JSON.parse(got.text)).toEqual(events[1]!.data);
  });

  it("refuses a bad chapter id and a bad game id", async () => {
    const kv = { guides: new MemoryKV(), quota: new MemoryKV() };
    const bad = await run(kv, post("/v1/walkthrough/chapter", { chapterId: "chapter-1" }));
    expect(bad.response.status).toBe(400);
    expect(JSON.parse(bad.text)).toEqual({ error: "invalid", reason: "chapter_id" });
    const badGet = await run(kv, new Request(`https://assistant.example/v1/walkthrough/${GAME_ID}/chapter/x?language=ru`));
    expect(badGet.response.status).toBe(400);
    const badGame = await run(kv, new Request("https://assistant.example/v1/walkthrough/nope?language=ru"));
    expect(badGame.response.status).toBe(400);
  });

  it("reports the walkthrough prompt in health", async () => {
    const { text } = await run({ guides: new MemoryKV(), quota: new MemoryKV() }, new Request("https://assistant.example/v1/health"));
    expect(JSON.parse(text)).toMatchObject({ ok: true, walkthrough_prompt: WALKTHROUGH_PROMPT_VERSION });
  });
});
