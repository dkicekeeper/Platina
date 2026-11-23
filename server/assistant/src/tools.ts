import type Anthropic from "@anthropic-ai/sdk";

// The tools Claude can call in the chat (docs/assistant.md §5). The phone executes every one of
// them over its own database (AssistantToolkit in the app) and returns the result as JSON text
// in a tool_result; this server only describes them. Names and input shapes are the contract
// with the app: a change needs the matching change in the app and, when it is not backwards
// compatible, a bump of PROTOCOL_VERSION.
//
// Order is fixed: the tool list is part of the cached prompt prefix, and a thinking block is
// bound to it (src/claude.ts).
//
// Not `strict`: optional fields stay optional (strict mode would make the model send null for
// each), and the app decodes and checks every input itself. Not `eager_input_streaming`: the
// inputs are a few fields, nothing would arrive sooner, and the API's own validation of each
// field is kept.

type Tool = Anthropic.Beta.BetaTool;
type Schema = Tool["input_schema"];

function object(properties: Record<string, unknown>, required: string[] = []): Schema {
  return { type: "object", properties, required, additionalProperties: false } as Schema;
}

const gameId = {
  type: "string",
  description: "The game's id: its npCommunicationId, like NPWR28536_00, from list_games, get_current_session or <app_context>",
} as const;
const trophyId = {
  type: "integer",
  description: "A trophy's id within its game (PSN trophyId; the platinum is usually 0), from list_trophies or get_guide",
} as const;
const limit = (fallback: number, max: number) => ({ type: "integer", description: `How many, 1 to ${max}; ${fallback} by default` }) as const;

export const PHONE_TOOLS: Tool[] = [
  {
    name: "get_profile",
    description:
      "The person's PlayStation profile as the app knows it: online id, trophy level and progress to the next level, platinums, trophies earned by type (platinum, gold, silver, bronze), games with trophies and total play time. Call it for questions about them as a trophy hunter: their level, how many platinums, their totals.",
    input_schema: object({}),
  },
  {
    name: "list_games",
    description:
      "The person's games, most recently played first: id, name, progress %, trophies earned and in total by type, play time, the person's status (chasing, later, skip, none), whether the platinum is earned, and whether a guide is built (with its difficulty and hours when it is). filter: in_progress (started, platinum not earned yet), chasing (marked as going for the platinum), platinum (platinum earned), not_started (no trophy yet), shelved (marked later or skip), all (the default). Call it to suggest what to play next, to compare games, or to find a game's id by its name.",
    input_schema: object({
      filter: { type: "string", enum: ["in_progress", "chasing", "platinum", "not_started", "shelved", "all"] },
      limit: limit(20, 50),
    }),
  },
  {
    name: "get_game",
    description:
      "One game: name, platform, progress %, trophies earned and in total by type, trophy groups (the base game and each DLC, with their counts), play time, first and last played, the person's status, the last session, the guide's summary when a guide is built (difficulty, hours, playthroughs, online, missable and glitched trophies), and the walkthrough's current chapter when a walkthrough is built.",
    input_schema: object({ game_id: gameId }, ["game_id"]),
  },
  {
    name: "list_trophies",
    description:
      "Trophies of one game: id, name, description, type, group, PSN rarity %, earned or not and when, progress of counter trophies (37 of 50), the person's note, and whether the guide marks it missable. A hidden trophy the person has not earned comes without its name and description unless include_hidden_details is true: set it only when the person asks about a hidden trophy or says spoilers are fine. filter: unearned, earned or all (the default). type and group_id narrow the list (group default is the base game, 001 and on are DLC).",
    input_schema: object(
      {
        game_id: gameId,
        filter: { type: "string", enum: ["unearned", "earned", "all"] },
        type: { type: "string", enum: ["platinum", "gold", "silver", "bronze"] },
        group_id: { type: "string", description: "A trophy group id from get_game: default, 001, 002..." },
        include_hidden_details: { type: "boolean", description: "Names and descriptions of hidden trophies too; false by default" },
        limit: limit(50, 200),
      },
      ["game_id"],
    ),
  },
  {
    name: "get_guide",
    description:
      "The trophy guide of one game, built from Stratege.ru players' tips and web guides: summary (difficulty 1 to 10, hours, playthroughs, online, missable and glitched trophies, whether the difficulty setting matters, an overview), roadmap steps with their trophy ids, the missable trophies with when to get them, tips per trophy, and sources with links. When the game has no guide yet the app builds one first, which can take a minute. Call it before advising on a game's platinum, its roadmap or its missable trophies.",
    input_schema: object({ game_id: gameId }, ["game_id"]),
  },
  {
    name: "get_game_help",
    description:
      "PlayStation's own Game Help for a PS5 game's trophies: Sony's official hints, the ones the console and the PlayStation App show, in steps of words and usually a video. Without trophy_ids: which trophies of the game have help (id, name, hidden, earned). With trophy_ids (1 to 5 of those): each trophy's steps (title, text, has_video). The video plays on the trophy's screen in the app, so tell the person it is there instead of describing it. Call it when the person is stuck on a trophy or asks how to get one, together with the guide; say it is PlayStation's hint. A hidden trophy's help spoils it: ask for it only when the person asks about that trophy.",
    input_schema: object(
      {
        game_id: gameId,
        trophy_ids: { type: "array", items: trophyId, description: "1 to 5 trophy ids of this game that have help; leave out to list them" },
      },
      ["game_id"],
    ),
  },
  {
    name: "get_walkthrough",
    description:
      "The game's walkthrough plan, for leading the person through it chapter by chapter: an overview of the route to the platinum, the number of playthroughs, the chapters in order (id, title, a summary without spoilers, its state for this person: done, current or ahead, what can be missed there with the trophy and whether it is earned, choices that matter for trophies, collectibles with counts, the trophies earned there), the current chapter, what is left for the cleanup, and the sources. Where the person is comes from their trophies and their own marks. When the game has no walkthrough yet the app builds one first, which takes a minute or two: call it when the person wants to be led through the game, or at a session's start when a walkthrough exists or they agreed to one.",
    input_schema: object({ game_id: gameId }, ["game_id"]),
  },
  {
    name: "get_chapter",
    description:
      "One chapter's steps in the order of play, from the walkthrough: each step's id (s1, s2...), kind (path: where to go; collectible; choice: a decision that matters for a trophy; point_of_no_return; trophy; boss; tip), text, done or not (ticked, its trophies earned, or the chapter behind), the trophies it earns, the collectible's number, whether it has a picture or a video the app can show, and spoiler: true for a step that reveals the story or a hidden trophy (don't tell it unless the person asks). Also the chapter's next step not done. chapter_id defaults to the current chapter. The first time a chapter is asked for, the app builds its steps, which takes a minute.",
    input_schema: object(
      {
        game_id: gameId,
        chapter_id: { type: "string", description: "A chapter id from get_walkthrough: c1, c2...; the current chapter by default" },
      },
      ["game_id"],
    ),
  },
  {
    name: "set_walkthrough_progress",
    description:
      "Marks the person's progress in the walkthrough when they tell you: steps done (or not done after all), a chapter done, or the chapter they are on now (current: true; it also works for going back to replay one). Returns the new current chapter and its next step. Only for what the person said they did; the app works the rest out from trophies.",
    input_schema: object(
      {
        game_id: gameId,
        chapter_id: { type: "string", description: "The chapter these marks belong to: c1, c2..." },
        done_step_ids: { type: "array", items: { type: "string" }, description: "Step ids of this chapter now done: s1, s2..." },
        undone_step_ids: { type: "array", items: { type: "string" }, description: "Step ids to mark as not done" },
        chapter_done: { type: "boolean", description: "true: the chapter is finished; false: it isn't after all" },
        current: { type: "boolean", description: "true: the person is on this chapter now" },
      },
      ["game_id", "chapter_id"],
    ),
  },
  {
    name: "get_sessions",
    description:
      "The person's past play sessions, newest first: id, game, date, length (by the timer and by PSN play time), trophies earned, the goals and whether they were met, and the summary and next steps saved at the end. Leave game_id out for every game. Call it to recall where they stopped last time.",
    input_schema: object({ game_id: gameId, limit: limit(5, 20) }),
  },
  {
    name: "get_current_session",
    description:
      "The play session in progress, if any: its id, game, start time, elapsed time, goals and which are done, trophies earned during it, and the person's 'where I stopped' note. Returns {\"session\": null} when no session is running.",
    input_schema: object({}),
  },
  {
    name: "set_session_goals",
    description:
      "Sets the goals of the current session of this game, or of its next session when none is running: the trophies to aim for today (1 to 6 ids from list_trophies or get_guide, ones not earned yet) and an optional short note for a goal that is not one trophy (a roadmap step, a collectibles run). Replaces the previous goals. The app checks each goal off when its trophy pops. Use it when planning a session.",
    input_schema: object(
      {
        game_id: gameId,
        trophy_ids: { type: "array", items: trophyId, description: "1 to 6 trophy ids of this game" },
        note: { type: "string", description: "A goal in words, in the person's language, one line" },
      },
      ["game_id", "trophy_ids"],
    ),
  },
  {
    name: "set_game_status",
    description:
      "Sets the person's status for a game: chasing (going for the platinum), later (put off for now), skip (won't do it), none (clear the status). Only when the person says so.",
    input_schema: object(
      {
        game_id: gameId,
        status: { type: "string", enum: ["chasing", "later", "skip", "none"] },
      },
      ["game_id", "status"],
    ),
  },
  {
    name: "save_note",
    description:
      "Saves a note to a game, or to one of its trophies with trophy_id: what the person asked to remember (where they stopped, a code, a reminder), in their words or a short summary in their language. It is added to the existing note. Only when the person asks to remember something.",
    input_schema: object(
      {
        game_id: gameId,
        trophy_id: trophyId,
        text: { type: "string", description: "The note, in the person's language" },
      },
      ["game_id", "text"],
    ),
  },
  {
    name: "save_session_summary",
    description:
      "Saves the summary of a finished session to the game's journal, where the next session starts from: summary (2 to 4 sentences: what was done, the trophies earned) and next_steps (what to do next time, a short Markdown list). Both in the person's language. session_id comes from the session-end message or get_current_session.",
    input_schema: object(
      {
        session_id: { type: "string", description: "The finished session's id" },
        summary: { type: "string" },
        next_steps: { type: "string", description: "A short Markdown list" },
      },
      ["session_id", "summary", "next_steps"],
    ),
  },
];

/** Every phone tool a history may hold. */
export const TOOL_NAMES: ReadonlySet<string> = new Set(PHONE_TOOLS.map((t) => t.name));

/** The server-side tools a history may hold: web search, and the code its newer version runs to
 * filter results on the models that have it. */
export const SERVER_TOOL_NAMES: ReadonlySet<string> = new Set(["web_search", "code_execution", "bash_code_execution", "text_editor_code_execution"]);

/** Models whose web search filters its results with code before they reach the context
 * (web_search_20260209). The others, Claude Haiku 5.5 among them, take web_search_20250305. */
const DYNAMIC_FILTERING_MODELS = new Set([
  "claude-fable-5-2",
  "claude-fable-5-1",
  "claude-fable-5",
  "claude-opus-5-5",
  "claude-opus-5",
  "claude-opus-4-8",
  "claude-opus-4-7",
  "claude-opus-4-6",
  "claude-sonnet-5-5",
  "claude-sonnet-5",
  "claude-sonnet-4-6",
]);

export function webSearchTool(model: string, maxUses: number, allowedDomains?: string[]): Anthropic.Beta.BetaToolUnion {
  const domains = allowedDomains?.length ? { allowed_domains: allowedDomains } : {};
  return DYNAMIC_FILTERING_MODELS.has(model)
    ? { type: "web_search_20260209", name: "web_search", max_uses: maxUses, ...domains }
    : { type: "web_search_20250305", name: "web_search", max_uses: maxUses, ...domains };
}

/** Web fetch: reads a page whose address is already in the conversation (a search result, the
 * request, an earlier page). Same model split as web search. */
export function webFetchTool(model: string, maxUses: number, allowedDomains?: string[], maxContentTokens = 20000): Anthropic.Beta.BetaToolUnion {
  const options = { max_uses: maxUses, max_content_tokens: maxContentTokens, ...(allowedDomains?.length ? { allowed_domains: allowedDomains } : {}) };
  return DYNAMIC_FILTERING_MODELS.has(model)
    ? { type: "web_fetch_20260209", name: "web_fetch", ...options }
    : { type: "web_fetch_20250910", name: "web_fetch", ...options };
}

/** The chat's tools: the phone's, then web search when it is on. */
export function chatTools(config: { model: string; webSearch: boolean; webSearchMaxUses: number }): Anthropic.Beta.BetaToolUnion[] {
  return config.webSearch ? [...PHONE_TOOLS, webSearchTool(config.model, config.webSearchMaxUses)] : PHONE_TOOLS;
}
