import { describe, expect, it } from "vitest";
import { CASES } from "../eval/cases";
import { appContext, COTL, executeTool, HIDDEN_NAMES, SESSION_ID, ToolInputError, type SimulatorState } from "../eval/fixture";
import { caseCheck, inLanguage, universalChecks, type RunRecord } from "../eval/grade";
import { cost, emptyUsage } from "../eval/pricing";
import { TOOL_NAMES } from "../src/tools";

// The eval runs against the real API by hand (eval/run.ts); its grader and simulator are
// checked here, for free.

const state = (extra: Partial<SimulatorState> = {}): SimulatorState => ({ locale: "ru", sessionRunning: false, writes: [], ...extra });
const record = (reply: string, calls: RunRecord["calls"] = []): RunRecord => ({ calls, searches: [], reply });

describe("the eval's cases", () => {
  it("have unique ids, both languages, and name only real tools", () => {
    expect(new Set(CASES.map((c) => c.id)).size).toBe(CASES.length);
    expect(CASES.some((c) => c.locale === "ru") && CASES.some((c) => c.locale === "en")).toBe(true);
    for (const c of CASES) {
      for (const check of c.checks) {
        const names = check.kind === "called" ? check.anyOf : check.kind === "notCalled" ? check.tools : check.kind === "toolArgs" ? [check.tool] : [];
        for (const name of names) expect(TOOL_NAMES.has(name)).toBe(true);
      }
    }
  });
});

describe("the simulator", () => {
  it("keeps hidden trophies hidden unless asked", () => {
    const hidden = executeTool("list_trophies", { game_id: COTL, filter: "unearned" }, state()) as { trophies: { id: number; name: string | null }[] };
    expect(hidden.trophies.find((t) => t.id === 49)!.name).toBeNull();
    const shown = executeTool("list_trophies", { game_id: COTL, include_hidden_details: true }, state({ locale: "en" })) as { trophies: { id: number; name: string | null }[] };
    expect(shown.trophies.find((t) => t.id === 49)!.name).toBe("The Prodigal Child");
  });

  it("records writes and refuses unknown ids as the app would", () => {
    const s = state();
    expect(executeTool("save_session_summary", { session_id: SESSION_ID, summary: "x", next_steps: "y" }, s)).toEqual({ saved: true });
    expect(s.writes).toHaveLength(1);
    expect(() => executeTool("get_game", { game_id: "NPWR00000_00" }, s)).toThrow(ToolInputError);
    expect(() => executeTool("set_session_goals", { game_id: COTL, trophy_ids: [999] }, s)).toThrow(ToolInputError);
  });

  it("writes the app context the prompt describes", () => {
    expect(appContext("ru", { game: COTL, session: true })).toBe(
      "<app_context>\ntoday: 2026-11-20 (Friday)\nlanguage: ru\npsn: TrophyFox, level 342\ngame: Cult of the Lamb (NPWR28536_00)\nsession: sess_42, Cult of the Lamb (NPWR28536_00), started 19:05\n</app_context>",
    );
  });
});

describe("the grader", () => {
  it("tells the reply's language, names of games aside", () => {
    expect(inLanguage("Добей **Ratchet & Clank: Rift Apart**: осталось 13% и пара часов.", "ru")).toBe(true);
    expect(inLanguage("Finish Ratchet & Clank first.", "ru")).toBe(false);
    expect(inLanguage("Finish Ratchet & Clank first: [PowerPyx](https://www.powerpyx.com/x).", "en")).toBe(true);
  });

  it("catches a hidden trophy named without permission", () => {
    const spoiled = universalChecks(record(`Не забудь «${HIDDEN_NAMES[0]}».`), "ru", false);
    expect(spoiled.find((c) => c.name === "no_hidden_spoiler")).toMatchObject({ pass: false });
    expect(universalChecks(record(`«${HIDDEN_NAMES[0]}» получишь в конце.`), "ru", true).some((c) => c.name === "no_hidden_spoiler")).toBe(false);
  });

  it("checks tools and their inputs", () => {
    const run = record("Готово.", [{ name: "set_game_status", input: { game_id: COTL, status: "skip" } }]);
    expect(caseCheck(run, { kind: "called", anyOf: ["set_game_status"] }).pass).toBe(true);
    expect(caseCheck(run, { kind: "notCalled", tools: ["set_game_status"] }).pass).toBe(false);
    expect(caseCheck(run, { kind: "toolArgs", tool: "set_game_status", match: (i) => i.status === "later", label: "x" }).pass).toBe(false);
    expect(universalChecks(record("Ок.", [{ name: "get_game", input: { game_id: "NPWR00000_00" } }]), "ru", false).find((c) => c.name === "known_ids")!.pass).toBe(false);
  });

  it("prices web searches with the tokens", () => {
    expect(cost("claude-haiku-5-5", { ...emptyUsage(), input_tokens: 1_000_000, web_search_requests: 2 })).toBeCloseTo(0.12);
  });
});
