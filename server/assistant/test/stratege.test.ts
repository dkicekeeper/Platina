import { describe, expect, it } from "vitest";
import {
  decodeEntities,
  fetchUrl,
  findStrategeGame,
  htmlToText,
  listUrl,
  matchTrophies,
  pageGameIds,
  parseHours,
  parseStrategePage,
  platformOrder,
  slugCandidates,
  slugFromUrl,
  USER_AGENT,
} from "../src/stratege";
import { fixture } from "./helpers";

// Real pages saved from stratege.ru on 2026-11-20 (?nax=1), trimmed of scripts, chrome and
// buttons the parser never reads: Cult of the Lamb whole, Gran Turismo 7 cut to six trophies.

const COTL_URL = "https://stratege.ru/ps5/games/cult_of_the_lamb/trophies/spisok";
const cotlHtml = fixture("stratege-cult-of-the-lamb.html");
const gt7Html = fixture("stratege-gran-turismo-7.html");
const cotl = parseStrategePage(cotlHtml, COTL_URL, "NPWR28536_00");
const gt7 = parseStrategePage(gt7Html, "https://stratege.ru/ps5/games/gran_turismo_7/trophies/spisok", "NPWR20919_00");

describe("a Stratege trophy list page", () => {
  it("proves its game by the npCommunicationId in the trophy images", () => {
    expect(pageGameIds(cotlHtml)).toEqual(new Set(["NPWR28536_00"]));
    expect(pageGameIds(gt7Html)).toEqual(new Set(["NPWR20919_00"]));
    expect(pageGameIds(fixture("stratege-not-found.html")).size).toBe(0);
  });

  it("gives the game's numbers", () => {
    expect(cotl).toMatchObject({
      url: COTL_URL,
      npCommunicationId: "NPWR28536_00",
      title: "Cult of the Lamb",
      owners: 6846,
      platinumEarned: 1135,
      platinumPercent: 16.58,
      averagePlatinumHours: 49,
      averageCompletion: 32,
    });
    expect(gt7).toMatchObject({ owners: 7299, platinumEarned: 725, averagePlatinumHours: 319 });
  });

  it("reads the standard summary from the platinum's top tip", () => {
    expect(cotl.summary).toMatchObject({
      difficulty: 4,
      hoursMin: 10,
      hoursMax: null,
      playthroughs: 1,
      onlineTrophies: 0,
      offlineTrophies: 37,
      missableTrophies: 1,
      glitchedTrophies: 0,
      difficultyAffects: false,
      author: "TailyMile",
      tipId: "259620",
    });
    expect(cotl.summary!.lines.map((l) => l.key)).toContain("Число трофеев, которые можно пропустить");
    expect(cotl.summary!.lines.find((l) => l.key.startsWith("Число трофеев"))!.value).toContain("Master of Chance / Улыбка фортуны");
    // Another wording of the same lines, and a range of hours.
    expect(gt7.summary).toMatchObject({ difficulty: 6, hoursMin: 50, hoursMax: 100, onlineTrophies: 54, offlineTrophies: 0, missableTrophies: 0, glitchedTrophies: 0, difficultyAffects: false });
  });

  it("reads every trophy with its PSN id, type, names and rarity", () => {
    expect(cotl.trophies).toHaveLength(57);
    expect(cotl.trophies.map((t) => t.number)).toEqual(Array.from({ length: 57 }, (_, i) => i));
    const types = cotl.trophies.reduce<Record<string, number>>((n, t) => ({ ...n, [t.type!]: (n[t.type!] ?? 0) + 1 }), {});
    expect(types).toEqual({ platinum: 1, gold: 4, silver: 21, bronze: 31 });
    expect(cotl.trophies[36]).toMatchObject({
      number: 36,
      type: "silver",
      title: "Master of Chance / Улыбка фортуны",
      names: ["Master of Chance", "Улыбка фортуны"],
      url: "https://stratege.ru/ps5/trophies/cult_of_the_lamb/spisok/master_of_chance",
      psnRarity: 19,
      online: false,
    });
    expect(cotl.trophies[0]).toMatchObject({ description: "Настало время слуге стать божеством.", psnRarity: 1.8, strategeRarity: 16.58 });
  });

  it("marks online trophies", () => {
    expect(gt7.trophies.filter((t) => t.online).map((t) => t.number).sort()).toEqual([29, 48, 49]);
  });

  it("reads the tips on the page with their author, date, thanks and additions", () => {
    expect(cotl.trophies.reduce((n, t) => n + t.tips.length, 0)).toBe(42);
    const platinum = cotl.trophies[0]!;
    expect(platinum.tips).toHaveLength(1);
    const tip = platinum.tips[0]!;
    expect(tip).toMatchObject({ id: "259620", author: "TailyMile", date: "09.03.2023 в 12:19", thanks: 5 });
    expect(tip.text).toContain("- Уровень сложности трофеев: 4/10.");
    expect(tip.text).toContain("[Бронзовый трофей]");
    expect(tip.additions).toHaveLength(7);
    expect(tip.additions[0]).toMatchObject({ author: "borogoz", date: "20.09.2024 в 14:38", thanks: 3 });
    expect(tip.additions[0]!.text).toMatch(/^На момент обновления 1\.16 игра сломана/);
  });

  it("keeps the count of tips the page doesn't carry, and puts the most thanked first", () => {
    const fullFlock = cotl.trophies[21]!;
    expect(fullFlock.tipCount).toBe(16);
    expect(fullFlock.tips.map((t) => [t.id, t.author, t.thanks])).toEqual([
      ["265218", "Globeer", 13],
      ["279826", "Bigmakin", 12],
    ]);
    expect(cotl.trophies[1]).toMatchObject({ tipCount: 0, tips: [] });
  });
});

describe("tip text", () => {
  it("keeps lines and lists, marks hidden text, names trophy icons, keeps outside links", () => {
    const html =
      'Шаг 1:<br />Иди на <b>юг</b>.<ul><li>Раз</li><li>Два</li></ul>' +
      '<div class="spoiler_control"><input type="button" value="Скрытый текст: Открыть"></div><div><div class="spoiler-body">Босс &mdash; отец</div></div>' +
      '5 <img src="x.svg" title="Бронзовый трофей" class="inlineimg" /> и <a href="https://ddm999.github.io/gt7info/">таблица</a>, ' +
      '<a href="https://www.stratege.ru/ps5/trophies/x/spisok/y">трофей</a>, <a href="/users/x"><img src="a.png" /></a>&laquo;ок&raquo; &#1044;&#x430;';
    expect(htmlToText(html)).toBe(
      "Шаг 1:\nИди на юг.\n- Раз\n- Два\n\n[скрытый текст] Босс — отец\n\n5 [Бронзовый трофей] и таблица (https://ddm999.github.io/gt7info/), трофей, «ок» Да",
    );
    expect(decodeEntities("&amp;&lt;&nbsp;&unknown;")).toBe("&< &unknown;");
  });

  it("reads hours as a range", () => {
    expect(parseHours("10+ часов")).toEqual({ min: 10, max: null });
    expect(parseHours("50-100 часов (плюс ожидание)")).toEqual({ min: 50, max: 100 });
    expect(parseHours("15–20 часов")).toEqual({ min: 15, max: 20 });
    expect(parseHours("около 25 часов")).toEqual({ min: 25, max: 25 });
  });
});

describe("finding the page", () => {
  it("guesses slugs the way Stratege writes them", () => {
    expect(slugCandidates("Cult of the Lamb")).toEqual(["cult_of_the_lamb"]);
    expect(slugCandidates("Marvel's Spider-Man 2")).toEqual(["marvels_spider-man_2", "marvels_spider_man_2"]);
    expect(slugCandidates("ASTRO BOT™")).toEqual(["astro_bot"]);
    expect(slugCandidates("Ratchet & Clank: Rift Apart")).toEqual(["ratchet_and_clank_rift_apart"]);
    expect(slugCandidates("Pokémon™")).toEqual(["pokemon"]);
    expect(platformOrder("PS5")).toEqual(["ps5", "ps4"]);
    expect(platformOrder("PS4")).toEqual(["ps4", "ps5"]);
    expect(listUrl("ps5", "cult_of_the_lamb")).toBe(COTL_URL);
    expect(fetchUrl(COTL_URL)).toBe(`${COTL_URL}?nax=1`);
  });

  it("reads a slug from a search result", () => {
    expect(slugFromUrl("https://www.stratege.ru/ps5/trophies/cult_of_the_lamb/spisok/godhood")).toEqual({ platform: "ps5", slug: "cult_of_the_lamb" });
    expect(slugFromUrl("https://stratege.ru/ps4/games/gran_turismo_7/")).toEqual({ platform: "ps4", slug: "gran_turismo_7" });
    expect(slugFromUrl("https://example.com/ps5/games/x")).toBeUndefined();
  });

  /** A fetch that serves `pages` by URL (404 otherwise) and records what was asked. */
  function site(pages: Record<string, string>) {
    const asked: { url: string; userAgent: string | null }[] = [];
    const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      asked.push({ url, userAgent: new Headers(init?.headers).get("user-agent") });
      const page = pages[url];
      return page ? new Response(page, { status: 200 }) : new Response("not found", { status: 404 });
    }) as typeof fetch;
    return { fetcher, asked };
  }

  const cultOfTheLamb = { npCommunicationId: "NPWR28536_00", name: "Cult of the Lamb", platform: "PS5" };

  it("takes one page when the name gives the right slug", async () => {
    const { fetcher, asked } = site({ [`${COTL_URL}?nax=1`]: cotlHtml });
    const found = await findStrategeGame(cultOfTheLamb, { fetch: fetcher });
    expect(found.game?.title).toBe("Cult of the Lamb");
    expect(found.game?.url).toBe(COTL_URL);
    expect(asked).toEqual([{ url: `${COTL_URL}?nax=1`, userAgent: USER_AGENT }]);
    expect(USER_AGENT).not.toMatch(/@/);
  });

  it("does not take a page of another game, and tries PS4 next", async () => {
    const ps4 = "https://stratege.ru/ps4/games/cult_of_the_lamb/trophies/spisok?nax=1";
    const { fetcher, asked } = site({ [`${COTL_URL}?nax=1`]: gt7Html, [ps4]: cotlHtml });
    const found = await findStrategeGame(cultOfTheLamb, { fetch: fetcher });
    expect(found.game?.url).toBe("https://stratege.ru/ps4/games/cult_of_the_lamb/trophies/spisok");
    expect(asked.map((a) => a.url)).toEqual([`${COTL_URL}?nax=1`, ps4]);
  });

  it("asks a web search when no guess works, and stops after it", async () => {
    const real = "https://stratege.ru/ps5/games/cult_of_lamb_v2/trophies/spisok?nax=1";
    const { fetcher, asked } = site({ [real]: cotlHtml });
    let searched = 0;
    const found = await findStrategeGame(cultOfTheLamb, {
      fetch: fetcher,
      search: async () => {
        searched += 1;
        return ["https://example.com/x", "https://www.stratege.ru/ps5/trophies/cult_of_lamb_v2/spisok/godhood"];
      },
    });
    expect(searched).toBe(1);
    expect(found).toMatchObject({ searched: true, fetches: 3 });
    expect(found.game?.url).toBe("https://stratege.ru/ps5/games/cult_of_lamb_v2/trophies/spisok");
    expect(asked).toHaveLength(3);

    const none = await findStrategeGame(cultOfTheLamb, { fetch: site({}).fetcher, search: async () => [] });
    expect(none).toEqual({ fetches: 2, searched: true });
  });

  it("survives a network failure", async () => {
    const failing = (async () => {
      throw new TypeError("network");
    }) as typeof fetch;
    expect(await findStrategeGame(cultOfTheLamb, { fetch: failing })).toEqual({ fetches: 2, searched: false });
  });
});

describe("PSN ↔ Stratege", () => {
  it("matches by PSN trophy id, and by name when the id is not there", () => {
    const matched = matchTrophies(cotl, [
      { id: 36, name: "Улыбка фортуны" },
      { id: 0, name: "Godhood" },
      { id: 900, name: "Master of Chance" },
      { id: 901, name: "Nothing like it" },
    ]);
    expect(matched.get(36)?.number).toBe(36);
    expect(matched.get(0)?.type).toBe("platinum");
    expect(matched.get(900)?.number).toBe(36);
    expect(matched.has(901)).toBe(false);
  });
});
