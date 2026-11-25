// The trophy watcher (docs/assistant.md §9): one Durable Object per app install (named by its
// App Attest key) that looks at PSN with the server's own grant and sends a push for every new
// trophy, the app open or not.
//
//   idle      every 5 min: is a game running on the console? (presence, one request)
//   active    every 60 s: the trophy lists changed last (one request); a list with more earned
//             trophies → its trophies earned since the last look and their names → one push per
//             game, the platinum its own. After two quiet checks presence is asked again: no game
//             running → idle.
//   hidden    presence is private: the lists every 10 min instead (presence tried again daily).
//
// The first check after subscribing only records the lists (no flood of old trophies). Sony
// refusing the refresh token → one "sign in again" push, then everything is erased; APNs saying
// the device token is gone → everything is erased. Tokens are kept sealed (vault.ts).

import { sendPush, type ApnsConfig, type PushContent, type PushTarget } from "./apns";
import { signInAgainAlert, trophyAlerts, type AlertLanguage } from "./alerts-text";
import { earnedSince, isPlaying, recentLists, refreshGrant, SonyError, type Fetcher, type Grant } from "./sony";
import { open, seal } from "./vault";

export interface WatcherEnv {
  TOKEN_KEY?: string;
  APNS_KEY_P8?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_TOPIC?: string;
}

export const WATCH = {
  idle: 5 * 60_000,
  active: 60_000,
  hidden: 10 * 60_000,
  /** The first check, soon after subscribing. */
  first: 5_000,
  /** Presence private: tried again after a day. */
  hiddenRetry: 24 * 3600_000,
  /** Quiet active checks before presence is asked again. */
  quietChecks: 2,
  /** Changed lists read in one check; the rest wait for the next. */
  listsPerCheck: 3,
  /** Lists remembered (the most recently changed). */
  keptLists: 200,
  /** Errors in a row back off up to this. */
  maxBackoff: 60 * 60_000,
} as const;

export interface Subscription {
  accountId: string;
  refresh: string;
  refreshExpiresAt: number;
  access: string;
  accessExpiresAt: number;
  pushToken: string;
  environment: PushTarget["environment"];
  language: AlertLanguage;
  mode: "idle" | "active";
  quiet: number;
  hiddenSince: number | null;
  failures: number;
  lastCheckedAt: number | null;
}

type Lists = Record<string, { earned: number; updated: string }>;

/** What the Worker hands over when the app turns notifications on. */
export interface SubscribeRequest {
  grant: Grant;
  accountId: string;
  pushToken: string;
  environment: PushTarget["environment"];
  language: AlertLanguage;
}

/** The part of DurableObjectStorage the watcher uses (a fake one in the tests). */
export interface WatcherStorage {
  get<T>(key: string): Promise<T | undefined>;
  put<T>(key: string, value: T): Promise<void>;
  deleteAll(): Promise<void>;
  setAlarm(time: number): Promise<void>;
  deleteAlarm(): Promise<void>;
}

export interface WatcherDeps {
  fetcher: Fetcher;
  now: () => number;
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

export class TrophyWatcher {
  private readonly storage: WatcherStorage;
  private readonly deps: WatcherDeps;

  constructor(
    state: { storage: WatcherStorage },
    private readonly env: WatcherEnv,
    deps?: Partial<WatcherDeps>,
  ) {
    this.storage = state.storage;
    this.deps = { fetcher: deps?.fetcher ?? ((input, init) => fetch(input, init)), now: deps?.now ?? (() => Date.now()) };
  }

  /** The Worker's calls: POST /subscribe, POST /token, POST /unsubscribe. */
  async fetch(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (path === "/subscribe") {
      await this.subscribe((await request.json()) as SubscribeRequest);
      return json({ ok: true });
    }
    if (path === "/token") {
      const body = (await request.json()) as { pushToken: string; environment: PushTarget["environment"] };
      const sub = await this.storage.get<Subscription>("sub");
      if (!sub) return json({ error: "not_found" }, 404);
      await this.storage.put("sub", { ...sub, pushToken: body.pushToken, environment: body.environment });
      return json({ ok: true });
    }
    if (path === "/unsubscribe") {
      await this.erase();
      return json({ ok: true });
    }
    return json({ error: "not_found" }, 404);
  }

  async subscribe(request: SubscribeRequest): Promise<void> {
    const key = this.tokenKey();
    // A new grant starts over: the first check records the lists as they are now.
    await this.storage.deleteAll();
    const sub: Subscription = {
      accountId: request.accountId,
      refresh: await seal(key, request.grant.refreshToken),
      refreshExpiresAt: request.grant.refreshExpiresAt,
      access: await seal(key, request.grant.accessToken),
      accessExpiresAt: request.grant.accessExpiresAt,
      pushToken: request.pushToken,
      environment: request.environment,
      language: request.language,
      mode: "idle",
      quiet: 0,
      hiddenSince: null,
      failures: 0,
      lastCheckedAt: null,
    };
    await this.storage.put("sub", sub);
    await this.storage.setAlarm(this.deps.now() + WATCH.first);
  }

  async alarm(): Promise<void> {
    const sub = await this.storage.get<Subscription>("sub");
    if (!sub) return;
    const delay = await this.check(sub);
    if (delay !== null) await this.storage.setAlarm(this.deps.now() + delay);
  }

  /** One look at PSN; the time to the next one, or null once the watcher has stopped. */
  private async check(sub: Subscription): Promise<number | null> {
    if (!this.env.TOKEN_KEY || !this.apns()) return WATCH.maxBackoff;
    const now = this.deps.now();
    if (sub.hiddenSince !== null && now - sub.hiddenSince > WATCH.hiddenRetry) sub.hiddenSince = null;
    try {
      const token = await this.accessToken(sub);
      const firstLook = (await this.storage.get<Lists>("lists")) === undefined;

      if (sub.hiddenSince === null && !firstLook) {
        const asksPresence = sub.mode === "idle" || sub.quiet >= WATCH.quietChecks;
        if (asksPresence) {
          let playing: boolean | null;
          try {
            playing = await isPlaying(sub.accountId, token, this.deps.fetcher);
          } catch (error) {
            if (!(error instanceof SonyError) || error.kind !== "hidden") throw error;
            sub.hiddenSince = now;
            playing = null;
          }
          if (playing === false) {
            sub.mode = "idle";
            sub.quiet = 0;
            sub.failures = 0;
            await this.storage.put("sub", sub);
            return WATCH.idle;
          }
          if (playing === true) {
            sub.mode = "active";
            sub.quiet = 0;
          }
        }
      }

      const found = await this.checkLists(sub, token);
      if (found === "stopped") return null;
      sub.quiet = found ? 0 : sub.quiet + 1;
      sub.failures = 0;
      sub.lastCheckedAt = now;
      await this.storage.put("sub", sub);
      if (sub.hiddenSince !== null) return WATCH.hidden;
      return sub.mode === "active" ? WATCH.active : WATCH.idle;
    } catch (error) {
      if (error instanceof SonyError && error.kind === "refused") {
        if (error.status === 401 && sub.accessExpiresAt > now && sub.failures < 3) {
          // The access token went bad early: refresh it on the next look (a few times at most).
          sub.accessExpiresAt = 0;
          sub.failures += 1;
          await this.storage.put("sub", sub);
          return WATCH.active;
        }
        await this.stop(sub, true);
        return null;
      }
      sub.failures += 1;
      await this.storage.put("sub", sub);
      console.log(`watcher ${error instanceof SonyError ? error.message : "error"}`);
      return Math.min(WATCH.idle * 2 ** (sub.failures - 1), WATCH.maxBackoff);
    }
  }

  /** The lists changed last against the ones kept: true when trophies were found (and sent). */
  private async checkLists(sub: Subscription, token: string): Promise<boolean | "stopped"> {
    const lists = await recentLists(token, this.deps.fetcher);
    const kept = await this.storage.get<Lists>("lists");
    const next: Lists = { ...(kept ?? {}) };
    if (!kept) {
      for (const list of lists) next[list.id] = { earned: list.earned, updated: list.updated };
      await this.storage.put("lists", this.trim(next));
      return false;
    }
    const changed = lists.filter((list) => list.earned > (kept[list.id]?.earned ?? 0));
    const read = changed.slice(0, WATCH.listsPerCheck);
    let found = false;
    for (const list of lists) {
      if (changed.includes(list) && !read.includes(list)) continue; // Waits for the next check.
      next[list.id] = { earned: list.earned, updated: list.updated };
    }
    for (const list of read) {
      // A list not seen before came up because it just changed: what was earned since the last
      // look (with a margin for the clocks), not the whole game.
      const since = kept[list.id]?.updated ?? new Date((sub.lastCheckedAt ?? this.deps.now()) - WATCH.idle).toISOString();
      const trophies = await earnedSince(list, since, sub.language, token, this.deps.fetcher);
      if (trophies.length === 0) continue;
      found = true;
      for (const alert of trophyAlerts(sub.language, { id: list.id, name: list.name }, trophies)) {
        if ((await this.push(sub, alert)) === "gone") {
          await this.erase();
          return "stopped";
        }
      }
    }
    await this.storage.put("lists", this.trim(next));
    return found;
  }

  /** The most recently changed lists, so the record stays small. */
  private trim(lists: Lists): Lists {
    const entries = Object.entries(lists);
    if (entries.length <= WATCH.keptLists) return lists;
    entries.sort((a, b) => b[1].updated.localeCompare(a[1].updated));
    return Object.fromEntries(entries.slice(0, WATCH.keptLists));
  }

  private async accessToken(sub: Subscription): Promise<string> {
    const key = this.tokenKey();
    const now = this.deps.now();
    // A token sealed under another TOKEN_KEY can't be read: as good as refused.
    const unseal = (sealed: string) => open(key, sealed).catch(() => Promise.reject(new SonyError("refused")));
    if (sub.accessExpiresAt - now > 60_000) return unseal(sub.access);
    if (sub.refreshExpiresAt <= now) throw new SonyError("refused");
    const grant = await refreshGrant(await unseal(sub.refresh), this.deps.fetcher, now);
    sub.access = await seal(key, grant.accessToken);
    sub.accessExpiresAt = grant.accessExpiresAt;
    sub.refresh = await seal(key, grant.refreshToken);
    // Sony may answer a refresh with the same refresh token and a new lifetime, or the old one.
    sub.refreshExpiresAt = Math.max(grant.refreshExpiresAt, sub.refreshExpiresAt);
    await this.storage.put("sub", sub);
    return grant.accessToken;
  }

  private async push(sub: Subscription, content: PushContent) {
    const apns = this.apns();
    if (!apns) return "failed" as const;
    return sendPush(apns, { token: sub.pushToken, environment: sub.environment }, content, this.deps.fetcher, this.deps.now());
  }

  /** Sony stopped accepting the grant: say so once, then forget everything. */
  private async stop(sub: Subscription, tellsPerson: boolean): Promise<void> {
    if (tellsPerson) await this.push(sub, signInAgainAlert(sub.language));
    await this.erase();
  }

  private async erase(): Promise<void> {
    await this.storage.deleteAlarm();
    await this.storage.deleteAll();
  }

  private tokenKey(): string {
    if (!this.env.TOKEN_KEY) throw new Error("TOKEN_KEY is not set");
    return this.env.TOKEN_KEY;
  }

  private apns(): ApnsConfig | null {
    if (!this.env.APNS_KEY_P8 || !this.env.APNS_KEY_ID) return null;
    return {
      keyP8: this.env.APNS_KEY_P8,
      keyId: this.env.APNS_KEY_ID,
      teamId: this.env.APNS_TEAM_ID ?? "SY2L2VMQP7",
      topic: this.env.APNS_TOPIC ?? "dakacom.Platina",
    };
  }
}
