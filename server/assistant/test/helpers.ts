import type Anthropic from "@anthropic-ai/sdk";
import { readFileSync } from "node:fs";

// In-memory stand-in for a KV namespace: get/put, TTLs kept for the tests that check them.
export class MemoryKV {
  readonly store = new Map<string, string>();
  readonly ttls = new Map<string, number | undefined>();
  async get(key: string): Promise<string | null> {
    return this.store.get(key) ?? null;
  }
  async put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void> {
    this.store.set(key, value);
    this.ttls.set(key, options?.expirationTtl);
  }
}

export const userTurn = (text: string) => ({ role: "user" as const, content: [{ type: "text" as const, text }] });

export const body = (messages: unknown[], options: { protocol?: number; language?: string } = {}) =>
  JSON.stringify({ protocol: options.protocol ?? 1, language: options.language ?? "ru", messages });

export const fixture = (name: string) => readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8");

type Block = Anthropic.Beta.BetaContentBlock;
type Event = Anthropic.Beta.BetaRawMessageStreamEvent;

export const textBlock = (text: string): Block => ({ type: "text", text, citations: null }) as Block;
export const toolUse = (id: string, name: string, input: Record<string, unknown>): Block => ({ type: "tool_use", id, name, input }) as Block;
export const searchUse = (id: string, query: string): Block => ({ type: "server_tool_use", id, name: "web_search", input: { query } }) as Block;
export const searchResult = (toolUseId: string, urls: string[]): Block =>
  ({
    type: "web_search_tool_result",
    tool_use_id: toolUseId,
    content: urls.map((url, i) => ({ type: "web_search_result", url, title: `Result ${i + 1}`, encrypted_content: "x", page_age: null })),
  }) as unknown as Block;

export const fetchUse = (id: string, url: string): Block => ({ type: "server_tool_use", id, name: "web_fetch", input: { url } }) as Block;
export const fetchResult = (toolUseId: string, url: string, text: string): Block =>
  ({
    type: "web_fetch_tool_result",
    tool_use_id: toolUseId,
    content: { type: "web_fetch_result", url, retrieved_at: "2026-11-23T10:00:00Z", content: { type: "document", source: { type: "text", media_type: "text/plain", data: text }, title: null, citations: null } },
  }) as unknown as Block;

export function message(content: Block[], stop_reason = "end_turn", usage: Partial<Anthropic.Beta.BetaUsage> = {}): Anthropic.Beta.BetaMessage {
  return {
    id: "msg_1",
    type: "message",
    role: "assistant",
    model: "claude-haiku-5-5",
    content,
    stop_reason,
    stop_sequence: null,
    usage: { input_tokens: 100, output_tokens: 20, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, server_tool_use: null, ...usage },
  } as unknown as Anthropic.Beta.BetaMessage;
}

/** The events a streamed message arrives as: text in two deltas, tool inputs as JSON pieces. */
export function eventsOf(msg: Anthropic.Beta.BetaMessage): Event[] {
  const events: Event[] = [{ type: "message_start", message: { ...msg, content: [] } } as unknown as Event];
  msg.content.forEach((block, index) => {
    if (block.type === "text") {
      events.push({ type: "content_block_start", index, content_block: { ...block, text: "" } } as unknown as Event);
      const half = Math.ceil(block.text.length / 2);
      for (const piece of [block.text.slice(0, half), block.text.slice(half)]) {
        events.push({ type: "content_block_delta", index, delta: { type: "text_delta", text: piece } } as unknown as Event);
      }
    } else if (block.type === "tool_use" || block.type === "server_tool_use") {
      events.push({ type: "content_block_start", index, content_block: { ...block, input: {} } } as unknown as Event);
      const json = JSON.stringify(block.input);
      const half = Math.ceil(json.length / 2);
      for (const piece of [json.slice(0, half), json.slice(half)]) {
        events.push({ type: "content_block_delta", index, delta: { type: "input_json_delta", partial_json: piece } } as unknown as Event);
      }
    } else {
      events.push({ type: "content_block_start", index, content_block: block } as unknown as Event);
    }
    events.push({ type: "content_block_stop", index } as unknown as Event);
  });
  events.push({ type: "message_delta", delta: { stop_reason: msg.stop_reason, stop_sequence: null }, usage: msg.usage } as unknown as Event);
  events.push({ type: "message_stop" } as unknown as Event);
  return events;
}

/** A stream object as the SDK's MessageStream is used: async iteration, finalMessage, abort. */
export function scriptedStream(msg: Anthropic.Beta.BetaMessage) {
  return {
    abort() {},
    async *[Symbol.asyncIterator]() {
      yield* eventsOf(msg);
    },
    finalMessage: async () => msg,
  };
}

/** Reads a server-sent events body into its events. */
export function parseSSE(text: string): { event: string; data: any }[] {
  return text
    .split("\n\n")
    .filter((chunk) => chunk.trim())
    .map((chunk) => {
      const event = /^event: (.*)$/m.exec(chunk)?.[1] ?? "";
      const data = /^data: (.*)$/m.exec(chunk)?.[1] ?? "null";
      return { event, data: JSON.parse(data) };
    });
}
