// Apple Push Notification service for the trophy watcher (docs/assistant.md §9): token-based
// auth (the .p8 key in the secret APNS_KEY_P8, its id in APNS_KEY_ID), an ES256 JWT reused for
// 50 minutes as Apple asks, HTTP/2 through fetch.

import type { Fetcher } from "./sony";

export interface ApnsConfig {
  keyP8: string;
  keyId: string;
  teamId: string;
  topic: string;
}

export interface PushTarget {
  token: string;
  environment: "sandbox" | "production";
}

export interface PushContent {
  title: string;
  body: string;
  threadId: string;
  /** Read by the app when the notification is tapped. */
  data?: Record<string, unknown>;
}

/** `gone`: the device token is no longer valid (the app was deleted, or notifications went off
 * for good): stop sending to it. */
export type PushResult = "sent" | "gone" | "failed";

const base64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const encodeJSON = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));

async function importP8(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

let cached: { jwt: string; keyId: string; issuedAt: number } | undefined;

/** The provider token: made again after 50 minutes (Apple refuses one older than an hour, and
 * one made more often than every 20 minutes). */
export async function providerToken(config: ApnsConfig, now = Date.now()): Promise<string> {
  if (cached && cached.keyId === config.keyId && now - cached.issuedAt < 50 * 60 * 1000) return cached.jwt;
  const header = encodeJSON({ alg: "ES256", kid: config.keyId });
  const payload = encodeJSON({ iss: config.teamId, iat: Math.floor(now / 1000) });
  const key = await importP8(config.keyP8);
  // WebCrypto signs ECDSA as r ‖ s, the form a JWT wants.
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${payload}`)));
  const jwt = `${header}.${payload}.${base64url(signature)}`;
  cached = { jwt, keyId: config.keyId, issuedAt: now };
  return jwt;
}

/** Forgets the provider token (tests, or after Apple refused it). */
export function resetProviderToken(): void {
  cached = undefined;
}

export async function sendPush(config: ApnsConfig, target: PushTarget, content: PushContent, fetcher: Fetcher, now = Date.now()): Promise<PushResult> {
  const host = target.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const payload = {
    aps: { alert: { title: content.title, body: content.body }, sound: "default", "thread-id": content.threadId },
    ...content.data,
  };
  let response: Response;
  try {
    response = await fetcher(`https://${host}/3/device/${target.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${await providerToken(config, now)}`,
        "apns-topic": config.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });
  } catch {
    return "failed";
  }
  if (response.ok) return "sent";
  if (response.status === 410) return "gone";
  let reason = "";
  try {
    reason = ((await response.json()) as { reason?: string }).reason ?? "";
  } catch {
    // No body.
  }
  if (response.status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic")) return "gone";
  if (response.status === 403 && (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken")) resetProviderToken();
  console.log(`apns ${response.status} ${reason}`);
  return "failed";
}
