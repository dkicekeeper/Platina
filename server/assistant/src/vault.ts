// The watcher's PSN tokens at rest (docs/assistant.md §9): AES-GCM under the secret TOKEN_KEY
// (32 random bytes in Base64, made once by the deploy workflow). A sealed value is
// Base64(iv ‖ ciphertext); a wrong key or a changed value fails to open.

const toBase64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const fromBase64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));

async function importKey(secret: string): Promise<CryptoKey> {
  const raw = fromBase64(secret.trim());
  if (raw.length !== 32) throw new Error("TOKEN_KEY must be 32 bytes in Base64");
  return crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

export async function seal(secret: string, text: string): Promise<string> {
  const key = await importKey(secret);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, new TextEncoder().encode(text)));
  const out = new Uint8Array(iv.length + cipher.length);
  out.set(iv);
  out.set(cipher, iv.length);
  return toBase64(out);
}

export async function open(secret: string, sealed: string): Promise<string> {
  const key = await importKey(secret);
  const bytes = fromBase64(sealed);
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: bytes.slice(0, 12) }, key, bytes.slice(12));
  return new TextDecoder().decode(plain);
}
