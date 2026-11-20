// USD per million tokens (Anthropic first-party prices, November 2026; Haiku 5.5 for prompts up
// to 100K tokens). Cache writes are the 5-minute TTL (1.25x input).
export interface Price {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
}

export const PRICING: Record<string, Price> = {
  "claude-opus-5-5": { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 },
  "claude-sonnet-5-5": { input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5 },
  "claude-haiku-5-5": { input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite: 0.125 },
};

/** Anthropic's web search: $10 per 1 000 searches, on top of the tokens its results add. */
export const WEB_SEARCH_USD = 0.01;

export interface Usage {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens: number;
  cache_creation_input_tokens: number;
  web_search_requests: number;
}

export const emptyUsage = (): Usage => ({ input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, web_search_requests: 0 });

export function addUsage(total: Usage, usage: { input_tokens?: number | null; output_tokens?: number | null; cache_read_input_tokens?: number | null; cache_creation_input_tokens?: number | null; server_tool_use?: { web_search_requests?: number } | null }): void {
  total.input_tokens += usage.input_tokens ?? 0;
  total.output_tokens += usage.output_tokens ?? 0;
  total.cache_read_input_tokens += usage.cache_read_input_tokens ?? 0;
  total.cache_creation_input_tokens += usage.cache_creation_input_tokens ?? 0;
  total.web_search_requests += usage.server_tool_use?.web_search_requests ?? 0;
}

export function cost(model: string, usage: Usage): number {
  const p = PRICING[model];
  if (!p) return Number.NaN;
  return (
    (usage.input_tokens * p.input + usage.output_tokens * p.output + usage.cache_read_input_tokens * p.cacheRead + usage.cache_creation_input_tokens * p.cacheWrite) / 1_000_000 +
    usage.web_search_requests * WEB_SEARCH_USD
  );
}

// Upper bound before a run: ~4 calls per case, ~9k input and ~800 output tokens per call, no
// cache discount, one search in a case out of three.
export function estimate(model: string, cases: number): number {
  return cost(model, { input_tokens: cases * 4 * 9000, output_tokens: cases * 4 * 800, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, web_search_requests: Math.ceil(cases / 3) });
}
