// A server-sent events response the handler writes into while it works.

export interface EventStream {
  readonly response: Response;
  /** Writes one event. Never throws: once the app has gone, writes are dropped. */
  send(event: string, data: unknown): Promise<void>;
  close(): Promise<void>;
  /** Called once if the app closes the connection before the stream ends. */
  onDisconnect(handler: () => void): void;
}

/** How often a comment line goes out while nothing else does: a build reads pages and thinks for
 * minutes, and the app (and any proxy on the way) gives up on a silent connection. */
export const HEARTBEAT_MS = 15_000;

export function eventStream(headers: Record<string, string> = {}, heartbeatMs = HEARTBEAT_MS): EventStream {
  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();
  let closing = false;
  // An SSE comment: readers skip it.
  const heartbeat = heartbeatMs > 0 ? setInterval(() => void writer.write(encoder.encode(": ping\n\n")).catch(() => undefined), heartbeatMs) : undefined;
  const handlers: (() => void)[] = [];
  // The reader went away (the app closed the chat or lost the connection): the writer errors.
  writer.closed.catch(() => {
    if (heartbeat) clearInterval(heartbeat);
    if (!closing) handlers.forEach((handler) => handler());
  });
  return {
    response: new Response(readable, { headers: { "content-type": "text/event-stream", "cache-control": "no-store", ...headers } }),
    send: (event, data) => writer.write(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`)).catch(() => undefined),
    close: async () => {
      closing = true;
      if (heartbeat) clearInterval(heartbeat);
      await writer.close().catch(() => undefined);
    },
    onDisconnect: (handler) => {
      handlers.push(handler);
    },
  };
}
