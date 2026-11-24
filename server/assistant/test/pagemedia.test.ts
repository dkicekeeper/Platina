import { describe, expect, it } from "vitest";
import { extractPageMedia, fetchPageMedia } from "../src/pagemedia";

const SITES = ["powerpyx.com", "psnprofiles.com"];
const PAGE = "https://www.powerpyx.com/test-game-chapter-1-collectible-locations/";

// A page laid out like PowerPyx's collectible guides: the site's chrome, then the article with
// a heading, a paragraph and a screenshot per collectible, a YouTube embed, pictures from
// elsewhere.
const html = `<!doctype html><html><head><title>Test Game Chapter 1 Collectible Locations &amp; Guide</title></head><body>
<header><img src="https://www.powerpyx.com/wp-content/uploads/powerpyx-header.png" alt="PowerPyx"></header>
<article class="post"><div class="entry-content">
<p>This guide shows every collectible of Chapter 1.</p>
<iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ?feature=oembed" width="640"></iframe>
<h3>Record #1: Old Song</h3>
<p>Behind the crates to the left of the first bridge.</p>
<p><img src="https://www.powerpyx.com/wp-content/uploads/test-game-record-1-300x169.jpg" srcset="https://www.powerpyx.com/wp-content/uploads/test-game-record-1-300x169.jpg 300w, https://www.powerpyx.com/wp-content/uploads/test-game-record-1.jpg 1280w" width="1280" alt="Record 1 location"></p>
<h3>Record #2: Lullaby</h3>
<p>On the desk in the locked office; the key is in the hall.</p>
<p><img data-src="/wp-content/uploads/test-game-record-2.jpg" src="data:image/gif;base64,R0lG" alt=""></p>
<p><img src="https://cdn.example.com/ad-banner.jpg" alt="ad"></p>
<p><img src="https://www.powerpyx.com/wp-content/uploads/tiny-arrow.png" width="24"></p>
<p><img src="http://www.powerpyx.com/wp-content/uploads/insecure.jpg"></p>
</div></article></body></html>`;

describe("extractPageMedia", () => {
  it("keeps the article's pictures with the text before them, and the YouTube embed", () => {
    const media = extractPageMedia(html, PAGE, SITES);
    expect(media.title).toBe("Test Game Chapter 1 Collectible Locations & Guide");
    expect(media.images.map((i) => i.url)).toEqual([
      "https://www.powerpyx.com/wp-content/uploads/test-game-record-1.jpg",
      "https://www.powerpyx.com/wp-content/uploads/test-game-record-2.jpg",
    ]);
    expect(media.images[0]!.context).toContain("Record #1: Old Song");
    expect(media.images[0]!.context).toContain("Behind the crates");
    expect(media.images[0]!.context).toContain("[Record 1 location]");
    expect(media.images[1]!.context).toContain("locked office");
    expect(media.images[1]!.context).not.toContain("Old Song");
    expect(media.videos).toEqual([{ youtubeId: "dQw4w9WgXcQ", context: "This guide shows every collectible of Chapter 1." }]);
  });

  it("reads a page over the network, and gives nothing for a page that fails", async () => {
    const ok = await fetchPageMedia(PAGE, SITES, async () => new Response(html, { status: 200 }));
    expect(ok?.images).toHaveLength(2);
    expect(await fetchPageMedia(PAGE, SITES, async () => new Response("no", { status: 403 }))).toBeUndefined();
    expect(
      await fetchPageMedia(PAGE, SITES, async () => {
        throw new Error("offline");
      }),
    ).toBeUndefined();
  });
});
