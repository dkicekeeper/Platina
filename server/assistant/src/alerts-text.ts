// What a trophy notification says (docs/assistant.md §9), in the person's language: every
// trophy of one check in one notification per game, the platinum always on its own.

import type { PushContent } from "./apns";
import type { EarnedTrophy, TrophyType } from "./sony";

export type AlertLanguage = "ru" | "en";

const TYPE_NAMES: Record<AlertLanguage, Record<TrophyType, string>> = {
  ru: { bronze: "Бронза", silver: "Серебро", gold: "Золото", platinum: "Платина" },
  en: { bronze: "Bronze", silver: "Silver", gold: "Gold", platinum: "Platinum" },
};

const RANK: Record<TrophyType, number> = { platinum: 0, gold: 1, silver: 2, bronze: 3 };

/** "1 трофей", "3 трофея", "5 трофеев", "21 трофей". */
export function ruTrophies(count: number): string {
  const tens = count % 100;
  const ones = count % 10;
  const word = tens >= 11 && tens <= 14 ? "трофеев" : ones === 1 ? "трофей" : ones >= 2 && ones <= 4 ? "трофея" : "трофеев";
  return `${count} ${word}`;
}

const label = (language: AlertLanguage, trophy: EarnedTrophy) =>
  trophy.name ? `${TYPE_NAMES[language][trophy.type]} · ${trophy.name}` : TYPE_NAMES[language][trophy.type];

/** At most this many trophies by name in a grouped notification; the rest are counted. */
const LISTED = 4;

/** The notifications for the trophies one check found in one game. */
export function trophyAlerts(language: AlertLanguage, game: { id: string; name: string }, trophies: EarnedTrophy[]): PushContent[] {
  const data = (list: EarnedTrophy[]) => ({ gameId: game.id, trophyIds: list.map((trophy) => trophy.id) });
  const alerts: PushContent[] = [];
  const others = trophies.filter((trophy) => trophy.type !== "platinum").sort((a, b) => RANK[a.type] - RANK[b.type]);
  if (others.length === 1) {
    alerts.push({ title: `🏆 ${label(language, others[0]!)}`, body: game.name, threadId: game.id, data: data(others) });
  } else if (others.length > 1) {
    const listed = others.slice(0, LISTED).map((trophy) => label(language, trophy));
    const rest = others.length - listed.length;
    const more = rest > 0 ? (language === "ru" ? ` и ещё ${rest}` : ` and ${rest} more`) : "";
    const count = language === "ru" ? ruTrophies(others.length) : `${others.length} trophies`;
    alerts.push({ title: `🏆 ${count} · ${game.name}`, body: listed.join(", ") + more, threadId: game.id, data: data(others) });
  }
  for (const platinum of trophies.filter((trophy) => trophy.type === "platinum")) {
    alerts.push({
      title: `🏆 ${TYPE_NAMES[language].platinum} · ${game.name}`,
      body: platinum.name || (language === "ru" ? "Все трофеи игры получены" : "Every trophy of the game earned"),
      threadId: game.id,
      data: { ...data([platinum]), platinum: true },
    });
  }
  return alerts;
}

/** The one notification when Sony stops accepting the server's grant: the watcher stops. */
export function signInAgainAlert(language: AlertLanguage): PushContent {
  return language === "ru"
    ? { title: "Уведомления о трофеях на паузе", body: "Войдите в PSN снова в Platina, чтобы получать их дальше.", threadId: "account", data: { signIn: true } }
    : { title: "Trophy notifications paused", body: "Sign in to PSN again in Platina to keep getting them.", threadId: "account", data: { signIn: true } };
}
