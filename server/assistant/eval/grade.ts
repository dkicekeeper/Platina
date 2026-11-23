// Grades one assistant turn. Universal checks run on every case; each case adds its own.
// Every check is mechanical: tools called and with what, words in the reply, its language.

import { COTL_CHAPTER_2, COTL_TROPHIES, GAMES, HIDDEN_NAMES, SESSION_ID, type Locale } from "./fixture";

export interface ToolCall {
  name: string;
  input: Record<string, unknown>;
  result?: unknown;
  error?: string;
}

export interface RunRecord {
  calls: ToolCall[];
  /** Every web search the model made. */
  searches: string[];
  /** The text the app shows: every text block of the turn, in order. */
  reply: string;
  error?: string;
}

type Input = Record<string, unknown>;

export type Check =
  | { kind: "called"; anyOf: string[] }
  | { kind: "notCalled"; tools: string[] }
  | { kind: "toolArgs"; tool: string; match: (input: Input) => boolean; label: string }
  /** The reply names every group: one of each group's words, case-insensitive (stems work). */
  | { kind: "textHas"; groups: string[][]; label: string }
  /** The reply has none of the words, case-insensitive. */
  | { kind: "textLacks"; words: string[]; label: string }
  | { kind: "searched" };

export interface CheckResult {
  name: string;
  pass: boolean;
  detail?: string;
}

const letters = (text: string, pattern: RegExp) => (text.match(pattern) ?? []).length;

// Game and trophy names stay as PSN writes them, often English in a Russian reply.
const NAMES = [...GAMES.map((g) => g.name), ...COTL_TROPHIES.map((t) => t.name.en), "PlayStation", "PSN", "PS5", "PowerPyx", "PSNProfiles", "Stratege", "Reddit", "YouTube"].sort((a, b) => b.length - a.length);

/** Most letters of the reply are in the case's language (names of games, trophies, sites and
 * links aside). */
export function inLanguage(text: string, locale: Locale): boolean {
  const plain = NAMES.reduce((out, name) => out.split(name).join(" "), text.replace(/https?:\/\/\S+/g, ""));
  const cyrillic = letters(plain, /\p{Script=Cyrillic}/gu);
  const latin = letters(plain, /\p{Script=Latin}/gu);
  const total = cyrillic + latin;
  if (total === 0) return false;
  return locale === "ru" ? cyrillic / total > 0.6 : latin / total > 0.85;
}

const ids = new Set(GAMES.map((g) => g.id));
const trophyIds = new Set(COTL_TROPHIES.map((t) => t.id));

/** What the person sees: the reply's text and the cards the display tools drew. */
export function visibleText(record: RunRecord): string {
  const parts = [record.reply];
  for (const call of record.calls) {
    if (call.error) continue;
    const input = call.input;
    if (call.name === "show_warning") parts.push(String(input.title ?? ""), String(input.text ?? ""));
    if (call.name === "suggest_replies" && Array.isArray(input.replies)) parts.push(...input.replies.map(String));
    if (call.name === "show_checklist" || call.name === "show_step") {
      const ids = call.name === "show_step" ? [input.step_id] : Array.isArray(input.step_ids) ? input.step_ids : [];
      for (const step of COTL_CHAPTER_2.steps) if (ids.includes(step.id)) parts.push(step.text);
    }
    if (call.name === "show_trophies" && Array.isArray(input.trophy_ids)) {
      // A hidden trophy's card keeps its name back, as the app's does.
      for (const t of COTL_TROPHIES) if (input.trophy_ids.includes(t.id) && (!t.hidden || t.earned)) parts.push(t.name.ru, t.name.en);
    }
  }
  return parts.filter(Boolean).join("\n");
}

const DISPLAY_TOOLS = new Set(["show_checklist", "show_step", "show_trophies", "show_warning", "suggest_replies"]);

export function universalChecks(record: RunRecord, locale: Locale, allowSpoilers: boolean): CheckResult[] {
  const cards = record.calls.some((c) => DISPLAY_TOOLS.has(c.name) && !c.error);
  const checks: CheckResult[] = [
    { name: "answered", pass: !record.error && (record.reply.trim().length > 0 || cards), detail: record.error },
    { name: "language", pass: record.reply.trim().length === 0 ? cards : inLanguage(record.reply, locale) },
  ];
  const unknown = record.calls.filter(
    (c) =>
      (typeof c.input.game_id === "string" && !ids.has(c.input.game_id)) ||
      (Array.isArray(c.input.trophy_ids) && c.input.trophy_ids.some((id) => !trophyIds.has(id as number))) ||
      (c.name === "save_session_summary" && c.input.session_id !== SESSION_ID),
  );
  checks.push({ name: "known_ids", pass: unknown.length === 0, detail: unknown.map((c) => c.name).join(", ") || undefined });
  if (!allowSpoilers) {
    const shown = visibleText(record).toLowerCase();
    const named = HIDDEN_NAMES.filter((name) => shown.includes(name.toLowerCase()));
    checks.push({ name: "no_hidden_spoiler", pass: named.length === 0, detail: named.join(", ") || undefined });
  }
  return checks;
}

export function caseCheck(record: RunRecord, check: Check): CheckResult {
  const reply = visibleText(record).toLowerCase();
  switch (check.kind) {
    case "called": {
      const pass = record.calls.some((c) => check.anyOf.includes(c.name));
      return { name: `called ${check.anyOf.join("|")}`, pass, detail: pass ? undefined : record.calls.map((c) => c.name).join(", ") || "no tools" };
    }
    case "notCalled": {
      const called = record.calls.filter((c) => check.tools.includes(c.name)).map((c) => c.name);
      return { name: `not called ${check.tools.join("|")}`, pass: called.length === 0, detail: called.join(", ") || undefined };
    }
    case "toolArgs": {
      const calls = record.calls.filter((c) => c.name === check.tool && !c.error);
      const pass = calls.some((c) => check.match(c.input));
      return { name: check.label, pass, detail: pass ? undefined : JSON.stringify(calls.map((c) => c.input)).slice(0, 300) };
    }
    case "textHas": {
      const missing = check.groups.filter((group) => !group.some((word) => reply.includes(word.toLowerCase())));
      return { name: check.label, pass: missing.length === 0, detail: missing.map((g) => g.join("|")).join("; ") || undefined };
    }
    case "textLacks": {
      const found = check.words.filter((word) => reply.includes(word.toLowerCase()));
      return { name: check.label, pass: found.length === 0, detail: found.join(", ") || undefined };
    }
    case "searched":
      return { name: "searched the web", pass: record.searches.length > 0 };
  }
}
