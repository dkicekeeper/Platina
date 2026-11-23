import { describe, expect, it } from "vitest";
import { languageInstruction, PROMPT_VERSION, SYSTEM_PROMPT } from "../src/prompt";
import { chatTools, DISPLAY_TOOL_NAMES, PHONE_TOOLS, TOOL_NAMES, webFetchTool, webSearchTool } from "../src/tools";

// The phone tools are the contract with the app (docs/assistant.md §5).

const schema = (name: string) => PHONE_TOOLS.find((t) => t.name === name)!.input_schema as unknown as {
  properties: Record<string, { enum?: string[]; type?: string; items?: { type?: string } }>;
  required: string[];
  additionalProperties: boolean;
};

describe("phone tools", () => {
  it("are exactly the twenty of the contract, in a fixed order", () => {
    expect(PHONE_TOOLS.map((t) => t.name)).toEqual([
      "get_profile",
      "list_games",
      "get_game",
      "list_trophies",
      "get_guide",
      "get_game_help",
      "get_walkthrough",
      "get_chapter",
      "set_walkthrough_progress",
      "get_sessions",
      "get_current_session",
      "set_session_goals",
      "set_game_status",
      "save_note",
      "save_session_summary",
      "show_checklist",
      "show_step",
      "show_trophies",
      "show_warning",
      "suggest_replies",
    ]);
    expect(TOOL_NAMES.size).toBe(20);
    expect([...DISPLAY_TOOL_NAMES].every((name) => TOOL_NAMES.has(name))).toBe(true);
  });

  it("have the contract's inputs", () => {
    expect(Object.keys(schema("get_profile").properties)).toEqual([]);
    expect(schema("list_games").properties.filter!.enum).toEqual(["in_progress", "chasing", "platinum", "not_started", "shelved", "all"]);
    expect(Object.keys(schema("list_games").properties)).toEqual(["filter", "limit"]);
    expect(schema("get_game").required).toEqual(["game_id"]);
    expect(Object.keys(schema("list_trophies").properties)).toEqual(["game_id", "filter", "type", "group_id", "include_hidden_details", "limit"]);
    expect(schema("list_trophies").properties.filter!.enum).toEqual(["unearned", "earned", "all"]);
    expect(schema("list_trophies").required).toEqual(["game_id"]);
    expect(schema("get_guide").required).toEqual(["game_id"]);
    expect(schema("get_game_help").required).toEqual(["game_id"]);
    expect(Object.keys(schema("get_game_help").properties)).toEqual(["game_id", "trophy_ids"]);
    expect(schema("get_game_help").properties.trophy_ids!.items!.type).toBe("integer");
    expect(schema("get_walkthrough").required).toEqual(["game_id"]);
    expect(Object.keys(schema("get_chapter").properties)).toEqual(["game_id", "chapter_id"]);
    expect(schema("get_chapter").required).toEqual(["game_id"]);
    expect(Object.keys(schema("set_walkthrough_progress").properties)).toEqual(["game_id", "chapter_id", "done_step_ids", "undone_step_ids", "chapter_done", "current"]);
    expect(schema("set_walkthrough_progress").required).toEqual(["game_id", "chapter_id"]);
    expect(Object.keys(schema("get_sessions").properties)).toEqual(["game_id", "limit"]);
    expect(Object.keys(schema("get_current_session").properties)).toEqual([]);
    expect(schema("set_session_goals").required).toEqual(["game_id", "trophy_ids"]);
    expect(schema("set_session_goals").properties.trophy_ids!.items!.type).toBe("integer");
    expect(Object.keys(schema("set_session_goals").properties)).toEqual(["game_id", "trophy_ids", "note"]);
    expect(schema("set_game_status").properties.status!.enum).toEqual(["chasing", "later", "skip", "none"]);
    expect(schema("save_note").required).toEqual(["game_id", "text"]);
    expect(Object.keys(schema("save_note").properties)).toEqual(["game_id", "trophy_id", "text"]);
    expect(schema("save_session_summary").required).toEqual(["session_id", "summary", "next_steps"]);
    expect(schema("show_checklist").required).toEqual(["game_id", "chapter_id", "step_ids"]);
    expect(schema("show_step").required).toEqual(["game_id", "chapter_id", "step_id"]);
    expect(schema("show_trophies").properties.trophy_ids!.items!.type).toBe("integer");
    expect(schema("show_warning").properties.kind!.enum).toEqual(["missable", "choice", "point_of_no_return", "glitch", "online", "other"]);
    expect(schema("show_warning").required).toEqual(["kind", "text"]);
    expect(schema("suggest_replies").required).toEqual(["replies"]);
  });

  it("take no field they don't describe, and require only fields they have", () => {
    for (const tool of PHONE_TOOLS) {
      const s = schema(tool.name);
      expect(s.additionalProperties).toBe(false);
      for (const field of s.required) expect(Object.keys(s.properties)).toContain(field);
      expect(tool.description!.length).toBeGreaterThan(60);
    }
  });
});

describe("web search", () => {
  it("is the dynamic-filtering version only on the models that have it", () => {
    expect(webSearchTool("claude-haiku-5-5", 3)).toEqual({ type: "web_search_20250305", name: "web_search", max_uses: 3 });
    expect(webSearchTool("claude-sonnet-5-5", 5)).toEqual({ type: "web_search_20260209", name: "web_search", max_uses: 5 });
    expect(webSearchTool("claude-haiku-5-5", 2, ["stratege.ru"])).toMatchObject({ allowed_domains: ["stratege.ru"] });
  });

  it("joins the chat's tools, last, only when it is on", () => {
    const on = chatTools({ model: "claude-haiku-5-5", webSearch: true, webSearchMaxUses: 3 });
    expect(on).toHaveLength(21);
    expect(on.at(-1)).toMatchObject({ name: "web_search" });
    expect(chatTools({ model: "claude-haiku-5-5", webSearch: false, webSearchMaxUses: 3 })).toHaveLength(20);
  });
});

describe("web fetch", () => {
  it("takes the filtering version where the model has it, with a page size cap", () => {
    expect(webFetchTool("claude-haiku-5-5", 2)).toEqual({ type: "web_fetch_20250910", name: "web_fetch", max_uses: 2, max_content_tokens: 20000 });
    expect(webFetchTool("claude-sonnet-5-5", 4, ["powerpyx.com"])).toEqual({
      type: "web_fetch_20260209",
      name: "web_fetch",
      max_uses: 4,
      max_content_tokens: 20000,
      allowed_domains: ["powerpyx.com"],
    });
  });
});

describe("the prompt", () => {
  it("has no per-request values: it is the cached prefix", () => {
    expect(SYSTEM_PROMPT).not.toMatch(/\d{4}-\d{2}-\d{2}/);
    expect(PROMPT_VERSION).toMatch(/^\d{4}-\d{2}-\d{2}\.\d+$/);
  });

  it("knows the tools of the session flow and the spoiler switch", () => {
    for (const name of ["set_session_goals", "save_session_summary", "get_current_session", "get_guide", "include_hidden_details", "<app_context>"]) {
      expect(SYSTEM_PROMPT).toContain(name);
    }
  });

  it("names the reply language in its second block", () => {
    expect(languageInstruction("ru")).toContain("Russian");
    expect(languageInstruction("ru")).toContain("ты");
    expect(languageInstruction("en")).toContain("English");
  });
});
