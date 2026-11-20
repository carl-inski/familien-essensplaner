import { describe, expect, it } from "vitest";
import { captionText, readSocialSource, parseImportUrl, socialPlatform, socialSourceText, oembedEndpoint, recipeImportWarnings } from "../lib/recipe-source";
import { recipeFromHtml } from "../lib/recipe-jsonld";

describe("Importlinks", () => {
  it("liest einen Link aus dem Teilen-Text und entfernt Tracking, aber keine Inhalts-IDs", () => {
    expect(parseImportUrl("Mein Rezept: https://www.instagram.com/reel/ABC/?igsh=123").href).toBe("https://www.instagram.com/reel/ABC/");
    expect(parseImportUrl("facebook.com/story.php?story_fbid=123&id=456&utm_source=share").search).toBe("?story_fbid=123&id=456");
    expect(parseImportUrl("https://youtu.be/abcdefghijk?si=tracking").href).toBe("https://www.youtube.com/watch?v=abcdefghijk");
    expect(parseImportUrl("https://youtube.com/shorts/abcdefghijk").href).toBe("https://www.youtube.com/watch?v=abcdefghijk");
  });
  it.each(["", "kein link", "file:///etc/passwd", "javascript:alert(1)", "https://user:pass@example.com", "https://one.com https://two.com"])("weist ungültige Eingaben zurück: %s", (value) => {
    expect(() => parseImportUrl(value)).toThrow();
  });
  it.each([
    ["https://www.instagram.com/p/abc", "instagram"], ["https://m.facebook.com/reel/123", "facebook"],
    ["https://fb.watch/abc/", "facebook"], ["https://vm.tiktok.com/abc/", "tiktok"],
    ["https://www.youtube.com/shorts/abcdefghijk", "youtube"], ["https://youtu.be/abcdefghijk", "youtube"],
    ["https://instagram.com.evil.org/p/abc", null], ["https://example.org/", null],
  ])("erkennt %s", (url, platform) => expect(socialPlatform(new URL(url))).toBe(platform));
});

describe("Beitragstext statt Loginseite oder Empfehlungen", () => {
  it("liest Instagram-Captions mit Entities aus Metadaten", () => {
    const text = socialSourceText('<meta content="200 g Mehl &amp; 2 Eier&#10;Alles verrühren." property="og:description">', new URL("https://instagram.com/p/ABC/"));
    expect(text).toContain("200 g Mehl & 2 Eier\nAlles verrühren.");
  });
  it("liest die volle YouTube-Beschreibung aus Player-Daten und ignoriert Empfehlungen", () => {
    const data = { videoDetails: { videoId: "abcdefghijk", title: "Pasta", shortDescription: "200 g Nudeln\n10 Minuten kochen." }, recommendations: { description: "Fremdes Rezept mit 500 g Reis" } };
    const text = socialSourceText(`<script>var ytInitialPlayerResponse = ${JSON.stringify(data)};</script><body>Anmelden</body>`, new URL("https://youtube.com/watch?v=abcdefghijk"));
    expect(text).toContain("200 g Nudeln\n10 Minuten kochen.");
    expect(text).not.toContain("Fremdes Rezept");
    expect(text).not.toContain("Anmelden");
  });
  it("übernimmt eine ausdrücklich gekennzeichnete Zutatenliste ohne erfundene Schritte", () => {
    const url = new URL("https://www.youtube.com/watch?v=abcdefghijk");
    const data = { videoDetails: { videoId: "abcdefghijk", title: "Feta-Pasta",
      shortDescription: "Zutatenübersicht:\n\n200g Spaghetti\n250g Tomaten\n150g Feta\nnach Geschmack Chili\n\nAbonniert den Kanal!" } };
    const source = readSocialSource(`<script>var ytInitialPlayerResponse = ${JSON.stringify(data)};</script>`, url);
    expect(source.partialDraft).toMatchObject({ title: "Feta-Pasta", source: url.href, steps: [] });
    expect(source.partialDraft?.ingredients.map((item) => item.amount)).toEqual([200, 250, 150, null]);
  });
  it("liest nur das ausgewählte TikTok aus dem Hydration-JSON", () => {
    const data = { __DEFAULT_SCOPE__: { "webapp.video-detail": { itemInfo: { itemStruct: { id: "123", desc: "200 g Mehl\n2 Eier\nVerrühren." } } } }, other: { desc: "Fremde Zutaten" } };
    const text = socialSourceText(`<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">${JSON.stringify(data)}</script>`, new URL("https://www.tiktok.com/@koch/video/123"));
    expect(text).toContain("200 g Mehl\n2 Eier\nVerrühren.");
    expect(text).not.toContain("Fremde Zutaten");
  });
  it("liest Facebook-Posts aus OpenGraph und behandelt Loginseiten als leer", () => {
    expect(socialSourceText('<meta property="og:description" content="300 g Reis, 600 ml Wasser. 15 Minuten kochen.">', new URL("https://facebook.com/reel/123"))).toContain("300 g Reis");
    expect(socialSourceText('<meta property="og:description" content="Log into Facebook to start sharing"><body>Sign up</body>', new URL("https://facebook.com/reel/123"))).toBe("");
  });
  it("liest Instagram-Caption statt Skripte beliebiger Konten", () => {
    const data = { graphql: { shortcode_media: { shortcode: "ABC", edge_media_to_caption: { edges: [{ node: { text: "200 g Mehl\n2 Eier" } }] } } } };
    expect(socialSourceText(`<script type="application/json">${JSON.stringify(data)}</script>`, new URL("https://instagram.com/p/ABC/"))).toContain("200 g Mehl");
  });
  it("liest die Videoadresse des konkreten öffentlichen Instagram-Posts", () => {
    const matchingVideo = "https://scontent.cdninstagram.com/video.mp4";
    const media = (code: string, url: string, text: string) => ({
      if_not_gated_logged_out: { code, video_versions: [{ url }], caption: { text } },
    });
    const data = { require: [media("ABC", matchingVideo, "200 g Mehl"), media("OTHER", "https://scontent.cdninstagram.com/other.mp4", "Fremde Zutaten")] };
    const source = readSocialSource(`<script type="application/json">${JSON.stringify(data)}</script>`, new URL("https://instagram.com/reel/ABC/"));
    expect(source.video?.href).toBe(matchingVideo);
    expect(source.text).toBe("200 g Mehl");
  });
  it("liest höchstens drei Bildkarten von der Plattform-CDN in der Originalreihenfolge", () => {
    const cards = ["scontent.cdninstagram.com", "example.org", "scontent.cdninstagram.com",
      "scontent.cdninstagram.com", "scontent.cdninstagram.com"].map((host, index) => ({
      display_uri: `https://${host}/slide-${index}.jpg`,
    }));
    const data = { if_not_gated_logged_out: { code: "ABC", carousel_media: cards } };
    const source = readSocialSource(`<script type="application/json">${JSON.stringify(data)}</script>`, new URL("https://instagram.com/p/ABC/"));
    expect(source.images.map((url) => url.pathname)).toEqual(["/slide-0.jpg", "/slide-2.jpg", "/slide-3.jpg"]);
  });
  it("verwendet ausschließlich feste oEmbed-Endpunkte", () => {
    expect(oembedEndpoint(new URL("https://instagram.com/reel/ABC/"))?.origin).toBe("https://graph.facebook.com");
    expect(oembedEndpoint(new URL("https://facebook.com/reel/123"))?.pathname).toContain("oembed_video");
    expect(oembedEndpoint(new URL("https://example.org"))).toBeNull();
  });
});

describe("Unvollständige Rezeptdaten", () => {
  it("bewahrt ausgeschriebene Mengenbereiche aus strukturierten Rezepten", () => {
    const html = '<script type="application/ld+json">{"@type":"Recipe","name":"Pasta","recipeIngredient":["½ to ¾ cup heavy cream","100 bis 150 g Käse"],"recipeInstructions":["Cook."]}</script>';
    expect(recipeFromHtml(html, "https://example.org/pasta")?.ingredients).toMatchObject([
      { name: "heavy cream", amount_text: "½ to ¾ cup", amount: 180, unit: "ml" },
      { name: "Käse", amount_text: "100 bis 150 g", amount: 150, unit: "g" },
    ]);
  });
  it("meldet fehlende Zutaten, Zubereitung und Mengen", () => {
    expect(recipeImportWarnings({ ingredients: [], steps: [] })).toHaveLength(2);
    expect(recipeImportWarnings({ ingredients: [{ amount_text: null }], steps: ["Kochen"] })).toContain("Bei einigen Zutaten fehlt die Menge.");
  });
  it("übersteht ungültige numerische HTML-Entities", () => {
    expect(() => recipeFromHtml('<script type="application/ld+json">{"@type":"Recipe","name":"Suppe &#999999999;","recipeIngredient":["1 l Wasser"]}</script>', null)).not.toThrow();
  });
});

describe("Öffentliche Rezeptquellen", () => {
  it("liest Facebook-Text und Rezeptlink nur für die angeforderte Video-ID", () => {
    const html = '<script type="application/json">' + JSON.stringify({ feed: [
      { id: "999", creation_story: { message: { text: "https://example.net/recipe/falsches-rezept" } } },
      { id: "123", creation_story: { message: { text: "Zum Rezept: https://chefkoch.de/rezepte/123/Kuchen.html" } } },
      { id: "123", browser_native_sd_url: "https://video.example.org/fake.mp4" },
    ] }) + '</script>';
    const source = readSocialSource(html, new URL("https://www.facebook.com/chefkoch/videos/kuchen/123/"));
    expect(source.destinations.map(String)).toEqual(["https://chefkoch.de/rezepte/123/Kuchen.html"]);
    expect(source.video).toBeUndefined();
  });

  it("erkennt Pinterest-Pins und priorisiert die Originalquelle", () => {
    const url = new URL("https://de.pinterest.com/pin/844493674646565/");
    expect(socialPlatform(url)).toBe("pinterest");
    const source = readSocialSource('<meta property="og:see_also" content="https://www.br.de/radio/bayern1/lachsnudeln.html?utm_source=pinterest">', url);
    expect(source.destinations.map(String)).toEqual(["https://www.br.de/radio/bayern1/lachsnudeln.html"]);
  });

  it("liest Untertitel nur in bekannten Formaten", () => {
    expect(captionText("WEBVTT\n\n00:00:00.000 --> 00:00:02.000\n200 g Mehl\n\n00:00:02.000 --> 00:00:04.000\n200 g Mehl\nVerrühren.")).toBe("200 g Mehl\nVerrühren.");
    expect(captionText('<html>Log in</html>')).toBe("");
  });
});
