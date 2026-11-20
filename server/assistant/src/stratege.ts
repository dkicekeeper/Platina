// Stratege.ru, the first source of a guide (docs/assistant.md §4, docs/PLAN.md §5): finds a
// game's trophy list page and reads it without a model. The page is big (about 700 KB of HTML
// for 57 trophies); what the guide needs from it is small: the game's numbers, the summary in
// the platinum's top tip, and players' tips per trophy.
//
//   https://stratege.ru/ps5/games/<slug>/trophies/spisok?nax=1
//
// `nax=1` makes the server render the list itself (without it the list arrives by a script).
// Trophy images live at static.stratege.ru/trophies/<npCommunicationId>/TROP<nnn>_w100h100.PNG,
// so the id in the page proves it is the right game, and <nnn> is the PSN trophyId.
// Each trophy shows its first two tips (the others load on a click) and how many there are.
//
// Polite by design: one page per guide build when the slug guessed from the name is right,
// a few more only when it is not (a second spelling, then PS4), a descriptive User-Agent, and
// the parsed page is kept in KV (src/guide.ts) so a guide in the other language or a refresh
// soon after does not fetch it again.

export const STRATEGE_ORIGIN = "https://stratege.ru";
export const USER_AGENT = "PlatinaGuideBot/1.0 (trophy guide builder for the Platina iPhone app; one page per game, cached)";

export type StrategePlatform = "ps5" | "ps4";
export type TrophyType = "platinum" | "gold" | "silver" | "bronze";

export interface StrategeTipAddition {
  author: string;
  date: string;
  thanks: number;
  text: string;
}

export interface StrategeTip {
  id: string;
  author: string;
  /** As the page writes it: 09.03.2023 в 12:19. */
  date: string;
  thanks: number;
  text: string;
  additions: StrategeTipAddition[];
}

export interface StrategeTrophy {
  /** The PSN trophyId, from the image file name (TROP014 → 14). */
  number: number | null;
  type: TrophyType | null;
  /** "Godhood / Божественность": the English name, then the Russian one when there is one. */
  title: string;
  names: string[];
  description: string;
  /** The trophy's own page, where all of its tips are. */
  url: string;
  /** PSN rarity, %. */
  psnRarity: number | null;
  /** Of Stratege's players who have the game, %. */
  strategeRarity: number | null;
  online: boolean;
  /** Tips on Stratege for this trophy; the page carries the first two of them. */
  tipCount: number;
  /** The tips on the page, most thanked first. */
  tips: StrategeTip[];
}

/** The standard summary in the platinum's top tip. Numbers the tip does not give are null. */
export interface StrategeSummary {
  difficulty: number | null;
  hoursMin: number | null;
  hoursMax: number | null;
  playthroughs: number | null;
  onlineTrophies: number | null;
  offlineTrophies: number | null;
  missableTrophies: number | null;
  glitchedTrophies: number | null;
  difficultyAffects: boolean | null;
  /** Every line of the summary as written: "Примерное время получения платины: 10+ часов." */
  lines: { key: string; value: string }[];
  author: string;
  tipId: string;
}

export interface StrategeGame {
  /** The list page, without `?nax=1`. */
  url: string;
  npCommunicationId: string;
  title: string;
  owners: number | null;
  platinumEarned: number | null;
  /** Of Stratege's players who have the game, %. */
  platinumPercent: number | null;
  averagePlatinumHours: number | null;
  /** Average completion, %. */
  averageCompletion: number | null;
  summary: StrategeSummary | null;
  trophies: StrategeTrophy[];
}

// MARK: - Addresses

export const listUrl = (platform: StrategePlatform, slug: string) => `${STRATEGE_ORIGIN}/${platform}/games/${slug}/trophies/spisok`;
export const fetchUrl = (url: string) => `${url}?nax=1`;

/** Slugs to try for a game name: Stratege lowercases the English name, drops apostrophes and
 * turns the rest of the punctuation into underscores (death_to_non-believers keeps its hyphen).
 * The second spelling turns hyphens into underscores too. */
export function slugCandidates(name: string): string[] {
  const base = name
    // Before NFKD, which spells ™ as "TM".
    .replace(/[™®©]/g, "")
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/['’`]/g, "")
    .replace(/&/g, " and ");
  const tidy = (s: string) => s.replace(/_+/g, "_").replace(/^[_-]+|[_-]+$/g, "");
  const keepHyphen = tidy(base.replace(/[^a-z0-9-]+/g, "_"));
  const noHyphen = tidy(base.replace(/[^a-z0-9]+/g, "_"));
  return [...new Set([keepHyphen, noHyphen])].filter((s) => s.length > 0);
}

/** The platforms to look under, the game's own first. */
export function platformOrder(platform: string): StrategePlatform[] {
  return /ps4/i.test(platform) && !/ps5/i.test(platform) ? ["ps4", "ps5"] : ["ps5", "ps4"];
}

/** A Stratege game or trophy address seen somewhere (a search result): its platform and slug. */
export function slugFromUrl(url: string): { platform: StrategePlatform; slug: string } | undefined {
  const match = /^https?:\/\/(?:www\.)?stratege\.ru\/(ps5|ps4)\/(?:games|trophies)\/([a-z0-9_-]+)/i.exec(url.trim());
  return match ? { platform: match[1]!.toLowerCase() as StrategePlatform, slug: match[2]!.toLowerCase() } : undefined;
}

/** Every npCommunicationId whose trophy images the page shows. */
export function pageGameIds(html: string): Set<string> {
  return new Set([...html.matchAll(/static\.stratege\.ru\/trophies\/(NPWR\d{5}_\d{2})\//g)].map((m) => m[1]!));
}

// MARK: - Finding the page

export interface FindOptions {
  fetch: typeof fetch;
  /** Asked when no guessed slug works: candidate pages from a web search. */
  search?: () => Promise<string[]>;
  /** Pages fetched at most, guesses and search results together. */
  maxFetches?: number;
  timeoutMs?: number;
}

export interface FindResult {
  game?: StrategeGame;
  /** Pages fetched, for the logs. */
  fetches: number;
  searched: boolean;
}

async function fetchPage(url: string, options: FindOptions): Promise<string | undefined> {
  const response = await options.fetch(fetchUrl(url), {
    headers: { "user-agent": USER_AGENT, accept: "text/html", "accept-language": "ru,en;q=0.5" },
    redirect: "follow",
    signal: AbortSignal.timeout(options.timeoutMs ?? 20_000),
  });
  if (!response.ok) {
    await response.body?.cancel().catch(() => undefined);
    return undefined;
  }
  const html = await response.text();
  // Over 4 MB is not a trophy list.
  return html.length > 4_000_000 ? undefined : html;
}

/** Finds the game's page by the slugs its name gives (PS5, then PS4), then by a web search, and
 * reads it. Only a page with the game's own npCommunicationId in its trophy images counts. */
export async function findStrategeGame(
  game: { npCommunicationId: string; name: string; platform: string },
  options: FindOptions,
): Promise<FindResult> {
  const maxFetches = options.maxFetches ?? 6;
  const tried = new Set<string>();
  let fetches = 0;
  let searched = false;

  const attempt = async (url: string): Promise<StrategeGame | undefined> => {
    if (tried.has(url) || fetches >= maxFetches) return undefined;
    tried.add(url);
    fetches += 1;
    let html: string | undefined;
    try {
      html = await fetchPage(url, options);
    } catch {
      return undefined;
    }
    if (!html || !pageGameIds(html).has(game.npCommunicationId)) return undefined;
    return parseStrategePage(html, url, game.npCommunicationId);
  };

  // Guesses: at most four pages (two spellings on two platforms).
  const guesses = platformOrder(game.platform).flatMap((platform) => slugCandidates(game.name).map((slug) => listUrl(platform, slug)));
  for (const url of guesses.slice(0, 4)) {
    const found = await attempt(url);
    if (found) return { game: found, fetches, searched };
  }

  if (options.search) {
    searched = true;
    let urls: string[] = [];
    try {
      urls = await options.search();
    } catch {
      urls = [];
    }
    const candidates = [...new Set(urls.map(slugFromUrl).filter((c) => c !== undefined).map((c) => listUrl(c.platform, c.slug)))];
    for (const url of candidates.slice(0, 2)) {
      const found = await attempt(url);
      if (found) return { game: found, fetches, searched };
    }
  }
  return { fetches, searched };
}

// MARK: - HTML

const ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  mdash: "—",
  ndash: "–",
  laquo: "«",
  raquo: "»",
  hellip: "…",
  rsquo: "’",
  lsquo: "‘",
  ldquo: "“",
  rdquo: "”",
  bdquo: "„",
  times: "×",
  minus: "−",
  deg: "°",
  copy: "©",
  reg: "®",
  trade: "™",
};

export function decodeEntities(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, name: string) => {
    if (name[0] === "#") {
      const code = name[1] === "x" || name[1] === "X" ? Number.parseInt(name.slice(2), 16) : Number.parseInt(name.slice(1), 10);
      return Number.isFinite(code) && code > 0 && code < 0x110000 ? String.fromCodePoint(code) : whole;
    }
    return ENTITIES[name.toLowerCase()] ?? whole;
  });
}

/** The element that starts at `start` (an opening `<div`), with everything inside it, found by
 * counting nested divs. */
export function balancedDiv(html: string, start: number): string {
  let depth = 0;
  let index = start;
  while (index < html.length) {
    const open = html.indexOf("<div", index);
    const close = html.indexOf("</div>", index);
    if (close < 0) return html.slice(start);
    if (open >= 0 && open < close) {
      depth += 1;
      index = open + 4;
    } else {
      depth -= 1;
      index = close + 6;
      if (depth === 0) return html.slice(start, index);
    }
  }
  return html.slice(start);
}

/** The contents of the first div with `className` at or after `from`, or undefined. */
function divContents(html: string, className: string, from = 0): string | undefined {
  const marker = html.indexOf(`class="${className}`, from);
  if (marker < 0) return undefined;
  const start = html.lastIndexOf("<div", marker);
  if (start < 0) return undefined;
  const element = balancedDiv(html, start);
  const inner = element.indexOf(">");
  return element.slice(inner + 1, element.length - 6);
}

/** A tip's HTML as plain text: lines kept, lists as "- ", hidden text marked, trophy icons as
 * their names, links to other sites with their address. */
export function htmlToText(html: string): string {
  let text = html
    .replace(/<script\b[\s\S]*?<\/script>/gi, "")
    .replace(/<style\b[\s\S]*?<\/style>/gi, "")
    .replace(/<input\b[^>]*>/gi, "")
    .replace(/<div[^>]*class="spoiler-body"[^>]*>/gi, "\n[скрытый текст] ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<li[^>]*>/gi, "\n- ")
    .replace(/<\/li>/gi, "")
    .replace(/<\/(p|div|ul|ol|tr|h\d)>/gi, "\n")
    .replace(/<img[^>]*\btitle="([^"]+)"[^>]*>/gi, " [$1] ")
    .replace(/<img[^>]*>/gi, "")
    .replace(/<a\b[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/gi, (_whole, href: string, inner: string) => {
      const label = inner.replace(/<[^>]+>/g, "").trim();
      const external = /^https?:\/\//i.test(href) && !/^https?:\/\/(www\.)?stratege\.ru\//i.test(href);
      if (!label) return "";
      return external && decodeEntities(label) !== decodeEntities(href) ? `${label} (${href})` : label;
    })
    .replace(/<[^>]+>/g, "");
  text = decodeEntities(text);
  return text
    .split("\n")
    .map((line) => line.replace(/[ \t ]+/g, " ").trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/ +([.,;:!?)])/g, "$1")
    .trim();
}

/** "1 135 чел." → 1135, "49 часов" → 49, "16.58%" → 16.58. */
export function firstNumber(text: string): number | null {
  const match = /(\d[\d\s ]*(?:[.,]\d+)?)/.exec(text);
  if (!match) return null;
  const value = Number.parseFloat(match[1]!.replace(/[\s ]/g, "").replace(",", "."));
  return Number.isFinite(value) ? value : null;
}

// MARK: - The page

/** Reads a trophy list page. `url` is the list page without `?nax=1`. */
export function parseStrategePage(html: string, url: string, npCommunicationId: string): StrategeGame {
  const labels = new Map<string, string>();
  for (const match of html.matchAll(/class="tlpf_bsc_label_list_left">([\s\S]*?)<\/div>\s*<div class="tlpf_bsc_label_list_right[^"]*"[^>]*>([\s\S]*?)<\/div>/g)) {
    labels.set(htmlToText(match[1]!).toLowerCase(), htmlToText(match[2]!));
  }
  const label = (pattern: RegExp) => {
    for (const [key, value] of labels) if (pattern.test(key)) return firstNumber(value);
    return null;
  };

  const trophies = trophyBlocks(html).map((block) => parseTrophy(block));
  const platinum = trophies.find((t) => t.type === "platinum");
  const owners = label(/игра есть у/);
  const platinumEarned = label(/получили платину/);
  let platinumPercent = platinum?.strategeRarity ?? null;
  if (platinumPercent === null && owners && platinumEarned !== null) platinumPercent = Math.round((platinumEarned / owners) * 10000) / 100;

  const titleMatch = /class="tlpf_games_title">([\s\S]*?)<\/div>/.exec(html);
  return {
    url,
    npCommunicationId,
    title: titleMatch ? htmlToText(titleMatch[1]!) : "",
    owners,
    platinumEarned,
    platinumPercent,
    averagePlatinumHours: label(/среднее время/),
    averageCompletion: label(/среднее завершение/),
    summary: findSummary(platinum ? [platinum, ...trophies.filter((t) => t !== platinum)] : trophies),
    trophies,
  };
}

/** Each trophy's block, in page order. */
function trophyBlocks(html: string): string[] {
  const listStart = html.indexOf('id="tlpfid_tltsid_list"');
  if (listStart < 0) return [];
  const listEnd = (() => {
    const bottom = html.indexOf('id="tlpfid_filter_box_bottom"', listStart);
    return bottom < 0 ? html.length : bottom;
  })();
  const list = html.slice(listStart, listEnd);
  const starts = [...list.matchAll(/<div id="tltstplid_bx_trophies_\d+"/g)].map((m) => m.index!);
  return starts.map((start, i) => list.slice(start, starts[i + 1] ?? list.length));
}

function parseTrophy(block: string): StrategeTrophy {
  const number = /static\.stratege\.ru\/trophies\/NPWR\d{5}_\d{2}\/TROP(\d{3,4})[_.]/i.exec(block);
  const type = /tltstpl_border_(platinum|gold|silver|bronze)_trophies/.exec(block);
  const title = /id="tltstplid_bx_title_\d+"><a[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/.exec(block);
  const description = divContents(block, "tltstpl_tt_trops_description_box");
  const psnRarity = /class="network_rarity[^"]*"[^>]*>[^<]*?\(([\d.,]+)\s*%\)/.exec(block);
  const strategeRarity = /Получен[^<(]*\(([\d.,]+)\s*%\)/.exec(block);
  const slider = /class="tlhsltpl_slider_box"[^>]*\brel="(\d+)"/.exec(block);
  const titleText = title ? htmlToText(title[2]!) : "";
  const href = title?.[1] ?? "";
  const tips = parseTips(block).sort((a, b) => b.thanks - a.thanks);
  return {
    number: number ? Number.parseInt(number[1]!, 10) : null,
    type: (type?.[1] as TrophyType | undefined) ?? null,
    title: titleText,
    names: titleText
      .split(" / ")
      .map((s) => s.trim())
      .filter(Boolean),
    description: description ? htmlToText(description) : "",
    url: href.startsWith("http") ? href : href ? `${STRATEGE_ORIGIN}${href}` : "",
    psnRarity: psnRarity ? firstNumber(psnRarity[1]!) : null,
    strategeRarity: strategeRarity ? firstNumber(strategeRarity[1]!) : null,
    online: /trophies_icon\/online\.png/.test(block),
    tipCount: slider ? Number.parseInt(slider[1]!, 10) : tips.length,
    tips,
  };
}

function parseTips(block: string): StrategeTip[] {
  const tips: StrategeTip[] = [];
  for (const match of block.matchAll(/<div class="tlhsltpl_relative_helps[^"]*" hsids="(\d+)">/g)) {
    const slot = balancedDiv(block, match.index!);
    if (!slot.includes("tlhsltpl_helps_body")) continue; // shown on a click, not on the page
    const id = match[1]!;
    const header = /Подсказка от\s*<span>(?:<a[^>]*>)?([^<]*)(?:<\/a>)?<\/span>\s*<span class="tlhsltpl_helps_header_autor_date">([^<]*)<\/span>/.exec(slot);
    const thanks = new RegExp(`id="tlhsltplid_helps_count_hearts_${id}">\\s*(\\d+)`).exec(slot);
    const text = divContents(slot, "tlhsltpl_helps_text_helps");
    tips.push({
      id,
      author: header ? decodeEntities(header[1]!).trim() : "",
      date: header ? cleanDate(header[2]!) : "",
      thanks: thanks ? Number.parseInt(thanks[1]!, 10) : 0,
      text: text ? htmlToText(text) : "",
      additions: parseAdditions(slot),
    });
  }
  return tips;
}

function parseAdditions(slot: string): StrategeTipAddition[] {
  const additions: StrategeTipAddition[] = [];
  for (const match of slot.matchAll(/id="tlhsltpl_add_header_id_(\d+)"/g)) {
    const id = match[1]!;
    const headerEnd = slot.indexOf(`id="tlhsltplid_add_helps_box${id}"`, match.index!);
    const header = slot.slice(match.index!, headerEnd < 0 ? undefined : headerEnd);
    const author = /от\s*<span>(?:<a[^>]*>)?([^<]*)(?:<\/a>)?<\/span>\s*<span class="tlhsltpl_helps_header_autor_date">([^<]*)<\/span>/.exec(header);
    const thanks = new RegExp(`id="tlhsltplid_helps_count_hearts_${id}">\\s*(\\d+)`).exec(header);
    const text = headerEnd < 0 ? undefined : divContents(slot, "tlhsltpl_add_helps_text", headerEnd);
    additions.push({
      author: author ? decodeEntities(author[1]!).trim() : "",
      date: author ? cleanDate(author[2]!) : "",
      thanks: thanks ? Number.parseInt(thanks[1]!, 10) : 0,
      text: text ? htmlToText(text) : "",
    });
  }
  return additions;
}

const cleanDate = (raw: string) => decodeEntities(raw).replace(/^[\s—–-]+/, "").trim();

// MARK: - The summary

/** The standard summary list ("Уровень сложности трофеев: 4/10." ...) from the first tip that
 * has one, the platinum's tips first. */
function findSummary(trophies: StrategeTrophy[]): StrategeSummary | null {
  for (const trophy of trophies) {
    for (const tip of trophy.tips) {
      const summary = parseSummary(tip);
      if (summary) return summary;
    }
  }
  return null;
}

export function parseSummary(tip: StrategeTip): StrategeSummary | null {
  const lines = tip.text
    .split("\n")
    .map((line) => line.replace(/^-\s*/, "").trim())
    .map((line) => {
      const colon = line.indexOf(":");
      return colon > 0 ? { key: line.slice(0, colon).trim(), value: line.slice(colon + 1).trim().replace(/\.$/, "") } : undefined;
    })
    .filter((line): line is { key: string; value: string } => line !== undefined && line.value.length > 0);
  const find = (pattern: RegExp) => lines.find((line) => pattern.test(line.key.toLowerCase()))?.value;

  const difficultyText = find(/сложност[ьи] трофеев|уровень сложности трофеев|сложность платины/);
  const difficultyMatch = difficultyText ? /(\d+(?:[.,]\d+)?)\s*\/\s*10/.exec(difficultyText) : null;
  const hoursText = find(/время (получения )?платины|время на платину|время получения/);
  if (!difficultyMatch && !hoursText) return null;

  const hours = hoursText ? parseHours(hoursText) : { min: null, max: null };
  const missableText = find(/пропустить/);
  const affectsText = find(/сложност[ьи] влияет/);
  return {
    difficulty: difficultyMatch ? Number.parseFloat(difficultyMatch[1]!.replace(",", ".")) : null,
    hoursMin: hours.min,
    hoursMax: hours.max,
    playthroughs: countOf(find(/прохождени/)),
    onlineTrophies: countOf(find(/онлайн/)),
    offlineTrophies: countOf(find(/оффлайн|офлайн/)),
    missableTrophies: countOf(missableText),
    glitchedTrophies: countOf(find(/глючн|баг/)),
    difficultyAffects: affectsText === undefined ? null : startsWithWord(affectsText, "нет") ? false : startsWithWord(affectsText, "да") ? true : null,
    lines,
    author: tip.author,
    tipId: tip.id,
  };
}

/** "Нет" → 0, "Все 54 (...)" → 54, "1, Master of Chance" → 1, "Да" → null (some, not counted). */
function countOf(value: string | undefined): number | null {
  if (value === undefined) return null;
  if (startsWithWord(value, "нет")) return 0;
  return firstNumber(value);
}

/** Whether `text` starts with `word` as a whole word. (`\b` in a JavaScript regex knows only
 * Latin letters: "Нет." would not match /^нет\b/.) */
function startsWithWord(text: string, word: string): boolean {
  return new RegExp(`^${word}(?![\\p{L}\\p{N}])`, "iu").test(text.trim());
}

/** "10+ часов" → 10..null, "50-100 часов" → 50..100, "около 20 часов" → 20..20. */
export function parseHours(text: string): { min: number | null; max: number | null } {
  const range = /(\d+(?:[.,]\d+)?)\s*(?:-|–|—|до)\s*(\d+(?:[.,]\d+)?)/.exec(text);
  if (range) return { min: Number.parseFloat(range[1]!.replace(",", ".")), max: Number.parseFloat(range[2]!.replace(",", ".")) };
  const plus = /(\d+(?:[.,]\d+)?)\s*\+/.exec(text);
  if (plus) return { min: Number.parseFloat(plus[1]!.replace(",", ".")), max: null };
  const single = firstNumber(text);
  return { min: single, max: single };
}

// MARK: - PSN ↔ Stratege

const normalizeName = (name: string) =>
  name
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/ё/g, "е")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();

/** Stratege's trophy for each PSN trophy id: by the image number when the page has it (the
 * PSN trophyId), else by name (English or Russian). */
export function matchTrophies(game: StrategeGame, trophies: { id: number; name: string }[]): Map<number, StrategeTrophy> {
  const matched = new Map<number, StrategeTrophy>();
  const byNumber = new Map(game.trophies.filter((t) => t.number !== null).map((t) => [t.number!, t]));
  const byName = new Map<string, StrategeTrophy>();
  for (const trophy of game.trophies) for (const name of trophy.names) byName.set(normalizeName(name), trophy);
  for (const trophy of trophies) {
    const found = byNumber.get(trophy.id) ?? byName.get(normalizeName(trophy.name));
    if (found) matched.set(trophy.id, found);
  }
  return matched;
}
