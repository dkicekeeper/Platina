// What web_fetch gives a walkthrough build: finds a guide page (PowerPyx first) and reads it with
// each version of the fetch tool, then counts what the build could use: the page's text, image
// URLs (pictures of the spots) and YouTube ids, in the fetch result itself and in the code the
// newer version runs to filter it. Answers "why do chapter steps come without pictures".
//
//   ANTHROPIC_API_KEY=... npx tsx scripts/probe-fetch.ts "Lies of P"
//
// Two short model calls; manual only (Actions → Assistant server → probe).

import Anthropic from "@anthropic-ai/sdk";

const game = process.argv[2] || "Lies of P";
const client = new Anthropic({ maxRetries: 1 });
const IMAGE = /https?:\/\/[^\s"'<>()[\]]+?\.(?:jpe?g|png|webp|gif)(?:\?[^\s"'<>()[\]]*)?/gi;
const YOUTUBE = /(?:youtube\.com\/(?:watch\?(?:[^\s"'<>]*&)?v=|embed\/|shorts\/)|youtu\.be\/)([A-Za-z0-9_-]{11})/g;

function strings(value: unknown, out: string[] = [], depth = 0): string[] {
  if (depth > 8) return out;
  if (typeof value === "string") out.push(value);
  else if (Array.isArray(value)) value.forEach((v) => strings(v, out, depth + 1));
  else if (value && typeof value === "object") for (const [k, v] of Object.entries(value)) if (k !== "encrypted_content") strings(v, out, depth + 1);
  return out;
}

async function probe(fetchType: "web_fetch_20250910" | "web_fetch_20260209", searchType: "web_search_20250305" | "web_search_20260209") {
  console.log(`\n=== ${fetchType} + ${searchType}`);
  const message = await client.beta.messages
    .stream({
      model: "claude-sonnet-5-5",
      max_tokens: 4000,
      tools: [
        { type: searchType, name: "web_search", max_uses: 2, allowed_domains: ["powerpyx.com", "psnprofiles.com"] },
        { type: fetchType, name: "web_fetch", max_uses: 1, max_content_tokens: 20000, allowed_domains: ["powerpyx.com", "psnprofiles.com"] },
      ] as Anthropic.Beta.BetaToolUnion[],
      messages: [
        {
          role: "user",
          content: `Find PowerPyx's walkthrough or collectible locations guide for ${game} (or PSNProfiles' if PowerPyx has none), fetch the page, and list the image URLs that show collectible locations in the first chapter, exactly as they appear in the page. Then stop.`,
        },
      ],
    })
    .finalMessage();
  for (const block of message.content) {
    const type = block.type;
    if (type === "text") continue;
    const texts = strings(block);
    const text = texts.join("\n");
    const images = [...new Set([...text.matchAll(IMAGE)].map((m) => m[0]))];
    const videos = [...new Set([...text.matchAll(YOUTUBE)].map((m) => m[1]))];
    const url = (block as { content?: { url?: string } }).content?.url ?? "";
    console.log(`block ${type}${url ? ` ${url}` : ""}: ${text.length} chars, ${images.length} image URLs, ${videos.length} YouTube ids`);
    for (const image of images.slice(0, 5)) console.log(`   image ${image}`);
  }
  const answer = message.content.filter((b) => b.type === "text").map((b) => (b as { text: string }).text).join("");
  const answerImages = [...new Set([...answer.matchAll(IMAGE)].map((m) => m[0]))];
  console.log(`answer: ${answerImages.length} image URLs; stop ${message.stop_reason}; in ${message.usage.input_tokens}, out ${message.usage.output_tokens}`);
  for (const image of answerImages.slice(0, 5)) console.log(`   answer image ${image}`);
}

try {
  await probe("web_fetch_20250910", "web_search_20250305");
  await probe("web_fetch_20260209", "web_search_20260209");
} catch (error) {
  console.log(`FAILED: ${error instanceof Anthropic.APIError ? `API ${error.status}: ${JSON.stringify(error.error).slice(0, 1000)}` : String(error)}`);
  process.exit(1);
}
