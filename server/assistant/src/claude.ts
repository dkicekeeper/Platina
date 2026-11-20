import Anthropic from "@anthropic-ai/sdk";
import type { Config } from "./config";
import { languageInstruction, SYSTEM_PROMPT, type Language } from "./prompt";
import { chatTools } from "./tools";
import type { TurnMessage } from "./validate";

export type Params = Anthropic.Beta.Messages.MessageCreateParamsStreaming;
type ContentBlock = Anthropic.Beta.BetaContentBlock;
type StreamEvent = Anthropic.Beta.BetaRawMessageStreamEvent;

// Models that accept the server-side refusal fallback in its "default" form. Claude Haiku 5.5
// has none: a refusal is returned as is (the app drops the turn).
const SERVER_FALLBACK_MODELS = new Set(["claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-opus-5"]);
const FALLBACK_BETA = "server-side-fallback-2026-07-01";

// A thinking block is bound to everything sent before it: the system prompt, the tools and the
// earlier messages. Kept conversations outlive both: a deploy changes SYSTEM_PROMPT or the
// tools, a change of the app's language changes the second system block, and the app may drop
// the oldest messages of a long chat. On an enforced account such a block is a 400 that no
// retry fixes, so the chat would be dead. "drop_block" drops the stale blocks instead and the
// turn goes on without that reasoning.
export const THINKING_BINDING_BETA = "thinking-binding-controls-2026-08-01";

/** The betas and fallback a request on `model` carries. */
export function modelExtras(model: string): Pick<Params, "betas" | "fallbacks"> {
  return SERVER_FALLBACK_MODELS.has(model)
    ? { betas: [THINKING_BINDING_BETA, FALLBACK_BETA], fallbacks: "default" }
    : { betas: [THINKING_BINDING_BETA] };
}

export function buildParams(config: Config, language: Language, messages: TurnMessage[]): Params {
  return {
    model: config.model,
    max_tokens: config.maxTokens,
    // Stable prefix: tools, then the prompt (a read point shared by every conversation), then
    // the language line. Per-person context lives in the messages.
    system: [
      { type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } },
      { type: "text", text: languageInstruction(language) },
    ],
    tools: chatTools(config),
    // Forced tool choice is a 400 on several current models, and the chat must be free to answer.
    tool_choice: { type: "auto" },
    thinking: { type: "adaptive", block_binding: { prefix_mismatch_behavior: "drop_block" } },
    output_config: { effort: config.effort },
    // Caches the conversation as it grows, across the turn's calls.
    cache_control: { type: "ephemeral" },
    messages,
    stream: true,
    ...modelExtras(config.model),
  };
}

// MARK: - Echo

// After a mid-output fallback, blocks before the last `fallback` block that belong to the
// declined model must not be sent back: thinking, redacted thinking, tool calls, and a server
// tool call whose result never came. Text and paired server-tool blocks stay. The `fallback`
// block itself stays exactly where it is: the API checks the thinking blocks around it by its
// position. Applied once, before the app stores the turn, so the stored history is already the
// form to echo. (Claude Haiku 5.5 has no server-side fallback: this matters only when
// ASSISTANT_MODEL is a model that has one, and for the guide builder.)
const DROP_BEFORE_FALLBACK = new Set(["thinking", "redacted_thinking", "tool_use"]);

export function normalizeForEcho(content: ContentBlock[]): ContentBlock[] {
  let boundary = -1;
  content.forEach((block, index) => {
    if (block.type === "fallback") boundary = index;
  });
  if (boundary < 0) return content;
  // The ids server tool calls got their results for.
  const answered = new Set(content.flatMap((block) => ("tool_use_id" in block && typeof block.tool_use_id === "string" ? [block.tool_use_id] : [])));
  return content.filter((block, index) => {
    if (index >= boundary) return true;
    if (DROP_BEFORE_FALLBACK.has(block.type)) return false;
    if (block.type === "server_tool_use") return answered.has(block.id);
    return true;
  });
}

// MARK: - Stream → SSE

export type TurnEvent =
  | { event: "text"; data: { text: string } }
  | { event: "tool"; data: { name: string } }
  | { event: "search"; data: { query: string } };

/** Maps one model stream's events to the app's SSE events (docs/assistant.md §3): text deltas,
 * the phone's tool calls as they start, and each web search with its query once the query is
 * whole. One mapper per model call: block indexes restart with each message. */
export class TurnEventMapper {
  /** Web search calls being streamed: block index → the input JSON so far. */
  private readonly searches = new Map<number, string>();

  map(event: StreamEvent): TurnEvent[] {
    switch (event.type) {
      case "content_block_start": {
        const block = event.content_block;
        if (block.type === "tool_use") return [{ event: "tool", data: { name: block.name } }];
        if (block.type === "server_tool_use" && block.name === "web_search") {
          const query = queryOf(block.input);
          if (query) return [{ event: "search", data: { query } }];
          this.searches.set(event.index, "");
        }
        return [];
      }
      case "content_block_delta":
        if (event.delta.type === "text_delta") return event.delta.text ? [{ event: "text", data: { text: event.delta.text } }] : [];
        if (event.delta.type === "input_json_delta" && this.searches.has(event.index)) {
          this.searches.set(event.index, this.searches.get(event.index)! + event.delta.partial_json);
        }
        return [];
      case "content_block_stop": {
        const json = this.searches.get(event.index);
        if (json === undefined) return [];
        this.searches.delete(event.index);
        let input: unknown;
        try {
          input = JSON.parse(json);
        } catch {
          return [];
        }
        const query = queryOf(input);
        return query ? [{ event: "search", data: { query } }] : [];
      }
      default:
        return [];
    }
  }
}

function queryOf(input: unknown): string | undefined {
  const query = (input as { query?: unknown } | null)?.query;
  return typeof query === "string" && query.trim() ? query.trim() : undefined;
}

// MARK: - Done

export interface Usage {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens: number;
  cache_creation_input_tokens: number;
  web_search_requests: number;
}

export const emptyUsage = (): Usage => ({ input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, web_search_requests: 0 });

export function addUsage(total: Usage, usage: Anthropic.Beta.BetaUsage): Usage {
  total.input_tokens += usage.input_tokens;
  total.output_tokens += usage.output_tokens;
  total.cache_read_input_tokens += usage.cache_read_input_tokens ?? 0;
  total.cache_creation_input_tokens += usage.cache_creation_input_tokens ?? 0;
  total.web_search_requests += usage.server_tool_use?.web_search_requests ?? 0;
  return total;
}

export interface DonePayload {
  /** The assistant turn to store and send back unchanged. */
  content: ContentBlock[];
  stop_reason: string | null;
  usage: Usage;
  model: string;
  /** The model declined: the app discards the turn (a refusal mid-answer leaves a partial). */
  refused: boolean;
  /** A tool input cut off by max_tokens can still look valid: the app never runs it. */
  truncated: boolean;
}

/** The `done` event of a turn: `content` is every message the turn's calls produced, in order
 * (more than one only when a paused web search was resumed), as one assistant turn. */
export function donePayload(messages: Anthropic.Beta.BetaMessage[]): DonePayload {
  const last = messages[messages.length - 1]!;
  const content = messages.flatMap((m) => normalizeForEcho(m.content));
  const refused = last.stop_reason === "refusal";
  const hasToolUse = last.content.some((b) => b.type === "tool_use");
  const usage = emptyUsage();
  messages.forEach((m) => addUsage(usage, m.usage));
  return {
    content: refused ? [] : content,
    stop_reason: last.stop_reason,
    usage,
    model: last.model,
    refused,
    truncated: last.stop_reason === "max_tokens" && hasToolUse,
  };
}

// MARK: - Errors

export interface ErrorPayload {
  code: "upstream_busy" | "upstream_unavailable" | "bad_request" | "internal";
  retryable: boolean;
}

export function errorPayload(error: unknown): ErrorPayload {
  if (error instanceof Anthropic.RateLimitError) return { code: "upstream_busy", retryable: true };
  if (error instanceof Anthropic.BadRequestError) return { code: "bad_request", retryable: false };
  if (error instanceof Anthropic.APIConnectionError) return { code: "upstream_unavailable", retryable: true };
  if (error instanceof Anthropic.APIError) {
    // An error event in the middle of a stream has no HTTP status, only the body's type.
    switch (error.type) {
      case "overloaded_error":
      case "rate_limit_error":
        return { code: "upstream_busy", retryable: true };
      case "api_error":
      case "timeout_error":
        return { code: "upstream_unavailable", retryable: true };
      case "invalid_request_error":
        return { code: "bad_request", retryable: false };
      case "authentication_error":
      case "permission_error":
      case "billing_error":
        return { code: "upstream_unavailable", retryable: false };
    }
    if ((error.status ?? 0) >= 500) return { code: "upstream_unavailable", retryable: true };
  }
  return { code: "internal", retryable: false };
}
