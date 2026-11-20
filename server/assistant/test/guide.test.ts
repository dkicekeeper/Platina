import type Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import type { Params } from "../src/claude";
import { readConfig } from "../src/config";
import {
  buildGuide,
  buildGuideInput,
  checkGuide,
  GuideError,
  guideParams,
  normalizeUrl,
  SAVE_GUIDE,
  strategeSearchParams,
  type BuildOptions,
  type CheckContext,
  type GuideProgress,
  type ModelCall,
} from "../src/guide";
import { parseStrategePage } from "../src/stratege";
import type { GuideGame, GuideTrophy } from "../src/validate";
import { eventsOf, fixture, MemoryKV, message, searchResult, searchUse, textBlock, toolUse } from "./helpers";

const COTL_URL = "https://stratege.ru/ps5/games/cult_of_the_lamb/trophies/spisok";
const cotlHtml = fixture("stratege-cult-of-the-lamb.html");
const stratege = parseStrategePage(cotlHtml, COTL_URL, "NPWR28536_00");
const HIDDEN = new Set([18, 49, 53, 56]);

// The game as the app sends it: PSN's trophy list in Russian, four hidden trophies, DLC in 001.
const trophies: GuideTrophy[] = stratege.trophies.map((t) => ({
  id: t.number!,
  name: t.names[1] ?? t.names[0]!,
  detail: t.description,
  type: t.type!,
  hidden: HIDDEN.has(t.number!),
  groupId: t.number! >= 37 ? "001" : "default",
}));
const game: GuideGame = { npCommunicationId: "NPWR28536_00", name: "Cult of the Lamb", platform: "PS5", trophySetVersion: "01.20", trophies };

const POWERPYX = "https://www.powerpyx.com/cult-of-the-lamb-trophy-guide-roadmap/";
const masterOfChanceTip = stratege.trophies[36]!.tips[0]!;

const validDraft = () => ({
  summary: {
    difficulty: 4,
    hoursMin: 10,
    hoursMax: 15,
    playthroughs: 1,
    onlineTrophies: 0,
    missableTrophies: 1,
    glitchedTrophies: 0,
    difficultyAffects: false,
    overview: "Лёгкая и приятная платина: сюжет, зачистка и немного гринда.",
  },
  steps: [
    { title: "Шаг 1. Сюжет", text: "Пройди сюжет, **сыграй в кости со всеми**.", trophyIds: [1, 2, 3, 49] },
    { title: "Шаг 2. Зачистка", text: "Добей коллекции.", trophyIds: [21, 22, 36] },
  ],
  missable: [{ trophyId: 36, note: "Обыграй всех игроков в кости до финала." }],
  tips: [
    { trophyId: 36, text: "Играй в кости с каждым, пока они не ушли.", sourceIds: [`st${masterOfChanceTip.id}`] },
    { trophyId: 21, text: "Облики покупаются у паука.", sourceIds: ["w1"] },
  ],
  sources: [{ id: "w1", title: "PowerPyx: roadmap", url: POWERPYX }],
});

/** The same guide citing Stratege only: for builds whose model made no web search. */
const strategeOnlyDraft = () => {
  const draft = validDraft();
  return { ...draft, tips: draft.tips.filter((t) => !t.sourceIds.includes("w1")), sources: [] };
};

const context = (extra: Partial<CheckContext> = {}): CheckContext => ({
  trophies,
  strategeTips: new Map([[masterOfChanceTip.id, { author: masterOfChanceTip.author, url: stratege.trophies[36]!.url }]]),
  allowedUrls: new Set([normalizeUrl(POWERPYX)!, normalizeUrl(COTL_URL)!]),
  language: "ru",
  ...extra,
});

describe("checkGuide", () => {
  it("accepts a valid guide and fills in a cited Stratege tip's source", () => {
    const { problems, draft } = checkGuide(validDraft(), context());
    expect(problems).toEqual([]);
    expect(draft.sources).toEqual([
      { id: "w1", title: "PowerPyx: roadmap", url: POWERPYX },
      { id: `st${masterOfChanceTip.id}`, title: `Stratege.ru: подсказка от ${masterOfChanceTip.author}`, url: "https://stratege.ru/ps5/trophies/cult_of_the_lamb/spisok/master_of_chance" },
    ]);
  });

  it("refuses trophy ids outside the list and drops them", () => {
    const input = validDraft();
    input.steps[0]!.trophyIds.push(999);
    input.missable.push({ trophyId: 1000, note: "x" });
    input.tips.push({ trophyId: -1, text: "x", sourceIds: [] });
    const { problems, draft } = checkGuide(input, context());
    expect(problems).toEqual([
      "steps[0].trophyIds: 999 is not in the trophy list",
      "missable[1]: trophyId 1000 is not in the trophy list",
      "tips[2]: trophyId -1 is not in the trophy list",
    ]);
    expect(draft.steps[0]!.trophyIds).toEqual([1, 2, 3, 49]);
    expect(draft.missable).toHaveLength(1);
    expect(draft.tips).toHaveLength(2);
  });

  it("keeps numbers in range, null when unknown", () => {
    const input = validDraft();
    Object.assign(input.summary, { difficulty: 11, hoursMin: 20, hoursMax: 10, playthroughs: 0, onlineTrophies: 58 });
    const { problems, draft } = checkGuide(input, context());
    expect(problems).toHaveLength(4);
    expect(problems[0]).toMatch(/^summary\.difficulty: 11 is out of range/);
    expect(draft.summary).toMatchObject({ difficulty: null, hoursMin: 20, hoursMax: null, playthroughs: null, onlineTrophies: null, missableTrophies: 1 });
    const unknown = validDraft();
    Object.assign(unknown.summary, { difficulty: null, hoursMax: null });
    expect(checkGuide(unknown, context()).problems).toEqual([]);
  });

  it("cites only pages the search returned", () => {
    const input = validDraft();
    input.sources.push({ id: "w2", title: "Made up", url: "https://www.powerpyx.com/made-up-page/" });
    input.tips[1]!.sourceIds.push("w2", "w9");
    const { problems, draft } = checkGuide(input, context());
    expect(problems).toEqual([
      "sources[1] (w2): https://www.powerpyx.com/made-up-page/ is not a page from your search results or the Stratege data; cite only pages you saw",
      "tips[1].sourceIds: w2 is not one of your sources",
      "tips[1].sourceIds: w9 is not one of your sources",
    ]);
    expect(draft.tips[1]!.sourceIds).toEqual(["w1"]);
    // Another spelling of a seen page is the same page.
    expect(normalizeUrl("https://powerpyx.com/cult-of-the-lamb-trophy-guide-roadmap#missables")).toBe(normalizeUrl(POWERPYX));
  });

  it("keeps hidden trophies' names out of the overview and the roadmap", () => {
    const input = validDraft();
    input.steps[0]!.text = "Не пропусти трофей «Блудное дитя» в конце.";
    const { problems, draft } = checkGuide(input, context());
    expect(problems).toEqual(['steps[0] names the hidden trophy 49 ("Блудное дитя"); keep it only in trophyIds']);
    expect(draft.steps[0]!.text).toBe("Не пропусти трофей «скрытый трофей» в конце.");
  });

  it("needs an overview and a roadmap", () => {
    const input = validDraft();
    input.summary.overview = "";
    input.steps = [];
    expect(checkGuide(input, context()).problems).toEqual(["summary.overview: 1 to 1500 characters", "steps: the roadmap needs at least one step"]);
    expect(checkGuide("nonsense", context()).problems.length).toBeGreaterThan(0);
  });
});

describe("the guide model's input", () => {
  const now = new Date("2026-11-20T10:00:00Z");

  it("carries the date, the language, the trophy list and Stratege's data", () => {
    const input = buildGuideInput(game, "ru", stratege, now);
    expect(input).toContain("Today is 2026-11-20. Write the guide in Russian.");
    expect(input).toContain("npCommunicationId: NPWR28536_00");
    expect(input).toContain("trophies: 57 (1 platinum, 4 gold, 21 silver, 31 bronze)");
    expect(input).toContain('{"id":49,"type":"bronze","group":"001","hidden":true,"name":"Блудное дитя"');
    expect(input).toContain(`<stratege url="${COTL_URL}">`);
    expect(input).toContain("platinum earned by 1135 (16.58%); average time to the platinum: 49 hours");
    expect(input).toContain("- Уровень сложности трофеев: 4/10");
    expect(input).toContain("tip st259620 by TailyMile, 09.03.2023 в 12:19, 5 thanks:");
    expect(input).toContain("[trophy 21] Full Flock / Многоликая община: 2 of 16 tips, page https://stratege.ru/ps5/trophies/cult_of_the_lamb/spisok/full_flock");
    expect(input.length).toBeLessThan(90_000);
  });

  it("says when Stratege has nothing", () => {
    const input = buildGuideInput(game, "en", undefined, now);
    expect(input).toContain("Write the guide in English.");
    expect(input).toContain("Stratege.ru has no page for this game.");
  });

  it("goes to the guide model with a strict save_guide and web search", () => {
    const params = guideParams(readConfig({}), [{ role: "user", content: "x" }]);
    expect(params.model).toBe("claude-sonnet-5-5");
    expect(params.tools).toEqual([{ type: "web_search_20260209", name: "web_search", max_uses: 5 }, expect.objectContaining({ name: SAVE_GUIDE, strict: true })]);
    expect(params.fallbacks).toBe("default");
    expect(params.betas).toEqual(["server-side-fallback-2026-07-01"]);
    expect(params.output_config).toEqual({ effort: "medium" });
    expect(guideParams(readConfig({ GUIDE_MAX_SEARCHES: "0" }), []).tools).toHaveLength(1);
    // Strict schemas list every property as required.
    const schema = JSON.stringify(params.tools![1]);
    expect(schema).toContain('"required":["summary","steps","missable","tips","sources"]');
  });
});

// MARK: - The build

/** A model that answers the build's calls in order and records their params. */
function scripted(...replies: Anthropic.Beta.BetaMessage[]) {
  const params: Params[] = [];
  const call: ModelCall = async (p, onEvent) => {
    params.push(structuredClone(p));
    const reply = replies.shift();
    if (!reply) throw new Error("no more replies");
    for (const event of eventsOf(reply)) onEvent(event);
    return reply;
  };
  return { call, params };
}

function strategeSite() {
  const asked: string[] = [];
  const fetcher = (async (input: RequestInfo | URL) => {
    asked.push(String(input));
    return String(input) === `${COTL_URL}?nax=1` ? new Response(cotlHtml) : new Response("", { status: 404 });
  }) as typeof fetch;
  return { fetcher, asked };
}

const searched = () => [searchUse("srv_1", "Cult of the Lamb trophy roadmap"), searchResult("srv_1", [POWERPYX])];
const save = (draft: unknown, id = "toolu_1") => toolUse(id, SAVE_GUIDE, draft as Record<string, unknown>);

function options(call: ModelCall, extra: Partial<BuildOptions> = {}) {
  const progress: GuideProgress[] = [];
  const site = strategeSite();
  const kv = new MemoryKV();
  const built: BuildOptions = {
    config: readConfig({}),
    call,
    fetch: site.fetcher,
    kv,
    refresh: false,
    now: new Date("2026-11-20T10:00:00Z"),
    onProgress: (step) => {
      progress.push(step);
    },
    ...extra,
  };
  return { options: built, progress, asked: site.asked, kv };
}

describe("buildGuide", () => {
  it("reads Stratege, lets the model search and write, and returns the checked guide", async () => {
    const model = scripted(message([...searched(), save(validDraft())], "tool_use", { server_tool_use: { web_search_requests: 1 } } as never));
    const run = options(model.call);
    const result = await buildGuide(game, "ru", run.options);

    expect(run.progress).toEqual(["stratege", "search", "writing"]);
    expect(run.asked).toEqual([`${COTL_URL}?nax=1`]);
    expect(result.calls).toBe(1);
    expect(result.usage.web_search_requests).toBe(1);
    expect(result.guide).toMatchObject({
      gameId: "NPWR28536_00",
      language: "ru",
      generatedAt: "2026-11-20T10:00:00Z",
      summary: { difficulty: 4, hoursMin: 10, hoursMax: 15, overview: expect.stringContaining("платина") },
      stratege: { url: COTL_URL, averagePlatinumHours: 49, platinumPercent: 16.58 },
    });
    expect(result.guide.sources.map((s) => s.id)).toEqual(["w1", `st${masterOfChanceTip.id}`]);
    // The page is kept for the next build (the other language, a refresh soon after).
    expect(JSON.parse(run.kv.store.get("stratege:NPWR28536_00")!).game.title).toBe("Cult of the Lamb");
    expect(run.kv.ttls.get("stratege:NPWR28536_00")).toBe(14 * 24 * 3600);
    const input = model.params[0]!.messages[0]!.content as string;
    expect(input).toContain("tip st259620 by TailyMile");
  });

  it("uses the kept Stratege page, unless asked to refresh", async () => {
    const kv = new MemoryKV();
    await kv.put("stratege:NPWR28536_00", JSON.stringify({ game: stratege }));
    const cached = options(scripted(message([save(strategeOnlyDraft())], "tool_use")).call, { kv });
    await buildGuide(game, "en", cached.options);
    expect(cached.asked).toEqual([]);
    expect(cached.progress).toEqual(["stratege", "writing"]);

    const refreshed = options(scripted(message([save(strategeOnlyDraft())], "tool_use")).call, { kv, refresh: true });
    await buildGuide(game, "en", refreshed.options);
    expect(refreshed.asked).toEqual([`${COTL_URL}?nax=1`]);
  });

  it("goes on without Stratege when it has no page", async () => {
    const model = scripted(message([...searched(), save({ ...validDraft(), tips: [] })], "tool_use"));
    const run = options(model.call, {
      fetch: (async () => new Response("", { status: 404 })) as typeof fetch,
      config: readConfig({ GUIDE_MAX_SEARCHES: "0" }),
    });
    const result = await buildGuide(game, "ru", run.options);
    expect(result.guide.stratege).toBeNull();
    expect(model.params[0]!.messages[0]!.content).toContain("Stratege.ru has no page for this game.");
    expect(JSON.parse(run.kv.store.get("stratege:NPWR28536_00")!)).toEqual({ notFound: true });
    expect(run.kv.ttls.get("stratege:NPWR28536_00")).toBe(3 * 24 * 3600);
  });

  it("finds the Stratege page by a small web search when the name's slug is wrong", async () => {
    const found = message([searchUse("srv_s", "Cult of the Lamb трофеи"), searchResult("srv_s", ["https://stratege.ru/ps5/trophies/cult_of_the_lamb/spisok/godhood"])]);
    const model = scripted(found, message([save(strategeOnlyDraft())], "tool_use"));
    const run = options(model.call);
    const renamed = { ...game, name: "Cult of the Lamb: Unholy Edition" };
    const result = await buildGuide(renamed, "ru", run.options);
    expect(result.guide.stratege?.url).toBe(COTL_URL);
    expect(result.calls).toBe(2);
    const search = model.params[0]!;
    expect(search).toEqual(strategeSearchParams(readConfig({}), renamed));
    expect(search.tools).toEqual([{ type: "web_search_20250305", name: "web_search", max_uses: 2, allowed_domains: ["stratege.ru"] }]);
    expect(run.asked.at(-1)).toBe(`${COTL_URL}?nax=1`);
  });

  it("asks once for a fix, then saves the corrected guide", async () => {
    const broken = validDraft();
    broken.steps[0]!.trophyIds.push(999);
    const model = scripted(message([save(broken, "toolu_1")], "tool_use"), message([save(validDraft(), "toolu_2")], "tool_use"));
    const result = await buildGuide(game, "ru", options(model.call).options);
    expect(result.calls).toBe(2);
    expect(result.guide.steps[0]!.trophyIds).toEqual([1, 2, 3, 49]);
    const fix = model.params[1]!.messages.at(-1)!;
    expect(fix).toMatchObject({ role: "user", content: [{ type: "tool_result", tool_use_id: "toolu_1", is_error: true }] });
    expect(JSON.stringify(fix)).toContain("steps[0].trophyIds: 999 is not in the trophy list");
    // The tools stay the same on every call, for the cache.
    expect(JSON.stringify(model.params[1]!.tools)).toBe(JSON.stringify(model.params[0]!.tools));
  });

  it("saves a still imperfect but usable guide without its invalid parts, and refuses an unusable one", async () => {
    const broken = validDraft();
    broken.tips.push({ trophyId: 999, text: "x", sourceIds: [] });
    const usable = await buildGuide(game, "ru", options(scripted(message([save(broken)], "tool_use"), message([save(broken)], "tool_use")).call).options);
    expect(usable.guide.tips).toHaveLength(2);

    const empty = { ...validDraft(), steps: [] };
    const failing = buildGuide(game, "ru", options(scripted(message([save(empty)], "tool_use"), message([save(empty)], "tool_use")).call).options);
    await expect(failing).rejects.toMatchObject({ code: "invalid_guide", retryable: true });
  });

  it("nudges a model that ended without the guide once, and resumes a paused search", async () => {
    const model = scripted(
      message(searched(), "pause_turn"),
      message([textBlock("Вот что я нашёл…")], "end_turn"),
      message([save(validDraft())], "tool_use"),
    );
    const result = await buildGuide(game, "ru", options(model.call).options);
    expect(result.calls).toBe(3);
    expect(model.params[1]!.messages.at(-1)!.role).toBe("assistant");
    expect(model.params[2]!.messages.at(-1)).toEqual({ role: "user", content: "Call save_guide now with the whole guide." });

    const never = scripted(message([textBlock("a")]), message([textBlock("b")]));
    await expect(buildGuide(game, "ru", options(never.call).options)).rejects.toMatchObject({ code: "no_guide" });
  });

  it("stops on a refusal or a guide cut off by max_tokens", async () => {
    const refused = buildGuide(game, "ru", options(scripted(message([textBlock("")], "refusal")).call).options);
    await expect(refused).rejects.toBeInstanceOf(GuideError);
    await expect(buildGuide(game, "ru", options(scripted(message([textBlock("")], "refusal")).call).options)).rejects.toMatchObject({ code: "refused", retryable: false });
    await expect(buildGuide(game, "ru", options(scripted(message([save(validDraft())], "max_tokens")).call).options)).rejects.toMatchObject({ code: "truncated" });
  });
});
