// The Worker's bindings and variables (wrangler.toml [vars], secrets) and their parsed form.

export interface Env {
  /** App Attest challenges and registered keys. */
  ATTEST: KVNamespace;
  /** Call and guide counters. */
  QUOTA: KVNamespace;
  /** Built guides (`{npCommunicationId}:{language}`, 30 days) and parsed Stratege pages. */
  GUIDES: KVNamespace;
  ANTHROPIC_API_KEY: string;
  /** Optional secret: with it set, `x-platina-dev: <DEV_TOKEN>` passes without App Attest. */
  DEV_TOKEN?: string;
  ASSISTANT_ENABLED?: string;
  ASSISTANT_MODEL?: string;
  ASSISTANT_EFFORT?: string;
  ASSISTANT_MAX_TOKENS?: string;
  GUIDE_MODEL?: string;
  GUIDE_EFFORT?: string;
  GUIDE_MAX_TOKENS?: string;
  GUIDE_MAX_SEARCHES?: string;
  WALKTHROUGH_MAX_FETCHES?: string;
  IMAGE_SOURCES?: string;
  WEB_SEARCH_ENABLED?: string;
  WEB_SEARCH_MAX_USES?: string;
  MONTHLY_CALLS?: string;
  DAILY_GUIDES?: string;
  GLOBAL_DAILY_CALLS?: string;
  GUIDE_CALL_WEIGHT?: string;
  BLOCKED_COUNTRIES?: string;
  APP_ID?: string;
}

export type Effort = "low" | "medium" | "high" | "xhigh" | "max";

const EFFORTS: readonly Effort[] = ["low", "medium", "high", "xhigh", "max"];

export interface Config {
  enabled: boolean;
  /** The chat's model (POST /v1/turn). */
  model: string;
  effort: Effort;
  maxTokens: number;
  /** The guide builder's model (POST /v1/guide). */
  guideModel: string;
  guideEffort: Effort;
  guideMaxTokens: number;
  /** Web searches one guide build may make, $0.01 each. */
  guideMaxSearches: number;
  /** Pages one walkthrough model call may read with web fetch ("0": search results only). */
  walkthroughMaxFetches: number;
  /** Sites whose pictures a walkthrough step may show, loaded from there with credit and a
   * link (docs/PLAN.md §10). Empty: no pictures from guides. */
  imageSources: string[];
  /** The chat gets the server-side web_search tool. */
  webSearch: boolean;
  /** Web searches per chat call. */
  webSearchMaxUses: number;
  /** Model calls per App Attest key per calendar month (UTC). */
  monthlyCalls: number;
  /** Guide builds per App Attest key per day (UTC); a cached guide is free. */
  dailyGuides: number;
  /** All model calls in a day (UTC), across everyone: the spend fuse. */
  globalDailyCalls: number;
  /** A guide build counts as this many calls in the global daily stop: its searches and its
   * long answer on the guide model cost about that many chat calls. */
  guideCallWeight: number;
  blockedCountries: Set<string>;
  /** TEAMID.bundle-id, the app App Attest assertions must come from. */
  appId: string;
}

function int(value: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

const effortOf = (value: string | undefined, fallback: Effort): Effort => (EFFORTS.includes(value as Effort) ? (value as Effort) : fallback);

export function readConfig(env: Partial<Env>): Config {
  return {
    enabled: env.ASSISTANT_ENABLED !== "false",
    model: env.ASSISTANT_MODEL || "claude-haiku-5-5",
    effort: effortOf(env.ASSISTANT_EFFORT, "low"),
    maxTokens: Math.max(1024, int(env.ASSISTANT_MAX_TOKENS, 16000)),
    guideModel: env.GUIDE_MODEL || "claude-sonnet-5-5",
    guideEffort: effortOf(env.GUIDE_EFFORT, "medium"),
    guideMaxTokens: Math.max(4096, int(env.GUIDE_MAX_TOKENS, 32000)),
    guideMaxSearches: Math.min(int(env.GUIDE_MAX_SEARCHES, 5), 20),
    walkthroughMaxFetches: Math.min(int(env.WALKTHROUGH_MAX_FETCHES, 4), 10),
    imageSources: (env.IMAGE_SOURCES ?? "powerpyx.com,psnprofiles.com,stratege.ru,playstationtrophies.org")
      .split(",")
      .map((s) => s.trim().toLowerCase().replace(/^www\./, ""))
      .filter(Boolean),
    webSearch: env.WEB_SEARCH_ENABLED === "true",
    webSearchMaxUses: Math.max(1, Math.min(int(env.WEB_SEARCH_MAX_USES, 3), 10)),
    monthlyCalls: int(env.MONTHLY_CALLS, 3000),
    dailyGuides: int(env.DAILY_GUIDES, 20),
    globalDailyCalls: int(env.GLOBAL_DAILY_CALLS, 3000),
    guideCallWeight: Math.max(1, int(env.GUIDE_CALL_WEIGHT, 50)),
    blockedCountries: new Set(
      (env.BLOCKED_COUNTRIES ?? "RU,BY")
        .split(",")
        .map((c) => c.trim().toUpperCase())
        .filter(Boolean),
    ),
    appId: env.APP_ID || "SY2L2VMQP7.dakacom.Platina",
  };
}
