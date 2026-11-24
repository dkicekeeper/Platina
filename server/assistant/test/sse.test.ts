import { describe, expect, it } from "vitest";
import { eventStream } from "../src/sse";

describe("eventStream", () => {
  it("keeps a quiet stream alive with comment lines, and stops them on close", async () => {
    const sse = eventStream({}, 10);
    // Read as the network does, while the stream is written.
    const reading = sse.response.text();
    await new Promise((resolve) => setTimeout(resolve, 35));
    await sse.send("walkthrough", { ok: true });
    await sse.close();
    const text = await reading;
    expect(text).toContain(": ping\n\n");
    expect(text).toContain('event: walkthrough\ndata: {"ok":true}\n\n');
    expect(text.trimEnd().endsWith('{"ok":true}')).toBe(true);
  });
});
