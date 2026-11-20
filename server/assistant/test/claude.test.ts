import Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import { buildParams, donePayload, errorPayload, normalizeForEcho, TurnEventMapper, type TurnEvent } from "../src/claude";
import { readConfig } from "../src/config";
import { SYSTEM_PROMPT } from "../src/prompt";
import { eventsOf, message, searchResult, searchUse, textBlock, toolUse, userTurn } from "./helpers";

type Block = Anthropic.Beta.BetaContentBlock;

describe("buildParams", () => {
  it("binds thinking blocks with drop_block, and opts into the fallback only where the model has one", () => {
    const haiku = buildParams(readConfig({}), "ru", [userTurn("hi")]);
    expect(haiku.model).toBe("claude-haiku-5-5");
    expect(haiku.thinking).toEqual({ type: "adaptive", block_binding: { prefix_mismatch_behavior: "drop_block" } });
    expect(haiku.betas).toEqual(["thinking-binding-controls-2026-08-01"]);
    expect(haiku.fallbacks).toBeUndefined();
    const sonnet = buildParams(readConfig({ ASSISTANT_MODEL: "claude-sonnet-5-5" }), "ru", [userTurn("hi")]);
    expect(sonnet.fallbacks).toBe("default");
    expect(sonnet.betas).toEqual(["thinking-binding-controls-2026-08-01", "server-side-fallback-2026-07-01"]);
  });

  it("keeps the cached prefix stable and the language after it", () => {
    const a = buildParams(readConfig({}), "ru", [userTurn("one")]);
    const b = buildParams(readConfig({}), "ru", [userTurn("two")]);
    expect(JSON.stringify(a.tools)).toBe(JSON.stringify(b.tools));
    expect(JSON.stringify(a.system)).toBe(JSON.stringify(b.system));
    const system = a.system as Anthropic.Beta.BetaTextBlockParam[];
    expect(system[0]).toEqual({ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } });
    expect(system[1]!.text).toContain("Russian");
    const english = buildParams(readConfig({}), "en", [userTurn("one")]).system as Anthropic.Beta.BetaTextBlockParam[];
    expect(english[0]).toEqual(system[0]);
    expect(english[1]!.text).toContain("English");
    expect(a.cache_control).toEqual({ type: "ephemeral" });
    expect(a.tool_choice).toEqual({ type: "auto" });
    expect(a.output_config).toEqual({ effort: "low" });
    expect(a.stream).toBe(true);
  });

  it("offers web search with the chat model's version only when it is on", () => {
    const on = buildParams(readConfig({ WEB_SEARCH_ENABLED: "true", WEB_SEARCH_MAX_USES: "2" }), "ru", [userTurn("hi")]);
    expect(on.tools!.at(-1)).toEqual({ type: "web_search_20250305", name: "web_search", max_uses: 2 });
    const off = buildParams(readConfig({ WEB_SEARCH_ENABLED: "false" }), "ru", [userTurn("hi")]);
    expect(off.tools!.some((t) => "name" in t && t.name === "web_search")).toBe(false);
  });
});

describe("normalizeForEcho", () => {
  const thinking = { type: "thinking", thinking: "", signature: "s" } as Block;
  const fallback = { type: "fallback", from: { model: "claude-sonnet-5-5" }, to: { model: "claude-sonnet-5" } } as unknown as Block;

  it("leaves ordinary turns untouched", () => {
    const content = [thinking, textBlock("a"), toolUse("toolu_1", "get_profile", {})];
    expect(normalizeForEcho(content)).toBe(content);
  });

  it("drops the declined model's thinking and calls before the last fallback, and keeps the marker in place", () => {
    const before = toolUse("toolu_1", "get_profile", {});
    const after = toolUse("toolu_2", "get_profile", {});
    const paired = [searchUse("srv_1", "q"), searchResult("srv_1", ["https://a.example"])];
    const unpaired = searchUse("srv_2", "q2");
    expect(normalizeForEcho([thinking, textBlock("partial"), ...paired, unpaired, before, fallback, thinking, textBlock("rest"), after])).toEqual([
      textBlock("partial"),
      ...paired,
      fallback,
      thinking,
      textBlock("rest"),
      after,
    ]);
  });
});

describe("TurnEventMapper", () => {
  const map = (msg: Anthropic.Beta.BetaMessage) => {
    const mapper = new TurnEventMapper();
    return eventsOf(msg).flatMap((event) => mapper.map(event));
  };

  it("streams text, the phone's tool calls as they start, and each search with its query", () => {
    const events = map(
      message(
        [
          { type: "thinking", thinking: "", signature: "s" } as Block,
          textBlock("Смотрю трофеи"),
          searchUse("srv_1", "Cult of the Lamb missable trophies"),
          searchResult("srv_1", ["https://www.powerpyx.com/cult-of-the-lamb-trophy-guide-roadmap/"]),
          toolUse("toolu_1", "list_trophies", { game_id: "NPWR28536_00" }),
        ],
        "tool_use",
      ),
    );
    expect(events).toEqual<TurnEvent[]>([
      { event: "text", data: { text: "Смотрю " } },
      { event: "text", data: { text: "трофеи" } },
      { event: "search", data: { query: "Cult of the Lamb missable trophies" } },
      { event: "tool", data: { name: "list_trophies" } },
    ]);
  });

  it("reports a search whose input arrives whole, and skips one without a query", () => {
    const mapper = new TurnEventMapper();
    const start = (input: unknown) =>
      mapper.map({ type: "content_block_start", index: 0, content_block: { type: "server_tool_use", id: "s", name: "web_search", input } } as never);
    expect(start({ query: "glitched trophy" })).toEqual([{ event: "search", data: { query: "glitched trophy" } }]);
    expect(start({})).toEqual([]);
    mapper.map({ type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: '{"q": 1}' } } as never);
    expect(mapper.map({ type: "content_block_stop", index: 0 } as never)).toEqual([]);
  });
});

describe("donePayload", () => {
  it("returns the turn, its stop reason and usage with web searches", () => {
    const done = donePayload([message([textBlock("ok")], "end_turn", { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: null, cache_creation_input_tokens: 3, server_tool_use: { web_search_requests: 1 } } as never)]);
    expect(done).toMatchObject({ content: [textBlock("ok")], stop_reason: "end_turn", refused: false, truncated: false, model: "claude-haiku-5-5" });
    expect(done.usage).toEqual({ input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 0, cache_creation_input_tokens: 3, web_search_requests: 1 });
  });

  it("joins a paused turn and its continuation into one turn", () => {
    const paused = message([searchUse("srv_1", "q"), searchResult("srv_1", ["https://a.example"])], "pause_turn");
    const rest = message([textBlock("found it")], "end_turn");
    const done = donePayload([paused, rest]);
    expect(done.content.map((b) => b.type)).toEqual(["server_tool_use", "web_search_tool_result", "text"]);
    expect(done.stop_reason).toBe("end_turn");
    expect(done.usage.input_tokens).toBe(200);
  });

  it("discards refused turns and flags tool input cut off by max_tokens", () => {
    expect(donePayload([message([textBlock("partial")], "refusal")])).toMatchObject({ refused: true, content: [] });
    expect(donePayload([message([toolUse("t", "save_note", {})], "max_tokens")]).truncated).toBe(true);
    expect(donePayload([message([textBlock("long")], "max_tokens")]).truncated).toBe(false);
  });
});

describe("errorPayload", () => {
  // An error event in the middle of a stream: no HTTP status, the type from its body.
  const streamError = (type: string) => new Anthropic.APIError(undefined, { type: "error", error: { type, message: "x" } }, undefined, undefined, type as never);

  it("lets the app retry an overloaded or failing upstream", () => {
    expect(errorPayload(streamError("overloaded_error"))).toEqual({ code: "upstream_busy", retryable: true });
    expect(errorPayload(streamError("api_error"))).toEqual({ code: "upstream_unavailable", retryable: true });
    expect(errorPayload(new Anthropic.APIConnectionError({ message: "down" }))).toEqual({ code: "upstream_unavailable", retryable: true });
  });

  it("does not offer a retry that cannot help", () => {
    expect(errorPayload(streamError("billing_error"))).toEqual({ code: "upstream_unavailable", retryable: false });
    expect(errorPayload(streamError("invalid_request_error"))).toEqual({ code: "bad_request", retryable: false });
    expect(errorPayload(new Error("boom"))).toEqual({ code: "internal", retryable: false });
  });
});
