import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
vi.mock("server-only", () => ({}));
vi.mock("@/lib/ai/guard", async () => {
  const { NextResponse } = await import("next/server");
  class AiError extends Error { constructor(message: string, public status: number, public code: string) { super(message); } }
  return { AiError, aiSession: vi.fn(), aiGuard: vi.fn(), logUsage: vi.fn(), aiErrorResponse: (e: unknown) => NextResponse.json({ error: (e as Error).message }, { status: e instanceof AiError ? e.status : 502 }) };
});
vi.mock("@/lib/ai/fetch-page", async () => {
  const { parseImportUrl } = await import("../lib/recipe-source");
  return { fetchPage: vi.fn(), fetchRecipeCover: vi.fn(), parseUserUrl: parseImportUrl };
});
vi.mock("@/lib/ai/run", () => ({ aiObject: vi.fn() }));
vi.mock("@/lib/ai/social-video", () => ({ socialVideoConfig: vi.fn(), extractSocialVideo: vi.fn() }));
import { AiError, aiSession, aiGuard } from "../lib/ai/guard";
import { fetchPage, fetchRecipeCover } from "../lib/ai/fetch-page";
import { aiObject } from "../lib/ai/run";
import { extractSocialVideo, socialVideoConfig } from "../lib/ai/social-video";
import { mockRecipeExtract } from "../lib/ai/mocks";
import { POST as linkImport } from "../app/api/ai/recipe-from-url/route";
import { POST as photoImport } from "../app/api/ai/recipe-from-photo/route";
import { POST as publicSource } from "../app/api/recipe-source/route";
import { POST as recipeAssist } from "../app/api/ai/recipe-assist/route";
import { proxy } from "../proxy";

const request = (body: unknown) => new NextRequest("http://localhost/api/import", { method: "POST", body: JSON.stringify(body), headers: { "Content-Type": "application/json" } });
const jpeg = { mediaType: "image/jpeg", data: Buffer.from([255, 216, 255, 224, 1, 2, 3]).toString("base64") };
beforeEach(() => {
  vi.resetAllMocks();
  vi.mocked(aiObject).mockResolvedValue({ data: JSON.parse(mockRecipeExtract()), cached: false });
  vi.mocked(fetchPage).mockRejectedValue(new AiError("Die Seite blockiert den Abruf.", 422, "bad-request"));
});

describe("Rezeptimport API", () => {
  it("übernimmt einen ausdrücklich ergänzten Original-Rezeptlink mit seiner eigenen Quelle", async () => {
    const original = new URL("https://example.org/rezepte/karottensuppe");
    vi.mocked(fetchPage).mockResolvedValueOnce({ url: original, html: '<html lang="de"><script type="application/ld+json">{"@type":"Recipe","name":"Karottensuppe","recipeIngredient":["250 g Karotten"],"recipeInstructions":["Karotten garen."]}</script></html>' });
    const response = await linkImport(request({ url: "https://www.instagram.com/reel/ABC/", mode: "social", text: original.href }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      draft: { title: "Karottensuppe", source: original.href },
      warnings: expect.arrayContaining(["Das Rezept stammt vom ergänzten Link."]),
    });
    expect(fetchPage).toHaveBeenCalledTimes(1);
    expect(aiObject).not.toHaveBeenCalled();
  });

  it("lässt native Bearer-Anfragen bis zur geschützten Rezept-KI-Route durch", async () => {
    const native = new NextRequest("https://example.org/api/ai/recipe-assist", {
      method: "POST",
      headers: { authorization: "Bearer fixture", "Content-Type": "application/json" },
      body: JSON.stringify({ task: "price", title: "Suppe", ingredients: ["1 Karotte"], servings: 2 }),
    });
    expect((await proxy(native)).headers.get("x-middleware-next")).toBe("1");
    vi.mocked(aiGuard).mockRejectedValueOnce(new AiError("Bitte anmelden", 401, "unauthorized"));
    expect((await recipeAssist(native)).status).toBe(401);
    expect(aiObject).not.toHaveBeenCalled();
  });

  it("lehnt den Linkabruf ohne Anmeldung ab", async () => {
    vi.mocked(aiSession).mockRejectedValueOnce(new AiError("Bitte melde dich an.", 401, "unauthorized"));
    const response = await publicSource(request({ url: "https://example.org/suppe" }));
    expect(response.status).toBe(401);
    expect(fetchPage).not.toHaveBeenCalled();
  });

  it("liefert strukturierten Websiteinhalt angemeldet ohne Modellaufruf", async () => {
    const url = new URL("https://example.org/suppe");
    vi.mocked(fetchPage).mockResolvedValue({ url, html: '<html lang="de"><script type="application/ld+json">{"@type":"Recipe","name":"Suppe","recipeIngredient":["1 l Wasser"],"recipeInstructions":["Aufkochen."]}</script></html>' });
    const response = await publicSource(request({ url: url.href }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ source: url.href, needs_translation: false, draft: { title: "Suppe" } });
    expect(aiSession).toHaveBeenCalledTimes(1);
    expect(aiObject).not.toHaveBeenCalled();
  });

  it("liest die Beitragsbeschreibung aus einem öffentlichen Instagram-Embed", async () => {
    const url = new URL("https://www.instagram.com/reel/ABC/");
    vi.mocked(fetchPage)
      .mockRejectedValueOnce(new AiError("Die Seite blockiert den Abruf.", 422, "bad-request"))
      .mockResolvedValueOnce({ url: new URL(url.href + "embed/captioned/"), html: '<div class="Container"><div class="Caption">200 g Mehl und 2 Eier verrühren und backen.</div></div>' });
    const response = await publicSource(request({ url: url.href }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ source: url.href, text: "200 g Mehl und 2 Eier verrühren und backen." });
    expect(aiObject).not.toHaveBeenCalled();
  });

  it("weist übergroße Quellenanfragen vor dem Abruf ab", async () => {
    const response = await publicSource(request({ url: "x".repeat(10_000) }));
    expect(response.status).toBe(413);
    expect(fetchPage).not.toHaveBeenCalled();
  });
  it("folgt einem Teilen-Kurzlink bis zum tatsächlichen Social-Beitrag", async () => {
    const url = new URL("https://www.tiktok.com/@koch/video/123");
    vi.mocked(fetchPage).mockResolvedValueOnce({ url, html: '<meta property="og:description" content="200 g Mehl, 2 Eier. Alles verrühren und backen.">' });
    const response = await publicSource(request({ url: "https://example.org/k/123", mode: "social" }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ source: url.href, text: expect.stringContaining("200 g Mehl") });
  });
  it("liefert bei einem bebilderten Beitrag ohne Text die Rezeptkarten für die App", async () => {
    const url = new URL("https://www.instagram.com/p/ABC/");
    const image = "https://scontent.cdninstagram.com/card.jpg";
    const html = `<script type="application/json">${JSON.stringify({
      if_not_gated_logged_out: { code: "ABC", display_uri: image, carousel_media: [{ display_uri: image }] },
    })}</script>`;
    vi.mocked(fetchPage).mockResolvedValueOnce({ url, html });
    vi.mocked(fetchRecipeCover).mockResolvedValue(jpeg);
    const response = await publicSource(request({ url: url.href }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ source: url.href, post_images: [jpeg] });
    expect(fetchRecipeCover).toHaveBeenCalledTimes(1);
    expect(aiObject).not.toHaveBeenCalled();
  });

  it("kopiert das Bild des verlinkten Reels in den Entwurf", async () => {
    const url = new URL("https://instagram.com/reel/ABC/");
    const cover = new URL("https://scontent.cdninstagram.com/cover.jpg?expires=123");
    vi.mocked(fetchPage).mockResolvedValueOnce({ url, html: `<meta property="og:image" content="${cover}"><meta property="og:description" content="200 g Mehl und 2 Eier. Verrühren und backen.">` });
    vi.mocked(fetchRecipeCover).mockResolvedValueOnce(jpeg);
    const response = await linkImport(request({ url: url.href, mode: "social" }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ draft: { image_data: jpeg } });
    expect(fetchRecipeCover).toHaveBeenCalledWith(cover, "instagram", expect.any(Number));
  });

  it("holt bei einem Pinterest-Pin das vollständige Rezept von der verlinkten Seite", async () => {
    const url = new URL("https://de.pinterest.com/pin/123/");
    const source = new URL("https://example.org/rezept/suppe");
    vi.mocked(fetchPage)
      .mockResolvedValueOnce({ url, html: `<meta property="og:see_also" content="${source}">` })
      .mockResolvedValueOnce({ url: source, html: '<html lang="de"><script type="application/ld+json">{"@type":"Recipe","name":"Suppe","recipeIngredient":["1 l Wasser"],"recipeInstructions":["Aufkochen."]}</script></html>' });
    const response = await linkImport(request({ url: url.href, mode: "social" }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ via: "jsonld", draft: { source: source.href, steps: ["Aufkochen."] } });
    expect(aiObject).not.toHaveBeenCalled();
  });

  it("verwendet einen verlinkten Rezeptartikel ohne strukturierte Metadaten", async () => {
    const url = new URL("https://de.pinterest.com/pin/123/");
    const source = new URL("https://example.org/suppe");
    vi.mocked(fetchPage)
      .mockResolvedValueOnce({ url, html: `<meta property="og:see_also" content="${source}">` })
      .mockResolvedValueOnce({ url: source, html: "<h1>Suppe</h1><p>Zutaten für 4 Personen:</p><p>200 g Sellerie</p><p>In Brühe kochen.</p>" });
    const response = await linkImport(request({ url: url.href, mode: "social" }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ draft: { source: source.href } });
    expect(vi.mocked(aiObject).mock.calls[0][0].input).toContain("200 g Sellerie");
  });

  it("wertet einen öffentlichen Short per Video aus, wenn im Text die Schritte fehlen", async () => {
    const url = new URL("https://www.youtube.com/watch?v=abcdefghijk");
    const player = { videoDetails: { videoId: "abcdefghijk", title: "Suppe vom Wochenmarkt", shortDescription: "250 g rote Linsen. Die Anleitung steht im Video." } };
    vi.mocked(fetchPage).mockResolvedValueOnce({ url, html: `<script>var ytInitialPlayerResponse = ${JSON.stringify(player)};</script>` });
    const recipe = JSON.parse(mockRecipeExtract("Linsensuppe"));
    vi.mocked(aiObject).mockResolvedValueOnce({ data: { ...recipe, steps: [] }, cached: false });
    vi.mocked(socialVideoConfig).mockReturnValue({ key: "test-key", model: "gemini-test" });
    vi.mocked(extractSocialVideo).mockResolvedValue({ data: recipe, usage: { inputTokens: 100, outputTokens: 80 } });
    const response = await linkImport(request({ url: "https://youtube.com/shorts/abcdefghijk", mode: "social" }));
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ via: "video", draft: { title: "Linsensuppe", steps: recipe.steps } });
    expect(extractSocialVideo).toHaveBeenCalledWith(expect.anything(), url, expect.stringContaining("Anleitung steht im Video"), expect.any(Number));
  });

  it("liest Rezeptdaten ohne KI und markiert fehlende Zubereitung", async () => {
    vi.mocked(fetchPage).mockResolvedValue({ url: new URL("https://example.org/rezept"), html: '<html lang="de"><script type="application/ld+json">{"@type":"Recipe","name":"Suppe","recipeIngredient":["1 l Wasser"]}</script></html>' });
    const res = await linkImport(request({ url: "https://example.org/rezept" }));
    expect(res.status).toBe(200);
    expect((await res.json()).warnings).toContain("In der Quelle wurde keine Zubereitung gefunden. Bitte ergänzen.");
    expect(aiGuard).not.toHaveBeenCalled();
  });
  it("erhält das Original, falls die optionale Übersetzung ausfällt", async () => {
    vi.mocked(fetchPage).mockResolvedValue({ url: new URL("https://example.org/soup"), html: '<html lang="en"><script type="application/ld+json">{"@type":"Recipe","name":"Soup","recipeIngredient":["1 l water"]}</script></html>' });
    vi.mocked(aiObject).mockRejectedValue(new Error("provider unavailable"));
    const res = await linkImport(request({ url: "https://example.org/soup" }));
    expect(res.status).toBe(200);
    expect((await res.json()).draft.title).toBe("Soup");
  });
  it("bietet bei einem gesperrten Social-Post Ergänzungen an", async () => {
    const res = await linkImport(request({ url: "https://instagram.com/reel/ABC/", mode: "social" }));
    expect(res.status).toBe(422);
    expect(await res.json()).toMatchObject({ needs_input: true });
    expect(aiObject).not.toHaveBeenCalled();
  });
  it("importiert Beschreibung und Screenshots bei gesperrter Seite mit Originalquelle", async () => {
    const res = await linkImport(request({ url: "https://www.instagram.com/reel/ABC/?igsh=abc", text: "Zutaten: 200 g Mehl, 2 Eier. Verrühren und backen.", images: [jpeg] }));
    expect(res.status).toBe(200);
    expect((await res.json()).draft.source).toBe("https://www.instagram.com/reel/ABC/");
    const call = vi.mocked(aiObject).mock.calls[0][0];
    expect(JSON.stringify(call.input)).toContain(jpeg.data);
    expect(JSON.stringify(call.input)).toContain("200 g Mehl");
  });
  it("nimmt öffentliche Captions in den Cache-Schlüssel auf", async () => {
    vi.mocked(fetchPage).mockResolvedValue({ url: new URL("https://facebook.com/reel/123"), html: '<meta property="og:description" content="Zutaten: 200 g Mehl, 2 Eier. Alles verrühren und in der Pfanne backen.">' });
    expect((await linkImport(request({ url: "https://facebook.com/reel/123" }))).status).toBe(200);
    expect(JSON.stringify(vi.mocked(aiObject).mock.calls[0][0].cacheInput)).toContain("200 g Mehl");
  });
  it("liest auch ein kurzes, aber vollständiges Rezept", async () => {
    vi.mocked(fetchPage).mockResolvedValue({ url: new URL("https://instagram.com/reel/ABC/"), html: '<meta property="og:description" content="1 Ei, 50 g Mehl. Mischen und backen.">' });
    expect((await linkImport(request({ url: "https://instagram.com/reel/ABC/" }))).status).toBe(200);
  });
  it("löst einen TikTok-Kurzlink vor dem Auslesen der Beitrags-ID auf", async () => {
    const item = { __DEFAULT_SCOPE__: { "webapp.video-detail": { itemInfo: { itemStruct: { id: "123", desc: "Zutaten: 200 g Mehl, 2 Eier. Mischen und in der Pfanne backen." } } } } };
    vi.mocked(fetchPage).mockResolvedValue({ url: new URL("https://www.tiktok.com/@koch/video/123"), html: `<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">${JSON.stringify(item)}</script>` });
    const res = await linkImport(request({ url: "https://vm.tiktok.com/ABC/" }));
    expect(res.status).toBe(200);
    expect((await res.json()).draft.source).toBe("https://www.tiktok.com/@koch/video/123");
    expect(JSON.stringify(vi.mocked(aiObject).mock.calls[0][0].input)).toContain("200 g Mehl");
  });
  it("übernimmt nach einem Social-Redirect kein fremdes Rezept", async () => {
    vi.mocked(fetchPage).mockResolvedValue({ url: new URL("https://example.org/rezept"), html: '<script type="application/ld+json">{"@type":"Recipe","name":"Fremdes Rezept","recipeIngredient":["500 g Reis"]}</script>' });
    const res = await linkImport(request({ url: "https://instagram.com/reel/ABC/" }));
    expect(res.status).toBe(422);
    expect(aiObject).not.toHaveBeenCalled();
  });
  it("importiert oEmbed-Captions bei gesperrtem Seitenabruf", async () => {
    vi.mocked(fetchPage)
      .mockRejectedValueOnce(new AiError("blocked", 422, "bad-request"))
      .mockRejectedValueOnce(new AiError("embed unavailable", 422, "bad-request"))
      .mockResolvedValueOnce({ url: new URL("https://graph.facebook.com/v27.0/instagram_oembed"), html: JSON.stringify({ html: "<blockquote><p>200 g Mehl, 2 Eier. Verrühren und in der Pfanne backen.</p></blockquote>" }) });
    const response = await linkImport(request({ url: "https://instagram.com/reel/ABC/" }));
    expect(response.status).toBe(200);
    expect(JSON.stringify((await response.json()).warnings)).not.toContain("deinen Ergänzungen");
    expect(JSON.stringify(vi.mocked(aiObject).mock.calls[0][0].input)).toContain("200 g Mehl");
  });
  it("akzeptiert Instagram-Teilen-Links und wertet den aufgelösten Beitrag aus", async () => {
    vi.mocked(fetchPage).mockResolvedValue({ url: new URL("https://instagram.com/reel/ABC/"), html: '<meta property="og:description" content="200 g Mehl, 2 Eier. Verrühren und backen.">' });
    const response = await linkImport(request({ url: "https://instagram.com/share/reel/DEF/" }));
    expect(response.status).toBe(200);
    expect((await response.json()).draft.source).toBe("https://instagram.com/reel/ABC/");
  });
  it("erfindet aus einem Titel oder einer Loginseite kein Rezept", async () => {
    vi.mocked(fetchPage).mockResolvedValue({ url: new URL("https://youtube.com/watch?v=abcdefghijk"), html: "<title>Pasta</title><body>Anmelden</body>" });
    expect((await linkImport(request({ url: "https://youtube.com/shorts/abcdefghijk" }))).status).toBe(422);
    expect(aiObject).not.toHaveBeenCalled();
  });
  it("weist Profile beim Social-Import zurück", async () => {
    expect((await linkImport(request({ url: "https://instagram.com/koch/", mode: "social" }))).status).toBe(400);
    expect(fetchPage).not.toHaveBeenCalled();
  });
  it("überträgt Fotos in der gewählten Reihenfolge", async () => {
    const second = { ...jpeg, data: Buffer.from([255, 216, 255, 224, 4, 5, 6]).toString("base64") };
    expect((await photoImport(request({ images: [jpeg, second], cookbook: "Mein Buch" }))).status).toBe(200);
    const input = JSON.stringify(vi.mocked(aiObject).mock.calls[0][0].input);
    expect(input.indexOf(jpeg.data)).toBeLessThan(input.indexOf(second.data));
  });
  it.each([[], [jpeg, jpeg, jpeg, jpeg], [{ mediaType: "image/jpeg", data: "kein-bild" }], [{ mediaType: "image/png", data: jpeg.data }]])("weist ungültige Bilddaten ab", async (...images) => {
    expect((await photoImport(request({ images }))).status).toBe(400);
    expect(aiObject).not.toHaveBeenCalled();
  });
  it("weist ein leeres KI-Ergebnis trotz is_recipe zurück", async () => {
    vi.mocked(aiObject).mockResolvedValue({ data: { ...JSON.parse(mockRecipeExtract()), title: "", ingredients: [], steps: [] }, cached: false });
    expect((await photoImport(request({ images: [jpeg] }))).status).toBe(422);
  });
  it("verhindert Abrufe ohne Anmeldung", async () => {
    vi.mocked(aiSession).mockRejectedValue(new AiError("Bitte anmelden", 401, "unauthorized"));
    expect((await linkImport(request({ url: "https://example.org" }))).status).toBe(401);
    expect(fetchPage).not.toHaveBeenCalled();
  });
  it("verhindert Fotoimporte ohne Anmeldung", async () => {
    vi.mocked(aiGuard).mockRejectedValue(new AiError("Bitte anmelden", 401, "unauthorized"));
    expect((await photoImport(request({ images: [jpeg] }))).status).toBe(401);
    expect(aiObject).not.toHaveBeenCalled();
  });
  it.each([null, [], "kein Objekt"])("weist ungültige JSON-Eingaben ab", async (body) => {
    expect((await linkImport(request(body))).status).toBe(400);
    expect(fetchPage).not.toHaveBeenCalled();
  });
  it("begrenzt den gesamten Request vor der Bilddekodierung", async () => {
    const body = { images: [{ ...jpeg, data: "A".repeat(4_300_000) }] };
    expect((await photoImport(request(body))).status).toBe(413);
    expect(aiObject).not.toHaveBeenCalled();
  });
});

describe("Rezept-Assistenz API", () => {
  it("liefert nur Zuordnungen für vorhandene Zutaten und wörtliche Vorkommen", async () => {
    vi.mocked(aiObject).mockResolvedValueOnce({
      cached: false,
      data: {
        aliases: [
          { index: 0, text: "Nudeln" },
          { index: 1, text: "Blattsalat" },
          { index: 1, text: "Paprika" },
          { index: 8, text: "Nudeln" },
        ],
        missing: [0, 1, 1, 8],
      },
    });
    const { POST } = await import("../app/api/ai/recipe-assist/route");
    const response = await POST(request({
      task: "review", title: "Sommerrollen", ingredients: ["Reisbandnudeln", "Blattsalat"],
      steps: ["Nudeln einweichen."],
    }));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ aliases: [{ index: 0, text: "Nudeln" }], missing: [1] });
    expect(aiGuard).toHaveBeenCalledOnce();
  });

  it("prüft die Portionszahl vor einer Preisschätzung", async () => {
    const { POST } = await import("../app/api/ai/recipe-assist/route");
    vi.mocked(aiObject).mockResolvedValueOnce({ cached: false, data: { cents: 325 } });
    const input = { task: "price", title: "Suppe", ingredients: ["2 kg Kürbis"] };
    expect((await POST(request({ ...input, servings: 0 }))).status).toBe(400);
    expect(aiObject).not.toHaveBeenCalled();
    expect(await (await POST(request({ ...input, servings: 4 }))).json()).toEqual({ cents: 325 });
  });
});
