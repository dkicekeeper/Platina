// One real walkthrough build, as the server does it, outside the Worker: the plan of a game,
// then its first chapter, against the Claude API with the production prompt and tools. Prints
// every stage with its time, the longest silence of the model's stream (the app waits up to
// 240 s between bytes), errors with the API's status and message, and what came out.
//
//   ANTHROPIC_API_KEY=... npx tsx scripts/smoke-walkthrough.ts [ru|en]
//
// Spends about what one build in the app does. Manual only (Actions → Assistant server → smoke).

import Anthropic from "@anthropic-ai/sdk";
import { readFileSync } from "node:fs";
import type { Params } from "../src/claude";
import { readConfig } from "../src/config";
import type { ModelCall } from "../src/guide";
import { parseStrategePage } from "../src/stratege";
import type { GuideGame } from "../src/validate";
import { buildChapter, buildWalkthrough, WalkthroughError } from "../src/walkthrough";

class MemoryKV {
  readonly store = new Map<string, string>();
  async get(key: string) {
    return this.store.get(key) ?? null;
  }
  async put(key: string, value: string) {
    this.store.set(key, value);
  }
}

const language = process.argv[2] === "en" ? "en" : "ru";
// Another game by name: a one-trophy list stands in for its own (enough for chapters and steps).
const otherGame = process.argv[3];
const url = "https://stratege.ru/ps5/games/cult_of_the_lamb/trophies/spisok";
const page = parseStrategePage(readFileSync(new URL("../test/fixtures/stratege-cult-of-the-lamb.html", import.meta.url), "utf8"), url, "NPWR28536_00");
const hidden = new Set([18, 49, 53, 56]);
const cultOfTheLamb: GuideGame = {
  npCommunicationId: "NPWR28536_00",
  name: "Cult of the Lamb",
  platform: "PS5",
  trophies: page.trophies.map((t) => ({
    id: t.number!,
    name: t.names[1] ?? t.names[0]!,
    detail: t.description,
    type: t.type!,
    hidden: hidden.has(t.number!),
    groupId: t.number! >= 37 ? "001" : "default",
  })),
};

const game: GuideGame = otherGame
  ? {
      npCommunicationId: "NPWR99999_00",
      name: otherGame,
      platform: "PS5",
      trophies: [{ id: 0, name: "Platinum", detail: "Earn every trophy.", type: "platinum", hidden: false, groupId: "default" }],
    }
  : cultOfTheLamb;

const config = readConfig({});
const client = new Anthropic({ maxRetries: 1 });
const started = Date.now();
const at = () => `${((Date.now() - started) / 1000).toFixed(1)}s`;
let longestSilence = 0;
let calls = 0;

const call: ModelCall = async (params: Params, onEvent) => {
  calls += 1;
  const tools = (params.tools ?? []).map((t) => ("type" in t && t.type ? `${t.name}:${t.type}` : t.name)).join(", ");
  console.log(`[${at()}] model call ${calls}: ${params.model}, tools ${tools}`);
  let last = Date.now();
  const stream = client.beta.messages.stream(params);
  for await (const event of stream) {
    const now = Date.now();
    longestSilence = Math.max(longestSilence, now - last);
    last = now;
    if (event.type === "content_block_start") {
      const block = event.content_block as { type: string; name?: string; input?: unknown };
      if (block.type !== "text" && block.type !== "thinking") console.log(`[${at()}]   block ${block.type}${block.name ? ` ${block.name}` : ""}`);
    }
    onEvent(event);
  }
  const message = await stream.finalMessage();
  console.log(`[${at()}]   stop ${message.stop_reason}, in ${message.usage.input_tokens}, out ${message.usage.output_tokens}, cache read ${message.usage.cache_read_input_tokens ?? 0}`);
  return message;
};

function report(error: unknown): void {
  if (error instanceof WalkthroughError) console.log(`FAILED: ${error.code} (retryable ${error.retryable})`);
  else if (error instanceof Anthropic.APIError) console.log(`FAILED: API ${error.status}: ${JSON.stringify(error.error ?? error.message).slice(0, 2000)}`);
  else console.log(`FAILED: ${error instanceof Error ? `${error.name}: ${error.message}` : String(error)}`);
}

const kv = new MemoryKV();
const options = { config, call, kv, fetch: globalThis.fetch, onProgress: (step: string) => console.log(`[${at()}] progress ${step}`) };
let ok = true;
try {
  const { walkthrough, usage } = await buildWalkthrough(game, language, options);
  console.log(`[${at()}] PLAN: ${walkthrough.chapters.length} chapters, ${walkthrough.sources.length} sources, searches ${usage.web_search_requests}`);
  for (const c of walkthrough.chapters) console.log(`  ${c.id} ${c.title} (missable ${c.missable.length}, choices ${c.choices.length}, completion ${c.completionTrophyId})`);
  for (const s of walkthrough.sources) console.log(`  source ${s.id}: ${s.url}`);
  kv.store.set(`walk:${game.npCommunicationId}:${language}`, JSON.stringify(walkthrough));
  const first = walkthrough.chapters[0]!.id;
  const { chapter } = await buildChapter(game, language, first, options);
  console.log(`[${at()}] CHAPTER ${first}: ${chapter.steps.length} steps, images ${chapter.steps.filter((s) => s.image).length}, videos ${chapter.steps.filter((s) => s.video).length}`);
  for (const s of chapter.steps.slice(0, 8)) console.log(`  ${s.id} [${s.kind}] ${s.text.slice(0, 120)}`);
  for (const s of chapter.steps.filter((x) => x.image || x.video)) console.log(`  ${s.id} picture ${s.image?.url ?? "-"} video ${s.video?.youtubeId ?? "-"}`);
  for (const s of chapter.sources) console.log(`  source ${s.id}: ${s.url}`);
} catch (error) {
  ok = false;
  report(error);
}
console.log(`[${at()}] model calls ${calls}, longest silence in a stream ${(longestSilence / 1000).toFixed(1)}s`);
process.exit(ok ? 0 : 1);
