// The subset of KVNamespace this server uses (its overloaded `get` defeats Pick<>). Tests pass
// an in-memory map (test/helpers.ts).
export interface KVLike {
  get(key: string): Promise<string | null>;
  put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void>;
}
