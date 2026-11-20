import { describe, expect, it } from "vitest";
import { readConfig } from "../src/config";
import { consumeCall, consumeGuide, refund } from "../src/quota";
import { MemoryKV } from "./helpers";

const now = new Date("2026-11-20T12:00:00Z");

describe("consumeCall", () => {
  it("counts calls per key per month up to MONTHLY_CALLS", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ MONTHLY_CALLS: "2" });
    expect((await consumeCall(kv, "key:a", config, now)).allowed).toBe(true);
    expect((await consumeCall(kv, "key:a", config, now)).used).toBe(2);
    expect(await consumeCall(kv, "key:a", config, now)).toMatchObject({ allowed: false, reason: "monthly", limit: 2 });
    // Another key has its own month; a new month starts from zero.
    expect((await consumeCall(kv, "key:b", config, now)).allowed).toBe(true);
    expect((await consumeCall(kv, "key:a", config, new Date("2026-12-01T00:00:00Z"))).allowed).toBe(true);
  });

  it("stops everyone at GLOBAL_DAILY_CALLS until the next day", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ GLOBAL_DAILY_CALLS: "1" });
    expect((await consumeCall(kv, "key:a", config, now)).allowed).toBe(true);
    expect(await consumeCall(kv, "key:b", config, now)).toMatchObject({ allowed: false, reason: "global" });
    expect((await consumeCall(kv, "key:b", config, new Date("2026-11-21T00:00:00Z"))).allowed).toBe(true);
  });

  it("uses the contract's defaults", () => {
    const config = readConfig({});
    expect(config).toMatchObject({ monthlyCalls: 3000, dailyGuides: 20, globalDailyCalls: 3000, model: "claude-haiku-5-5", guideModel: "claude-sonnet-5-5" });
    expect(config.blockedCountries).toEqual(new Set(["RU", "BY"]));
    expect(config.appId).toBe("SY2L2VMQP7.dakacom.Platina");
  });
});

describe("consumeGuide", () => {
  it("counts builds per key per day up to DAILY_GUIDES", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ DAILY_GUIDES: "1", GUIDE_CALL_WEIGHT: "1" });
    expect((await consumeGuide(kv, "key:a", config, now)).allowed).toBe(true);
    expect(await consumeGuide(kv, "key:a", config, now)).toMatchObject({ allowed: false, reason: "daily", limit: 1 });
    expect((await consumeGuide(kv, "key:a", config, new Date("2026-11-21T00:00:00Z"))).allowed).toBe(true);
  });

  it("weighs a build in the global daily stop", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ GLOBAL_DAILY_CALLS: "30", GUIDE_CALL_WEIGHT: "20" });
    expect((await consumeGuide(kv, "key:a", config, now)).allowed).toBe(true);
    expect(kv.store.get("calls:all:2026-11-20")).toBe("20");
    expect(await consumeGuide(kv, "key:b", config, now)).toMatchObject({ allowed: false, reason: "global" });
    // Chat calls still fit under the stop.
    expect((await consumeCall(kv, "key:b", config, now)).allowed).toBe(true);
  });
});

describe("refund", () => {
  it("gives back a call's month and day counts", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ MONTHLY_CALLS: "1" });
    const first = await consumeCall(kv, "key:a", config, now);
    expect(first.charge).toEqual({ ownKey: "calls:key:a:2026-11", ownTtl: 40 * 24 * 3600, globalKey: "calls:all:2026-11-20", weight: 1 });
    expect(await consumeCall(kv, "key:a", config, now)).toMatchObject({ allowed: false });

    await refund(kv, first.charge!);
    expect(kv.store.get("calls:key:a:2026-11")).toBe("0");
    expect(kv.store.get("calls:all:2026-11-20")).toBe("0");
    expect((await consumeCall(kv, "key:a", config, now)).allowed).toBe(true);
  });

  it("gives back a guide build with its weight, never below zero", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ GUIDE_CALL_WEIGHT: "20" });
    const build = await consumeGuide(kv, "key:a", config, now);
    await refund(kv, build.charge!);
    expect(kv.store.get("guides:key:a:2026-11-20")).toBe("0");
    expect(kv.store.get("calls:all:2026-11-20")).toBe("0");
    await refund(kv, build.charge!);
    expect(kv.store.get("calls:all:2026-11-20")).toBe("0");
  });
});
