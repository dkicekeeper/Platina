import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SAVE_GUIDE } from "../src/guide";
import { fixture, MemoryKV, message, parseSSE, scriptedStream, searchResult, searchUse, toolUse } from "./helpers";

// POST /v1/guide with a fake Anthropic client and a fake stratege.ru.
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

const { default: Anthropic } = await import("@anthropic-ai/sdk");
const { default: worker } = await import("../src/index");

const COTL_URL = "https://stratege.ru/ps5/games/cult_of_the_lamb/trophies/spisok";
const POWERPYX = "https://www.powerpyx.com/cult-of-the-lamb-trophy-guide-roadmap/";
const cotlHtml = fixture("stratege-cult-of-the-lamb.html");

const draft = {
  summary: { difficulty: 4, hoursMin: 10, hoursMax: 15, playthroughs: 1, onlineTrophies: 0, missableTrophies: 1, glitchedTrophies: 0, difficultyAffects: false, overview: "Лёгкая платина." },
  steps: [{ title: "Шаг 1. Сюжет", text: "Пройди сюжет.", trophyIds: [0, 1] }],
  missable: [{ trophyId: 1, note: "До финала." }],
  tips: [{ trophyId: 1, text: "Смотри роадмап.", sourceIds: ["w1"] }],
  sources: [{ id: "w1", title: "PowerPyx: roadmap", url: POWERPYX }],
};

const request = (refresh = false) => {
  const payload = JSON.stringify({
    protocol: 1,
    language: "ru",
    refresh,
    game: {
      npCommunicationId: "NPWR28536_00",
      name: "Cult of the Lamb",
      platform: "PS5",
      trophySetVersion: "01.20",
      trophies: [
        { id: 0, name: "Божественность", detail: "Настало время слуге стать божеством.", type: "platinum", hidden: false, groupId: "default" },
        { id: 1, name: "Первый последователь", detail: "Найти первого служителя культа ягнёнка.", type: "bronze", hidden: false, groupId: "default" },
      ],
    },
  });
  return new Request("https://assistant.example/v1/guide", { method: "POST", headers: { "x-platina-dev": "dev" }, body: payload });
};

async function run(kv: { guides: MemoryKV; quota: MemoryKV }, refresh = false) {
  const pending: Promise<unknown>[] = [];
  const ctx = { waitUntil: (p: Promise<unknown>) => pending.push(p), passThroughOnException() {} } as never;
  const env = { ATTEST: new MemoryKV(), QUOTA: kv.quota, GUIDES: kv.guides, ANTHROPIC_API_KEY: "test", DEV_TOKEN: "dev" } as never;
  const response = await worker.fetch(request(refresh), env, ctx);
  const text = await response.text();
  await Promise.all(pending);
  return { response, events: parseSSE(text) };
}

const fetched: string[] = [];

describe("POST /v1/guide", () => {
  beforeEach(() => {
    scripted.streams = [];
    scripted.params = [];
    fetched.length = 0;
    vi.stubGlobal("fetch", async (input: RequestInfo | URL) => {
      fetched.push(String(input));
      return String(input) === `${COTL_URL}?nax=1` ? new Response(cotlHtml) : new Response("", { status: 404 });
    });
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("builds the guide: progress, then the guide, kept for 30 days", async () => {
    scripted.streams.push(() =>
      scriptedStream(message([searchUse("srv_1", "Cult of the Lamb roadmap"), searchResult("srv_1", [POWERPYX]), toolUse("toolu_1", SAVE_GUIDE, draft)], "tool_use")),
    );
    const kv = { guides: new MemoryKV(), quota: new MemoryKV() };
    const { response, events } = await run(kv);

    expect(response.headers.get("content-type")).toBe("text/event-stream");
    expect(events.map((e) => e.event)).toEqual(["progress", "progress", "progress", "guide"]);
    expect(events.slice(0, 3).map((e) => e.data.step)).toEqual(["stratege", "search", "writing"]);
    const guide = events[3]!.data;
    expect(guide).toMatchObject({
      gameId: "NPWR28536_00",
      language: "ru",
      summary: { difficulty: 4, overview: "Лёгкая платина." },
      sources: [{ id: "w1", url: POWERPYX }],
      stratege: { url: COTL_URL, averagePlatinumHours: 49, platinumPercent: 16.58 },
    });
    expect(JSON.parse(kv.guides.store.get("NPWR28536_00:ru")!)).toEqual(guide);
    expect(kv.guides.ttls.get("NPWR28536_00:ru")).toBe(30 * 24 * 3600);
    expect(fetched).toEqual([`${COTL_URL}?nax=1`]);
    const day = new Date().toISOString().slice(0, 10);
    expect(kv.quota.store.get(`guides:dev:${day}`)).toBe("1");
    expect(kv.quota.store.get(`calls:all:${day}`)).toBe("50");
    expect((scripted.params[0] as { model: string }).model).toBe("claude-sonnet-5-5");

    // The next request is served from the cache: no model, no Stratege, no count.
    const again = await run(kv);
    expect(again.events).toEqual([{ event: "guide", data: guide }]);
    expect(scripted.params).toHaveLength(1);
    expect(kv.quota.store.get(`guides:dev:${day}`)).toBe("1");
  });

  it("reports a failure the app can retry, and gives the build back when the model never started", async () => {
    scripted.streams.push(() => ({
      abort() {},
      async *[Symbol.asyncIterator]() {
        throw new Anthropic.APIConnectionError({ message: "down" });
      },
      finalMessage: async () => {
        throw new Anthropic.APIConnectionError({ message: "down" });
      },
    }));
    const kv = { guides: new MemoryKV(), quota: new MemoryKV() };
    const { events } = await run(kv);
    expect(events).toEqual([
      { event: "progress", data: { step: "stratege" } },
      { event: "error", data: { code: "upstream_unavailable", retryable: true } },
    ]);
    const day = new Date().toISOString().slice(0, 10);
    expect(kv.quota.store.get(`guides:dev:${day}`)).toBe("0");
    expect(kv.guides.store.has("NPWR28536_00:ru")).toBe(false);
    // The Stratege page read on the way is kept all the same.
    expect(kv.guides.store.has("stratege:NPWR28536_00")).toBe(true);
  });

  it("says so when the model refuses", async () => {
    scripted.streams.push(() => scriptedStream(message([], "refusal")));
    const { events } = await run({ guides: new MemoryKV(), quota: new MemoryKV() });
    expect(events.at(-1)).toEqual({ event: "error", data: { code: "refused", retryable: false } });
  });
});
