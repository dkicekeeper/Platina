import type Anthropic from "@anthropic-ai/sdk";
import type { Language } from "./prompt";
import { SERVER_TOOL_NAMES, TOOL_NAMES } from "./tools";

// The app sends the whole conversation (Messages API form) on every call and appends the
// server's `done.content` verbatim, so history is append-only. This module checks the shape
// and the limits of the requests (docs/assistant.md §3, §4); it never rewrites history.

export const PROTOCOL_VERSION = 1;

export const LIMITS = {
  bodyBytes: 256 * 1024,
  messages: 80,
  // The <app_context> block and a question fit well under it; the body limit bounds the cost.
  userTextChars: 16 * 1024,
  // list_trophies of a big game with its descriptions.
  toolResultChars: 64 * 1024,
  guideTrophies: 600,
  trophyNameChars: 300,
  trophyDetailChars: 1000,
  gameNameChars: 300,
} as const;

export type TurnMessage = Anthropic.Beta.BetaUserMessageParam | Anthropic.Beta.BetaAssistantMessageParam;

export interface TurnRequest {
  protocol: number;
  language: Language;
  messages: TurnMessage[];
}

export class ValidationError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

type Json = Record<string, unknown>;

const isObject = (v: unknown): v is Json => typeof v === "object" && v !== null && !Array.isArray(v);

function parseJSON(raw: string): Json {
  if (raw.length > LIMITS.bodyBytes) throw new ValidationError("too_large");
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    throw new ValidationError("json");
  }
  if (!isObject(body)) throw new ValidationError("body");
  if (body.protocol !== PROTOCOL_VERSION) throw new ValidationError("protocol");
  return body;
}

/** The reply language: "ru" for any Russian locale, English for everything else. */
export function resolveLanguage(value: unknown): Language | undefined {
  if (typeof value !== "string" || value.length > 35 || !/^[A-Za-z]{2,3}([-_][A-Za-z0-9]{1,8})*$/.test(value)) return undefined;
  return value.toLowerCase().startsWith("ru") ? "ru" : "en";
}

// MARK: - POST /v1/turn

const USER_BLOCKS = new Set(["text", "tool_result"]);
// What Claude's own turns hold, as the app stores done.content: text (with citations from web
// search), thinking, the phone's tool calls, web search's calls and results (with the code its
// newer version runs to filter them), and the marker of a server-side fallback.
const ASSISTANT_BLOCKS = new Set([
  "text",
  "thinking",
  "redacted_thinking",
  "tool_use",
  "server_tool_use",
  "web_search_tool_result",
  "code_execution_tool_result",
  "bash_code_execution_tool_result",
  "text_editor_code_execution_tool_result",
  "fallback",
]);

function hasCacheControl(block: Json): boolean {
  if ("cache_control" in block) return true;
  return Array.isArray(block.content) && block.content.some((part) => isObject(part) && "cache_control" in part);
}

function checkUserBlock(block: Json): void {
  if (block.type === "text") {
    if (typeof block.text !== "string" || block.text.length > LIMITS.userTextChars) throw new ValidationError("user_text");
    // Citations belong to Claude's own text; on a user turn the API refuses them.
    if (Array.isArray(block.citations) && block.citations.length > 0) throw new ValidationError("citations");
    return;
  }
  // tool_result
  if (typeof block.tool_use_id !== "string") throw new ValidationError("tool_result_id");
  const content = block.content;
  const size =
    typeof content === "string"
      ? content.length
      : Array.isArray(content)
        ? content.reduce((n: number, part: unknown) => {
            if (!isObject(part) || part.type !== "text" || typeof part.text !== "string") throw new ValidationError("tool_result_content");
            return n + part.text.length;
          }, 0)
        : -1;
  if (size < 0 || size > LIMITS.toolResultChars) throw new ValidationError("tool_result_content");
}

function checkAssistantBlock(block: Json): void {
  if (block.type === "tool_use") {
    if (typeof block.id !== "string" || typeof block.name !== "string" || !TOOL_NAMES.has(block.name)) throw new ValidationError("tool_use");
    if (!isObject(block.input)) throw new ValidationError("tool_use_input");
  }
  if (block.type === "server_tool_use") {
    if (typeof block.id !== "string" || typeof block.name !== "string" || !SERVER_TOOL_NAMES.has(block.name)) throw new ValidationError("server_tool_use");
  }
}

export function parseTurnRequest(raw: string): TurnRequest {
  const body = parseJSON(raw);
  const language = resolveLanguage(body.language);
  if (!language) throw new ValidationError("language");
  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > LIMITS.messages) throw new ValidationError("messages");

  messages.forEach((message: unknown, index) => {
    if (!isObject(message)) throw new ValidationError("message");
    // role "system" carries operator authority in the Messages API; only the server sets it.
    if (message.role !== "user" && message.role !== "assistant") throw new ValidationError("role");
    if (index === 0 && message.role !== "user") throw new ValidationError("first_role");
    const content = message.content;
    const blocks: unknown[] = typeof content === "string" ? [{ type: "text", text: content }] : Array.isArray(content) ? content : [];
    if (blocks.length === 0) throw new ValidationError("content");
    const allowed = message.role === "user" ? USER_BLOCKS : ASSISTANT_BLOCKS;
    for (const block of blocks) {
      if (!isObject(block) || typeof block.type !== "string" || !allowed.has(block.type)) throw new ValidationError("block_type");
      if (hasCacheControl(block)) throw new ValidationError("cache_control");
      if (message.role === "user") checkUserBlock(block);
      else checkAssistantBlock(block);
    }
  });

  const last = messages[messages.length - 1] as Json;
  if (last.role !== "user") throw new ValidationError("last_role");
  return { protocol: PROTOCOL_VERSION, language, messages: messages as TurnMessage[] };
}

// MARK: - POST /v1/guide

export type TrophyType = "platinum" | "gold" | "silver" | "bronze";
const TROPHY_TYPES: readonly TrophyType[] = ["platinum", "gold", "silver", "bronze"];

export interface GuideTrophy {
  id: number;
  name: string;
  detail: string;
  type: TrophyType;
  hidden: boolean;
  groupId: string;
}

export interface GuideGame {
  npCommunicationId: string;
  name: string;
  platform: string;
  trophySetVersion?: string;
  trophies: GuideTrophy[];
}

export interface GuideRequest {
  protocol: number;
  language: Language;
  refresh: boolean;
  game: GuideGame;
}

const NP_COMMUNICATION_ID = /^NPWR\d{5}_\d{2}$/;

export const isValidGameId = (value: string | null | undefined): value is string => typeof value === "string" && NP_COMMUNICATION_ID.test(value);

const shortString = (value: unknown, max: number): value is string => typeof value === "string" && value.length <= max;

function parseTrophy(value: unknown): GuideTrophy {
  if (!isObject(value)) throw new ValidationError("trophy");
  const { id, name, detail, type, hidden, groupId } = value;
  if (typeof id !== "number" || !Number.isInteger(id) || id < 0 || id > 9999) throw new ValidationError("trophy_id");
  if (!shortString(name, LIMITS.trophyNameChars) || name.trim() === "") throw new ValidationError("trophy_name");
  if (detail !== undefined && detail !== null && !shortString(detail, LIMITS.trophyDetailChars)) throw new ValidationError("trophy_detail");
  if (!TROPHY_TYPES.includes(type as TrophyType)) throw new ValidationError("trophy_type");
  if (hidden !== undefined && typeof hidden !== "boolean") throw new ValidationError("trophy_hidden");
  if (groupId !== undefined && (typeof groupId !== "string" || !/^[A-Za-z0-9_-]{1,16}$/.test(groupId))) throw new ValidationError("trophy_group");
  return {
    id,
    name: name.trim(),
    detail: typeof detail === "string" ? detail.trim() : "",
    type: type as TrophyType,
    hidden: hidden === true,
    groupId: typeof groupId === "string" ? groupId : "default",
  };
}

export function parseGuideRequest(raw: string): GuideRequest {
  const body = parseJSON(raw);
  const language = resolveLanguage(body.language);
  if (!language) throw new ValidationError("language");
  if (body.refresh !== undefined && typeof body.refresh !== "boolean") throw new ValidationError("refresh");
  const game = body.game;
  if (!isObject(game)) throw new ValidationError("game");
  const { npCommunicationId, name, platform, trophySetVersion, trophies } = game;
  if (typeof npCommunicationId !== "string" || !isValidGameId(npCommunicationId)) throw new ValidationError("game_id");
  if (!shortString(name, LIMITS.gameNameChars) || name.trim() === "") throw new ValidationError("game_name");
  if (platform !== undefined && !shortString(platform, 32)) throw new ValidationError("platform");
  if (trophySetVersion !== undefined && trophySetVersion !== null && !shortString(trophySetVersion, 16)) throw new ValidationError("trophy_set_version");
  if (!Array.isArray(trophies) || trophies.length === 0 || trophies.length > LIMITS.guideTrophies) throw new ValidationError("trophies");
  const parsed = trophies.map(parseTrophy);
  if (new Set(parsed.map((t) => t.id)).size !== parsed.length) throw new ValidationError("trophy_duplicate");
  return {
    protocol: PROTOCOL_VERSION,
    language,
    refresh: body.refresh === true,
    game: {
      npCommunicationId,
      name: name.trim(),
      platform: typeof platform === "string" && platform ? platform : "PS5",
      ...(typeof trophySetVersion === "string" ? { trophySetVersion } : {}),
      trophies: parsed,
    },
  };
}
