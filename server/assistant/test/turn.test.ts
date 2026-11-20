import { beforeEach, describe, expect, it, vi } from "vitest";
import { signedHeaders, storedKey } from "./attest-helpers";
import fixture from "./fixtures/appattest.json";
import { body, MemoryKV, message, parseSSE, scriptedStream, searchResult, searchUse, textBlock, toolUse, userTurn } from "./helpers";

// POST /v1/turn with a fake Anthropic client: the streams it hands out are set per test.
const scripted = vi.hoisted(() => ({ streams: [] as (() => unknown)[], params: [] as unknown[] }));

vi.mock("@anthropic-ai/sdk", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@anthropic-ai/sdk")>();
  const Real = actual.default;
  // Inherits the error classes (static members), so errorPayload still recognises them.
  class FakeAnthropic extends Real {
    constructor(options: ConstructorParameters<typeof Real>[0]) {
      super(options);
      Object.defineProperty(this, "beta", {
        value: {
          messages: {
            stream: (params: unknown) => {
              scripted.params.push(structuredClone(params));
              return scripted.streams.shift()!();
            },
          },
        },
      });
    }
  }
  return { ...actual, default: FakeAnthropic };
});

const { default: Anthropic } = await import("@anthropic-ai/sdk");
const { default: worker } = await import("../src/index");

/** A stream that yields `events`, then fails. */
const failingStream = (events: unknown[], error: Error) => ({
  abort() {},
  async *[Symbol.asyncIterator]() {
    yield* events;
    throw error;
  },
  finalMessage: async () => {
    throw error;
  },
});

const down = () => new Anthropic.APIConnectionError({ message: "down" });

/** A stream that starts, then waits until it is aborted, as a long answer would. */
function abortableStream() {
  let aborted = false;
  let wake: (() => void) | undefined;
  const waiting = new Promise<void>((resolve) => {
    wake = resolve;
  });
  return {
    get aborted() {
      return aborted;
    },
    abort() {
      aborted = true;
      wake?.();
    },
    async *[Symbol.asyncIterator]() {
      yield { type: "message_start", message: {} };
      await waiting;
      throw new Anthropic.APIUserAbortError();
    },
    finalMessage: async () => {
      throw new Anthropic.APIUserAbortError();
    },
  };
}

interface Run {
  attest: MemoryKV;
  quota: MemoryKV;
}

/** Sends a signed turn; the caller reads (or drops) the response, then awaits `pending`. */
async function startTurn(run: Run, payload = body([userTurn("Что мне выбить сегодня?")])) {
  await run.attest.put(`attest-key:${fixture.keyId}`, await storedKey());
  const request = new Request("https://assistant.example/v1/turn", { method: "POST", headers: await signedHeaders(payload, 1), body: payload });
  const pending: Promise<unknown>[] = [];
  const ctx = { waitUntil: (p: Promise<unknown>) => pending.push(p), passThroughOnException() {} } as never;
  const env = { ATTEST: run.attest, QUOTA: run.quota, GUIDES: new MemoryKV(), ANTHROPIC_API_KEY: "test", APP_ID: fixture.appId, MONTHLY_CALLS: "5" } as never;
  const response = await worker.fetch(request, env, ctx);
  return { response, pending };
}

async function events(run: Run, payload?: string) {
  const { response, pending } = await startTurn(run, payload);
  const text = await response.text();
  await Promise.all(pending);
  return { response, events: parseSSE(text) };
}

const fresh = (): Run => ({ attest: new MemoryKV(), quota: new MemoryKV() });
const day = new Date().toISOString().slice(0, 10);
const month = day.slice(0, 7);

describe("a turn", () => {
  beforeEach(() => {
    scripted.streams = [];
    scripted.params = [];
  });

  it("streams the reply, the tool calls and the searches, then the turn to store", async () => {
    const reply = message(
      [
        searchUse("srv_1", "Cult of the Lamb patch 1.17 crash fix"),
        searchResult("srv_1", ["https://www.reddit.com/r/Trophies/x"]),
        textBlock("Сначала гляну трофеи."),
        toolUse("toolu_1", "list_trophies", { game_id: "NPWR28536_00", filter: "unearned" }),
      ],
      "tool_use",
      { server_tool_use: { web_search_requests: 1 } } as never,
    );
    scripted.streams.push(() => scriptedStream(reply));
    const run = fresh();
    const { response, events: got } = await events(run);

    expect(response.headers.get("content-type")).toBe("text/event-stream");
    expect(response.headers.get("x-platina-prompt")).toMatch(/^\d{4}-\d{2}-\d{2}\.\d+$/);
    expect(got.map((e) => e.event)).toEqual(["search", "text", "text", "tool", "done"]);
    expect(got[0]!.data).toEqual({ query: "Cult of the Lamb patch 1.17 crash fix" });
    expect(got.slice(1, 3).map((e) => e.data.text).join("")).toBe("Сначала гляну трофеи.");
    expect(got[3]!.data).toEqual({ name: "list_trophies" });
    const done = got[4]!.data;
    expect(done.content).toEqual(JSON.parse(JSON.stringify(reply.content)));
    expect(done).toMatchObject({ stop_reason: "tool_use", refused: false, truncated: false, quota: { used: 1, limit: 5 } });
    expect(done.usage).toMatchObject({ input_tokens: 100, output_tokens: 20, web_search_requests: 1 });

    // The request the model got: the server's prompt and tools, the app's messages as sent.
    const params = scripted.params[0] as { system: { text: string }[]; messages: unknown[]; tools: { name: string }[] };
    expect(params.system[1]!.text).toContain("Russian");
    expect(params.messages).toEqual([userTurn("Что мне выбить сегодня?")]);
    expect(params.tools.map((t) => t.name)).toContain("set_session_goals");
    expect(run.quota.store.get(`calls:key:${fixture.keyId}:${month}`)).toBe("1");
  });

  it("resumes a turn a long web search paused, and returns both parts as one turn", async () => {
    const paused = message([searchUse("srv_1", "q"), searchResult("srv_1", ["https://a.example"])], "pause_turn");
    const rest = message([textBlock("Нашёл.")], "end_turn");
    scripted.streams.push(() => scriptedStream(paused), () => scriptedStream(rest));
    const { events: got } = await events(fresh());
    const done = got.at(-1)!;
    expect(done.event).toBe("done");
    expect(done.data.content.map((b: { type: string }) => b.type)).toEqual(["server_tool_use", "web_search_tool_result", "text"]);
    expect(done.data.stop_reason).toBe("end_turn");
    const second = scripted.params[1] as { messages: { role: string }[] };
    expect(second.messages.map((m) => m.role)).toEqual(["user", "assistant"]);
  });

  it("gives the call back when the model never started answering", async () => {
    scripted.streams.push(() => failingStream([], down()));
    const run = fresh();
    const { events: got } = await events(run);
    expect(got).toEqual([{ event: "error", data: { code: "upstream_unavailable", retryable: true } }]);
    expect(run.quota.store.get(`calls:key:${fixture.keyId}:${month}`)).toBe("0");
    expect(run.quota.store.get(`calls:all:${day}`)).toBe("0");
  });

  it("keeps the count when the model failed in the middle of its answer", async () => {
    scripted.streams.push(() => failingStream([{ type: "message_start", message: {} }], down()));
    const run = fresh();
    const { events: got } = await events(run);
    expect(got.at(-1)!.event).toBe("error");
    expect(run.quota.store.get(`calls:key:${fixture.keyId}:${month}`)).toBe("1");
    expect(run.quota.store.get(`calls:all:${day}`)).toBe("1");
  });

  it("stops the model when the app leaves, and keeps the count", async () => {
    const stream = abortableStream();
    scripted.streams.push(() => stream);
    const run = fresh();
    const { response, pending } = await startTurn(run);
    // The app closes the chat: the response's reader goes away.
    await response.body!.cancel();
    await Promise.all(pending);
    expect(stream.aborted).toBe(true);
    expect(run.quota.store.get(`calls:key:${fixture.keyId}:${month}`)).toBe("1");
  });

  it("answers in English when the app is in English", async () => {
    scripted.streams.push(() => scriptedStream(message([textBlock("Hi!")])));
    await events(fresh(), body([userTurn("Hi")], { language: "en-US" }));
    const params = scripted.params[0] as { system: { text: string }[] };
    expect(params.system[1]!.text).toContain("English");
  });
});
