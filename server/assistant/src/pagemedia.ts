import { decodeEntities, htmlToText, USER_AGENT } from "./stratege";

// The pictures and videos of a guide page, for a walkthrough chapter's steps. web_fetch gives the
// model a page's text without its pictures (only the logo and the header survive), so the server
// reads the page's HTML itself, the way it reads Stratege's, and keeps each picture with the text
// right before it on the page: "Record #3: behind the crates…" and then the screenshot of it.
// Only sites in IMAGE_SOURCES, only https; the app loads the pictures from the site.

export interface PageImage {
  url: string;
  /** The text before the picture on the page (its heading or paragraph), and its alt text. */
  context: string;
}

export interface PageVideo {
  youtubeId: string;
  context: string;
}

export interface PageMedia {
  pageUrl: string;
  title: string;
  images: PageImage[];
  videos: PageVideo[];
}

/** Pictures that are the site's own chrome, not a spot in the game: by the file's name (not the
 * path: WordPress keeps everything under /uploads/). */
const CHROME = /(favicon|logo|header|avatar|gravatar|wallpaper|banner|sprite|emoji|icon[-_.]|placeholder|blank\.|spinner|(^|[-_.])ads?([-_.]|$))/i;
const IMAGE_FILE = /\.(jpe?g|png|webp|gif)(\?|$)/i;
const YOUTUBE_ID = /(?:youtube(?:-nocookie)?\.com\/(?:embed\/|watch\?v=)|youtu\.be\/)([A-Za-z0-9_-]{11})/;
const MAX_IMAGES = 80;
const CONTEXT_CHARS = 240;

const attribute = (tag: string, name: string) => {
  const match = new RegExp(`\\s${name}\\s*=\\s*("([^"]*)"|'([^']*)')`, "i").exec(tag);
  return match ? decodeEntities(match[2] ?? match[3] ?? "") : undefined;
};

/** The largest picture of a srcset ("a.jpg 300w, b.jpg 1024w" → b.jpg). */
function largest(srcset: string | undefined): string | undefined {
  if (!srcset) return undefined;
  let best: { url: string; width: number } | undefined;
  for (const part of srcset.split(",")) {
    const [url, size] = part.trim().split(/\s+/);
    const width = Number.parseInt(size ?? "0", 10) || 0;
    if (url && (!best || width > best.width)) best = { url, width };
  }
  return best?.url;
}

const hostIn = (url: URL, sites: string[]) => {
  const host = url.hostname.toLowerCase().replace(/^www\./, "");
  return sites.some((site) => host === site || host.endsWith(`.${site}`));
};

/** The text between the previous picture (or video) and this one, as plain text: its heading
 * and paragraph, the end of them when long. */
function textBefore(html: string, from: number, index: number): string {
  let chunk = html.slice(Math.max(from, index - 2500), index);
  const firstClose = chunk.indexOf(">");
  const firstOpen = chunk.indexOf("<");
  // Starts inside a tag: drop the tag's tail.
  if (firstClose >= 0 && (firstOpen < 0 || firstClose < firstOpen)) chunk = chunk.slice(firstClose + 1);
  const text = htmlToText(chunk).replace(/\s+/g, " ").trim();
  return text.slice(-CONTEXT_CHARS);
}

/** A page's pictures and YouTube videos, in the page's order, each with the text before it. */
export function extractPageMedia(html: string, pageUrl: string, sites: string[]): PageMedia {
  const title = decodeEntities(/<title[^>]*>([\s\S]*?)<\/title>/i.exec(html)?.[1] ?? "").replace(/\s+/g, " ").trim().slice(0, 160);
  // The article, when the page marks it: less of the site around it.
  const articleStart = html.search(/<article\b|class="[^"]*entry-content/i);
  const body = articleStart > 0 ? html.slice(articleStart) : html;
  const images: PageImage[] = [];
  const videos: PageVideo[] = [];
  const seenImages = new Set<string>();
  const seenVideos = new Set<string>();
  let previousEnd = 0;
  for (const match of body.matchAll(/<img\b[^>]*>|<iframe\b[^>]*>|<lite-youtube\b[^>]*>/gi)) {
    const tag = match[0];
    const index = match.index ?? 0;
    const from = previousEnd;
    previousEnd = index + tag.length;
    if (/^<img/i.test(tag)) {
      const raw = largest(attribute(tag, "data-srcset")) ?? attribute(tag, "data-src") ?? attribute(tag, "data-lazy-src") ?? largest(attribute(tag, "srcset")) ?? attribute(tag, "src");
      if (!raw || raw.startsWith("data:")) continue;
      let url: URL;
      try {
        url = new URL(raw, pageUrl);
      } catch {
        continue;
      }
      const file = url.pathname.split("/").pop() ?? "";
      if (url.protocol !== "https:" || !hostIn(url, sites) || !IMAGE_FILE.test(url.pathname) || CHROME.test(file)) continue;
      const width = Number.parseInt(attribute(tag, "width") ?? "", 10);
      if (Number.isFinite(width) && width > 0 && width < 200) continue;
      const href = url.toString();
      if (seenImages.has(href)) continue;
      seenImages.add(href);
      const alt = attribute(tag, "alt")?.trim();
      const before = textBefore(body, from, index);
      images.push({ url: href, context: alt && !before.includes(alt) ? `${before} [${alt}]`.trim() : before });
      if (images.length >= MAX_IMAGES) break;
    } else {
      const source = attribute(tag, "src") ?? attribute(tag, "data-src") ?? "";
      const id = YOUTUBE_ID.exec(source)?.[1] ?? attribute(tag, "videoid");
      if (!id || !/^[A-Za-z0-9_-]{11}$/.test(id) || seenVideos.has(id)) continue;
      seenVideos.add(id);
      videos.push({ youtubeId: id, context: textBefore(body, from, index) });
    }
  }
  return { pageUrl, title, images, videos };
}

/** Reads a guide page and gives its pictures and videos; undefined when the page doesn't load. */
export async function fetchPageMedia(pageUrl: string, sites: string[], fetcher: typeof fetch, timeoutMs = 15_000): Promise<PageMedia | undefined> {
  try {
    const response = await fetcher(pageUrl, {
      headers: { "user-agent": USER_AGENT, accept: "text/html", "accept-language": "en;q=0.8,ru;q=0.5" },
      redirect: "follow",
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!response.ok) {
      await response.body?.cancel().catch(() => undefined);
      return undefined;
    }
    const html = await response.text();
    if (html.length > 6_000_000) return undefined;
    return extractPageMedia(html, response.url || pageUrl, sites);
  } catch {
    return undefined;
  }
}
