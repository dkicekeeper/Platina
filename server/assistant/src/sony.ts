// PSN for the trophy watcher (docs/assistant.md §9): the server's own grant from an
// authorization code the app asked Sony for, its refresh, and the few reads the watcher makes.
// The client is the PlayStation App's, as PSNKit's (ios/Packages/PlatinaKit/Sources/PSNKit).
// Nothing here logs a token or an answer's content.

export type Fetcher = (input: Request | string | URL, init?: RequestInit) => Promise<Response>;

const OAUTH_TOKEN = "https://ca.account.sony.com/api/authz/v3/oauth/token";
// clientID:clientSecret of the PlayStation App, as every PSN client sends them (psn-api, PSNAWP).
const BASIC = "Basic MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A=";
const REDIRECT_URI = "com.scee.psxandroid.scecompcall://redirect";
const SCOPE = "psn:mobile.v2.core psn:clientapp";
const API = "https://m.np.playstation.com/api/";

/** A token pair and when each half runs out (ms since the epoch). */
export interface Grant {
  accessToken: string;
  accessExpiresAt: number;
  refreshToken: string;
  refreshExpiresAt: number;
}

/** `refused`: Sony no longer accepts the code or the refresh token (sign in again);
 * `hidden`: PSN will not show it (privacy); `unavailable`: anything else, try later. */
export class SonyError extends Error {
  constructor(
    readonly kind: "refused" | "hidden" | "unavailable",
    readonly status = 0,
  ) {
    super(`sony ${kind}${status ? ` ${status}` : ""}`);
  }
}

async function requestGrant(fields: Record<string, string>, fetcher: Fetcher, now: number): Promise<Grant> {
  let response: Response;
  try {
    response = await fetcher(OAUTH_TOKEN, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded", authorization: BASIC },
      body: new URLSearchParams(fields).toString(),
    });
  } catch {
    throw new SonyError("unavailable");
  }
  if (!response.ok) {
    let error = "";
    try {
      error = ((await response.json()) as { error?: string }).error ?? "";
    } catch {
      // Not JSON: an outage page.
    }
    if ((response.status === 400 || response.status === 401) && (error === "invalid_grant" || error === "invalid_request")) {
      throw new SonyError("refused", response.status);
    }
    throw new SonyError("unavailable", response.status);
  }
  const body = (await response.json()) as {
    access_token?: unknown;
    expires_in?: unknown;
    refresh_token?: unknown;
    refresh_token_expires_in?: unknown;
  };
  if (typeof body.access_token !== "string" || typeof body.refresh_token !== "string") throw new SonyError("unavailable");
  const seconds = (value: unknown, fallback: number) => (typeof value === "number" && value > 0 ? value : fallback);
  return {
    accessToken: body.access_token,
    accessExpiresAt: now + seconds(body.expires_in, 3600) * 1000,
    refreshToken: body.refresh_token,
    refreshExpiresAt: now + seconds(body.refresh_token_expires_in, 5_184_000) * 1000,
  };
}

/** The server's own tokens for a code the app asked Sony for (never the phone's tokens). */
export function exchangeCode(code: string, fetcher: Fetcher, now = Date.now()): Promise<Grant> {
  return requestGrant({ code, redirect_uri: REDIRECT_URI, grant_type: "authorization_code", token_format: "jwt" }, fetcher, now);
}

/** A fresh access token; Sony may hand back the same refresh token with its old expiry. */
export function refreshGrant(refreshToken: string, fetcher: Fetcher, now = Date.now()): Promise<Grant> {
  return requestGrant({ refresh_token: refreshToken, grant_type: "refresh_token", token_format: "jwt", scope: SCOPE }, fetcher, now);
}

// MARK: - Reads

async function get<T>(path: string, accessToken: string, fetcher: Fetcher, language = "en-US"): Promise<T> {
  let response: Response;
  try {
    response = await fetcher(API + path, {
      headers: { authorization: `Bearer ${accessToken}`, "accept-language": language, accept: "application/json" },
    });
  } catch {
    throw new SonyError("unavailable");
  }
  if (response.status === 401) throw new SonyError("refused", 401);
  if (response.status === 403) throw new SonyError("hidden", 403);
  if (!response.ok) throw new SonyError("unavailable", response.status);
  return (await response.json()) as T;
}

/** The account the grant belongs to. */
export async function accountId(accessToken: string, fetcher: Fetcher): Promise<string> {
  const summary = await get<{ accountId?: unknown }>("trophy/v1/users/me/trophySummary", accessToken, fetcher);
  if (typeof summary.accountId !== "string" || !/^\d{1,24}$/.test(summary.accountId)) throw new SonyError("unavailable");
  return summary.accountId;
}

/** Whether a game is running on the console now; `hidden` when presence is private. */
export async function isPlaying(account: string, accessToken: string, fetcher: Fetcher): Promise<boolean> {
  const body = await get<{ basicPresence?: { gameTitleInfoList?: unknown[] } }>(
    `userProfile/v1/internal/users/${account}/basicPresences?type=primary`,
    accessToken,
    fetcher,
  );
  return (body.basicPresence?.gameTitleInfoList?.length ?? 0) > 0;
}

/** One trophy list as the watcher keeps it: earned trophies in all, and when it last changed. */
export interface TrophyList {
  id: string;
  service: string;
  name: string;
  earned: number;
  updated: string;
}

const total = (counts: unknown) =>
  counts && typeof counts === "object"
    ? Object.values(counts as Record<string, unknown>).reduce<number>((sum, value) => sum + (typeof value === "number" ? value : 0), 0)
    : 0;

/** The lists changed last, newest first (PSN's own order): the first page is enough. */
export async function recentLists(accessToken: string, fetcher: Fetcher, limit = 20): Promise<TrophyList[]> {
  const body = await get<{ trophyTitles?: Array<Record<string, unknown>> }>(
    `trophy/v1/users/me/trophyTitles?limit=${limit}&offset=0`,
    accessToken,
    fetcher,
  );
  return (body.trophyTitles ?? []).flatMap((title) => {
    const id = title.npCommunicationId;
    if (typeof id !== "string") return [];
    const platform = typeof title.trophyTitlePlatform === "string" ? title.trophyTitlePlatform : "";
    // The app follows PS5 and PS4 games (docs/plans/2026-11-25-platina-1.1-design.md).
    if (!/PS5|PS4/.test(platform)) return [];
    return [
      {
        id,
        service: typeof title.npServiceName === "string" ? title.npServiceName : "trophy2",
        name: typeof title.trophyTitleName === "string" ? title.trophyTitleName : "",
        earned: total(title.earnedTrophies),
        updated: typeof title.lastUpdatedDateTime === "string" ? title.lastUpdatedDateTime : "",
      },
    ];
  });
}

export type TrophyType = "bronze" | "silver" | "gold" | "platinum";

/** A trophy just earned: what a notification says about it. */
export interface EarnedTrophy {
  id: number;
  type: TrophyType;
  name: string;
  earnedAt: string;
}

const isType = (value: unknown): value is TrophyType => value === "bronze" || value === "silver" || value === "gold" || value === "platinum";

/** The trophies of a list earned after `since` (an ISO date; empty: every earned one), with
 * their names in the person's language. Two requests. */
export async function earnedSince(list: TrophyList, since: string, language: string, accessToken: string, fetcher: Fetcher): Promise<EarnedTrophy[]> {
  const query = `npServiceName=${encodeURIComponent(list.service)}`;
  const earned = await get<{ trophies?: Array<Record<string, unknown>> }>(
    `trophy/v1/users/me/npCommunicationIds/${encodeURIComponent(list.id)}/trophyGroups/all/trophies?${query}`,
    accessToken,
    fetcher,
  );
  const sinceTime = since ? Date.parse(since) : Number.NEGATIVE_INFINITY;
  const fresh = (earned.trophies ?? []).filter(
    (trophy) => trophy.earned === true && typeof trophy.earnedDateTime === "string" && Date.parse(trophy.earnedDateTime) > sinceTime,
  );
  if (fresh.length === 0) return [];
  const definitions = await get<{ trophies?: Array<Record<string, unknown>> }>(
    `trophy/v1/npCommunicationIds/${encodeURIComponent(list.id)}/trophyGroups/all/trophies?${query}`,
    accessToken,
    fetcher,
    language === "ru" ? "ru-RU" : "en-US",
  );
  const names = new Map<number, { name: string; type: unknown }>();
  for (const trophy of definitions.trophies ?? []) {
    if (typeof trophy.trophyId === "number") {
      names.set(trophy.trophyId, { name: typeof trophy.trophyName === "string" ? trophy.trophyName : "", type: trophy.trophyType });
    }
  }
  return fresh
    .flatMap((trophy) => {
      if (typeof trophy.trophyId !== "number") return [];
      const known = names.get(trophy.trophyId);
      const type = isType(trophy.trophyType) ? trophy.trophyType : isType(known?.type) ? known.type : "bronze";
      return [{ id: trophy.trophyId, type, name: known?.name ?? "", earnedAt: trophy.earnedDateTime as string }];
    })
    .sort((a, b) => a.earnedAt.localeCompare(b.earnedAt));
}
