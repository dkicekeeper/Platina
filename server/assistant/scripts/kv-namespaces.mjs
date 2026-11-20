// The Worker's KV namespaces on Cloudflare, by the Cloudflare API (.github/workflows/assistant.yml).
//
//   node scripts/kv-namespaces.mjs ensure   create the missing ones, print every id
//   node scripts/kv-namespaces.mjs fill     put the ids into wrangler.toml where it still has
//                                           a REPLACE_WITH_... placeholder (before a deploy)
//
// Needs CLOUDFLARE_API_TOKEN (Account → Workers KV Storage → Edit) and CLOUDFLARE_ACCOUNT_ID.
// The namespaces are found by title: platina-assistant-attest, -quota, -guides. Ids are not
// secrets; the token is never printed.

import { appendFileSync, readFileSync, writeFileSync } from "node:fs";

const BINDINGS = ["ATTEST", "QUOTA", "GUIDES"];
const title = (binding) => `platina-assistant-${binding.toLowerCase()}`;
const placeholder = (binding) => `REPLACE_WITH_${binding}_NAMESPACE_ID`;
const TOML = new URL("../wrangler.toml", import.meta.url);

const account = process.env.CLOUDFLARE_ACCOUNT_ID?.trim();
const token = process.env.CLOUDFLARE_API_TOKEN?.trim();
if (!account || !token) {
  console.error("CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID repository secrets are needed.");
  process.exit(1);
}

async function api(path, init = {}) {
  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/storage/kv/namespaces${path}`, {
    ...init,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.success) {
    const errors = (body.errors ?? []).map((e) => `${e.code}: ${e.message}`).join("; ");
    throw new Error(`Cloudflare API ${response.status}${errors ? ` (${errors})` : ""}. Does the token have Workers KV Storage: Edit on this account?`);
  }
  return body;
}

async function existing() {
  const all = [];
  for (let page = 1; ; page++) {
    const body = await api(`?per_page=100&page=${page}`);
    all.push(...body.result);
    if (page >= (body.result_info?.total_pages ?? 1)) return new Map(all.map((ns) => [ns.title, ns.id]));
  }
}

const command = process.argv[2];
const found = await existing().catch((error) => {
  console.error(error.message);
  process.exit(1);
});

if (command === "ensure") {
  const lines = [];
  for (const binding of BINDINGS) {
    let id = found.get(title(binding));
    if (id) {
      console.log(`${binding}: ${title(binding)} exists`);
    } else {
      id = (await api("", { method: "POST", body: JSON.stringify({ title: title(binding) }) })).result.id;
      console.log(`${binding}: ${title(binding)} created`);
    }
    lines.push(`[[kv_namespaces]]\nbinding = "${binding}"\nid = "${id}"`);
  }
  const snippet = lines.join("\n\n");
  console.log(`\nThe namespaces for server/assistant/wrangler.toml (deploy also fills them in by itself):\n\n${snippet}\n`);
  if (process.env.GITHUB_STEP_SUMMARY) {
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, `### KV namespaces\n\nFor \`server/assistant/wrangler.toml\` (the deploy action fills them in by itself when the file still has placeholders):\n\n\`\`\`toml\n${snippet}\n\`\`\`\n`);
  }
} else if (command === "fill") {
  let toml = readFileSync(TOML, "utf8");
  for (const binding of BINDINGS) {
    if (!toml.includes(placeholder(binding))) continue;
    const id = found.get(title(binding));
    if (!id) {
      console.error(`No KV namespace ${title(binding)} yet: run the workflow with action "setup" first.`);
      process.exit(1);
    }
    toml = toml.replace(placeholder(binding), id);
    console.log(`${binding}: id filled in from ${title(binding)}`);
  }
  writeFileSync(TOML, toml);
} else {
  console.error("Usage: node scripts/kv-namespaces.mjs ensure|fill");
  process.exit(1);
}
