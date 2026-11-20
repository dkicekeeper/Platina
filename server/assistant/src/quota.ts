import type { Config } from "./config";
import type { KVLike } from "./kv";

// Soft quotas in Workers KV (docs/assistant.md §2). KV is eventually consistent, so two calls
// from different locations in the same second can both pass the last slot: acceptable for a
// monthly or daily budget. The global daily counter is a soft stop on spend; the Anthropic
// Console's spend limit is the hard one behind it.
//
//   calls:<key>:<YYYY-MM>     model calls of one App Attest key this month   MONTHLY_CALLS
//   guides:<key>:<YYYY-MM-DD> guide builds of one key today                  DAILY_GUIDES
//   calls:all:<YYYY-MM-DD>    every model call today, a guide weighing more  GLOBAL_DAILY_CALLS

export type QuotaReason = "monthly" | "daily" | "global";

export interface QuotaStatus {
  allowed: boolean;
  used: number;
  limit: number;
  reason?: QuotaReason;
  /** What an allowed call took, so it can be given back (`refund`). */
  charge?: Charge;
}

/** The counters one allowed call raised, and by how much. */
export interface Charge {
  /** The caller's own counter (monthly calls or daily guides), raised by one. */
  ownKey: string;
  ownTtl: number;
  /** The global daily counter, raised by `weight`. */
  globalKey: string;
  weight: number;
}

const month = (now: Date) => now.toISOString().slice(0, 7);
const day = (now: Date) => now.toISOString().slice(0, 10);
const MONTH_TTL = 40 * 24 * 3600;
const DAY_TTL = 2 * 24 * 3600;

async function read(kv: KVLike, key: string): Promise<number> {
  const value = await kv.get(key);
  const parsed = Number.parseInt(value ?? "0", 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

/** One model call of the chat (POST /v1/turn). `caller` is `key:<App Attest key id>` or `dev`. */
export async function consumeCall(kv: KVLike, caller: string, config: Config, now = new Date()): Promise<QuotaStatus> {
  return consume(kv, { key: `calls:${caller}:${month(now)}`, ttl: MONTH_TTL, limit: config.monthlyCalls, reason: "monthly" }, 1, config, now);
}

/** One guide build (POST /v1/guide): its own daily count, and `guideCallWeight` calls of the
 * global daily stop. */
export async function consumeGuide(kv: KVLike, caller: string, config: Config, now = new Date()): Promise<QuotaStatus> {
  return consume(kv, { key: `guides:${caller}:${day(now)}`, ttl: DAY_TTL, limit: config.dailyGuides, reason: "daily" }, config.guideCallWeight, config, now);
}

async function consume(
  kv: KVLike,
  own: { key: string; ttl: number; limit: number; reason: QuotaReason },
  weight: number,
  config: Config,
  now: Date,
): Promise<QuotaStatus> {
  const globalKey = `calls:all:${day(now)}`;
  const [used, global] = await Promise.all([read(kv, own.key), read(kv, globalKey)]);

  if (global + weight > config.globalDailyCalls) return { allowed: false, used, limit: own.limit, reason: "global" };
  if (used >= own.limit) return { allowed: false, used, limit: own.limit, reason: own.reason };

  // KV takes one write per second per key and refuses more with an error. The daily key is
  // shared by every call, so two calls in the same second would fail one of them: a lost count
  // is cheaper than a lost answer.
  await Promise.all([
    kv.put(own.key, String(used + 1), { expirationTtl: own.ttl }).catch(() => undefined),
    kv.put(globalKey, String(global + weight), { expirationTtl: DAY_TTL }).catch(() => undefined),
  ]);
  return { allowed: true, used: used + 1, limit: own.limit, charge: { ownKey: own.key, ownTtl: own.ttl, globalKey, weight } };
}

/** Gives back what an allowed call took when the model never answered it (Anthropic down,
 * overloaded or refusing the request before any output): such a call costs nothing, so it
 * should not eat the person's allowance or the day. Never goes below zero. */
export async function refund(kv: KVLike, charge: Charge): Promise<void> {
  const lower = async (key: string, by: number, ttl: number) => {
    const value = await read(kv, key);
    await kv.put(key, String(Math.max(0, value - by)), { expirationTtl: ttl }).catch(() => undefined);
  };
  await Promise.all([lower(charge.ownKey, 1, charge.ownTtl), lower(charge.globalKey, charge.weight, DAY_TTL)]);
}
