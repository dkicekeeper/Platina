import type Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import type { Params } from "../src/claude";
import { readConfig } from "../src/config";
import { normalizeUrl, type ModelCall } from "../src/guide";
import type { GuideGame, GuideTrophy } from "../src/validate";
import {
  addSeen,
  buildChapter,
  buildWalkthrough,
  chapterKey,
  checkChapter,
  checkWalkthrough,
  emptySeen,
  readChapter,
  SAVE_CHAPTER,
  SAVE_WALKTHROUGH,
  storeChapter,
  storeWalkthrough,
  walkthroughKey,
  WalkthroughError,
  type Seen,
  type Walkthrough,
  type WalkthroughProgress,
} from "../src/walkthrough";
import { eventsOf, fetchResult, fetchUse, MemoryKV, message, searchResult, searchUse, toolUse } from "./helpers";

const trophies: GuideTrophy[] = [
  { id: 0, name: "Platinum", detail: "Get every trophy.", type: "platinum", hidden: false, groupId: "default" },
  { id: 1, name: "Arrival", detail: "Finish chapter 1.", type: "bronze", hidden: false, groupId: "default" },
  { id: 2, name: "Collector", detail: "Find every relic.", type: "gold", hidden: false, groupId: "default" },
  { id: 3, name: "The Betrayal Revealed", detail: "Story related.", type: "silver", hidden: true, groupId: "default" },
  { id: 4, name: "Merciful", detail: "Spare the knight.", type: "bronze", hidden: false, groupId: "default" },
];
const game: GuideGame = { npCommunicationId: "NPWR12345_00", name: "Test Game", platform: "PS5", trophies };

const WALK_URL = "https://www.powerpyx.com/test-game-walkthrough/";
const CHAPTER_URL = "https://www.powerpyx.com/test-game-chapter-1-relic-locations/";
const IMAGE = "https://www.powerpyx.com/wp-content/uploads/test-game-relic-1.jpg";
const OTHER_IMAGE = "https://images.example.com/relic.jpg";
const VIDEO = "dQw4w9WgXcQ";

const seenWith = (...urls: string[]): Seen => {
  const seen = emptySeen();
  for (const url of urls) seen.urls.add(normalizeUrl(url)!);
  return seen;
};

const overviewDraft = () => ({
  overview: "Один проход и зачистка через выбор глав.",
  playthroughs: 1,
  chapters: [
    {
      id: "c1",
      title: "Пролог",
      summary: "Обучение в деревне.",
      missable: [{ trophyId: 4, note: "Пощади рыцаря в конце главы." }],
      choices: ["Пощадить рыцаря"],
      collectibles: [{ kind: "Реликвии", count: 3 }],
      trophyIds: [1, 4],
      completionTrophyId: 1,
      playthrough: 1,
      sourceIds: ["w1"],
    },
    {
      id: "c2",
      title: "Замок",
      summary: "Штурм замка.",
      missable: [],
      choices: [],
      collectibles: [],
      trophyIds: [3],
      completionTrophyId: null,
      playthrough: 1,
      sourceIds: [],
    },
  ],
  cleanup: "Добери реликвии через выбор глав.",
  sources: [{ id: "w1", title: "PowerPyx: walkthrough", url: WALK_URL }],
});

const chapterDraft = () => ({
  steps: [
    { kind: "path", text: "Иди **налево** от колодца.", trophyIds: [], spoiler: false, collectible: null, sourceId: "w1", imageUrl: null, video: null },
    {
      kind: "collectible",
      text: "Реликвия 1 за бочками.",
      trophyIds: [2],
      spoiler: false,
      collectible: { kind: "Реликвия", number: 1 },
      sourceId: "w1",
      imageUrl: IMAGE,
      video: { youtubeId: VIDEO, startSeconds: 95 },
    },
    { kind: "choice", text: "Пощади рыцаря.", trophyIds: [4], spoiler: false, collectible: null, sourceId: null, imageUrl: null, video: null },
  ],
  sources: [{ id: "w1", title: "PowerPyx: chapter 1", url: CHAPTER_URL }],
});

describe("checkWalkthrough", () => {
  it("accepts a plan built from what the model saw", () => {
    const { problems, draft } = checkWalkthrough(overviewDraft(), { trophies, seen: seenWith(WALK_URL), language: "ru" });
    expect(problems).toEqual([]);
    expect(draft.chapters.map((c) => c.id)).toEqual(["c1", "c2"]);
    expect(draft.chapters[0]).toMatchObject({ completionTrophyId: 1, missable: [{ trophyId: 4 }], collectibles: [{ kind: "Реликвии", count: 3 }] });
  });

  it("finds trophies not in the list, pages never seen, repeated chapters and hidden names", () => {
    const input = overviewDraft();
    input.chapters[0]!.trophyIds = [1, 99];
    input.chapters[1]!.id = "c1";
    input.overview = "Не пропусти The Betrayal Revealed.";
    const { problems, draft } = checkWalkthrough(input, { trophies, seen: emptySeen(), language: "ru" });
    expect(problems.some((p) => p.includes("99 is not in the trophy list"))).toBe(true);
    expect(problems.some((p) => p.includes("not a page you saw"))).toBe(true);
    expect(problems.some((p) => p.includes("chapters[1]: id must be unique"))).toBe(true);
    expect(problems.some((p) => p.includes('hidden trophy "The Betrayal Revealed"'))).toBe(true);
    expect(draft.overview).toBe("Не пропусти скрытый трофей.");
    expect(draft.chapters).toHaveLength(1);
    expect(draft.chapters[0]!.sourceIds).toEqual([]);
  });
});

describe("checkChapter", () => {
  const seen = () => {
    const s = seenWith(CHAPTER_URL);
    s.images.add(normalizeUrl(IMAGE)!);
    s.images.add(normalizeUrl(OTHER_IMAGE)!);
    s.videos.add(VIDEO);
    return s;
  };
  const context = (extra: Partial<Parameters<typeof checkChapter>[1]> = {}) => ({
    trophies,
    seen: seen(),
    language: "ru" as const,
    imageSites: ["powerpyx.com", "psnprofiles.com"],
    ...extra,
  });

  it("keeps steps, numbered, with the picture and the video the model saw", () => {
    const { problems, draft } = checkChapter(chapterDraft(), context());
    expect(problems).toEqual([]);
    expect(draft.steps.map((s) => s.id)).toEqual(["s1", "s2", "s3"]);
    expect(draft.steps[1]).toMatchObject({
      kind: "collectible",
      collectible: { kind: "Реликвия", number: 1 },
      image: { url: IMAGE, sourceId: "w1" },
      video: { youtubeId: VIDEO, startSeconds: 95 },
    });
  });

  it("drops a picture from a site off the list, or never seen, and a video never seen", () => {
    const input = chapterDraft();
    input.steps[1]!.imageUrl = OTHER_IMAGE;
    input.steps[2]!.imageUrl = "https://www.powerpyx.com/wp-content/uploads/made-up.jpg";
    input.steps[2]!.video = { youtubeId: "aaaaaaaaaaa", startSeconds: 0 };
    const { problems, draft } = checkChapter(input, context());
    expect(problems).toEqual([]);
    expect(draft.steps[1]!.image).toBeNull();
    expect(draft.steps[2]!.image).toBeNull();
    expect(draft.steps[2]!.video).toBeNull();
    expect(checkChapter(chapterDraft(), context({ imageSites: [] })).draft.steps[1]!.image).toBeNull();
  });

  it("hides a step that earns or names a hidden trophy", () => {
    const input = chapterDraft();
    input.steps.push({ kind: "trophy", text: "Сюжетный трофей.", trophyIds: [3], spoiler: false, collectible: null, sourceId: null, imageUrl: null, video: null });
    input.steps.push({ kind: "tip", text: "Тут The Betrayal Revealed.", trophyIds: [], spoiler: false, collectible: null, sourceId: null, imageUrl: null, video: null });
    const { draft } = checkChapter(input, context());
    expect(draft.steps[3]!.spoiler).toBe(true);
    expect(draft.steps[4]!.spoiler).toBe(true);
    expect(draft.steps[0]!.spoiler).toBe(false);
  });

  it("finds an unknown kind and a missing text", () => {
    const input = chapterDraft() as { steps: Record<string, unknown>[]; sources: unknown[] };
    input.steps[0]!.kind = "dance";
    input.steps[1]!.text = "";
    const { problems, draft } = checkChapter(input, context());
    expect(problems).toHaveLength(2);
    expect(draft.steps).toHaveLength(1);
  });
});

describe("addSeen", () => {
  it("collects pages, their pictures, links and videos from search, fetch and filtering code", () => {
    const seen = emptySeen();
    addSeen(seen, [
      searchResult("srv_1", [WALK_URL]),
      fetchResult("srv_2", CHAPTER_URL, `Relic 1 ![relic](${IMAGE}) see https://youtu.be/${VIDEO}?t=95 and https://psnprofiles.com/guide/1-test.`),
      {
        type: "code_execution_tool_result",
        tool_use_id: "srv_3",
        content: { type: "code_execution_result", stdout: "found https://stratege.ru/ps5/games/test/walkthrough", stderr: "", return_code: 0, content: [] },
      } as unknown as Anthropic.Beta.BetaContentBlock,
    ]);
    expect(seen.urls.has(normalizeUrl(WALK_URL)!)).toBe(true);
    expect(seen.urls.has(normalizeUrl(CHAPTER_URL)!)).toBe(true);
    expect(seen.urls.has(normalizeUrl("https://psnprofiles.com/guide/1-test")!)).toBe(true);
    expect(seen.urls.has(normalizeUrl("https://stratege.ru/ps5/games/test/walkthrough")!)).toBe(true);
    expect(seen.images.has(normalizeUrl(IMAGE)!)).toBe(true);
    expect(seen.videos.has(VIDEO)).toBe(true);
  });
});

// MARK: - Builds

function scripted(...messages: Anthropic.Beta.BetaMessage[]) {
  const params: Params[] = [];
  const call: ModelCall = async (p, onEvent) => {
    params.push(structuredClone(p));
    const next = messages.shift();
    if (!next) throw new Error("no more scripted messages");
    for (const event of eventsOf(next)) onEvent(event);
    return next;
  };
  return { call, params };
}

const NOW = new Date("2026-11-23T12:00:00Z");

describe("buildWalkthrough", () => {
  it("searches, reads a page, saves the plan; fetches only guide sites", async () => {
    const { call, params } = scripted(
      message(
        [searchUse("srv_1", "Test Game walkthrough"), searchResult("srv_1", [WALK_URL]), fetchUse("srv_2", WALK_URL), fetchResult("srv_2", WALK_URL, "Chapter 1: Prologue"), toolUse("toolu_1", SAVE_WALKTHROUGH, overviewDraft())],
        "tool_use",
      ),
    );
    const steps: WalkthroughProgress[] = [];
    const { walkthrough, calls } = await buildWalkthrough(game, "ru", { config: readConfig({}), call, kv: new MemoryKV(), now: NOW, onProgress: (s) => void steps.push(s) });

    expect(calls).toBe(1);
    expect(steps).toEqual(["search", "reading", "writing"]);
    expect(walkthrough).toMatchObject({ gameId: "NPWR12345_00", language: "ru", generatedAt: "2026-11-23T12:00:00Z", playthroughs: 1 });
    expect(walkthrough.chapters).toHaveLength(2);
    const tools = params[0]!.tools as { type: string; name: string; allowed_domains?: string[]; max_uses?: number }[];
    expect(tools.slice(0, 2).map((t) => t.type)).toEqual(["web_search_20260209", "web_fetch_20260209"]);
    expect(tools[1]).toMatchObject({ name: "web_fetch", max_uses: 4 });
    expect(tools[1]!.allowed_domains).toContain("powerpyx.com");
    expect(tools[2]!.name).toBe(SAVE_WALKTHROUGH);
    const input = (params[0]!.messages[0]!.content as string);
    expect(input).toContain("Write the walkthrough plan in Russian");
    expect(input).toContain('"hidden":true');
  });

  it("asks once for a fix, then saves what is usable", async () => {
    const bad = overviewDraft();
    bad.chapters[0]!.trophyIds = [99];
    const { call, params } = scripted(
      message([searchUse("srv_1", "q"), searchResult("srv_1", [WALK_URL]), toolUse("toolu_1", SAVE_WALKTHROUGH, bad)], "tool_use"),
      message([toolUse("toolu_2", SAVE_WALKTHROUGH, bad)], "tool_use"),
    );
    const { walkthrough, calls } = await buildWalkthrough(game, "ru", { config: readConfig({}), call, kv: new MemoryKV(), now: NOW, onProgress: () => {} });
    expect(calls).toBe(2);
    expect(walkthrough.chapters[0]!.trophyIds).toEqual([]);
    const correction = params[1]!.messages.at(-1)!.content as { type: string; is_error: boolean; content: string }[];
    expect(correction[0]).toMatchObject({ type: "tool_result", is_error: true });
    expect(correction[0]!.content).toContain("99 is not in the trophy list");
  });

  it("may cite the cached guide's pages without searching", async () => {
    const kv = new MemoryKV();
    await kv.put(
      "NPWR12345_00:ru",
      JSON.stringify({ gameId: "NPWR12345_00", language: "ru", summary: { overview: "Лёгкая.", playthroughs: 1 }, steps: [], missable: [], tips: [], sources: [{ id: "w1", title: "PowerPyx", url: WALK_URL }], stratege: null }),
    );
    const { call, params } = scripted(message([toolUse("toolu_1", SAVE_WALKTHROUGH, overviewDraft())], "tool_use"));
    const { walkthrough } = await buildWalkthrough(game, "ru", { config: readConfig({}), call, kv, now: NOW, onProgress: () => {} });
    expect(walkthrough.sources).toEqual([{ id: "w1", title: "PowerPyx: walkthrough", url: WALK_URL }]);
    expect(params[0]!.messages[0]!.content as string).toContain(`source: PowerPyx ${WALK_URL}`);
  });

  it("stops on a refusal", async () => {
    const { call } = scripted(message([], "refusal"));
    await expect(buildWalkthrough(game, "ru", { config: readConfig({}), call, kv: new MemoryKV(), onProgress: () => {} })).rejects.toMatchObject({ code: "refused" });
  });
});

describe("buildChapter", () => {
  const stored = (): Walkthrough => ({ gameId: "NPWR12345_00", language: "ru", generatedAt: "2026-11-22T10:00:00Z", ...overviewDraft() });

  it("needs the plan first, and a chapter in it", async () => {
    const { call } = scripted();
    const options = { config: readConfig({}), call, kv: new MemoryKV(), onProgress: () => {} };
    await expect(buildChapter(game, "ru", "c1", options)).rejects.toEqual(new WalkthroughError("no_walkthrough", false));
    await storeWalkthrough(options.kv, stored());
    await expect(buildChapter(game, "ru", "c9", options)).rejects.toMatchObject({ code: "unknown_chapter" });
  });

  it("reads the chapter's page and saves its steps against the plan", async () => {
    const kv = new MemoryKV();
    await storeWalkthrough(kv, stored());
    const { call, params } = scripted(
      message(
        [
          fetchUse("srv_1", CHAPTER_URL),
          fetchResult("srv_1", CHAPTER_URL, `Relic 1 behind the barrels ${IMAGE} https://www.youtube.com/watch?v=${VIDEO}`),
          toolUse("toolu_1", SAVE_CHAPTER, chapterDraft()),
        ],
        "tool_use",
      ),
    );
    const { chapter } = await buildChapter(game, "ru", "c1", { config: readConfig({}), call, kv, now: NOW, onProgress: () => {} });
    expect(chapter).toMatchObject({ chapterId: "c1", walkthroughGeneratedAt: "2026-11-22T10:00:00Z", generatedAt: "2026-11-23T12:00:00Z" });
    expect(chapter.steps[1]!.image).toEqual({ url: IMAGE, sourceId: "w1" });
    expect(chapter.steps[1]!.video).toEqual({ youtubeId: VIDEO, startSeconds: 95 });
    const input = params[0]!.messages[0]!.content as string;
    expect(input).toContain("c1. Пролог <- this chapter");
    expect(input).toContain("missable (trophy 4): Пощади рыцаря");
    expect(input).toContain(`w1: PowerPyx: walkthrough ${WALK_URL}`);
    const system = (params[0]!.system as { text: string }[])[0]!.text;
    expect(system).toContain("powerpyx.com, psnprofiles.com, stratege.ru, playstationtrophies.org");

    // Kept, and stale once the plan is rebuilt.
    await storeChapter(kv, chapter);
    expect(kv.ttls.get(chapterKey("NPWR12345_00", "ru", "c1"))).toBe(30 * 24 * 3600);
    expect(await readChapter(kv, "NPWR12345_00", "ru", "c1")).toEqual(chapter);
    await storeWalkthrough(kv, { ...stored(), generatedAt: "2026-11-24T10:00:00Z" });
    expect(await readChapter(kv, "NPWR12345_00", "ru", "c1")).toBeUndefined();
    expect(kv.store.has(walkthroughKey("NPWR12345_00", "ru"))).toBe(true);
  });

  it("asks for pictures only from IMAGE_SOURCES, and none when it is empty", async () => {
    const kv = new MemoryKV();
    await storeWalkthrough(kv, stored());
    const { call, params } = scripted(message([toolUse("toolu_1", SAVE_CHAPTER, { ...chapterDraft(), sources: [] })], "tool_use"));
    const { chapter } = await buildChapter(game, "ru", "c1", { config: readConfig({ IMAGE_SOURCES: "" }), call, kv, onProgress: () => {} });
    expect((params[0]!.system as { text: string }[])[0]!.text).toContain("imageUrl: always null.");
    expect(chapter.steps.every((s) => s.image === null)).toBe(true);
  });
});
