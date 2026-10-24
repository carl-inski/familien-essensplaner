import { NextResponse, type NextRequest } from "next/server";
import { fetchPage, parseUserUrl } from "@/lib/ai/fetch-page";
import { AiError, aiErrorResponse, aiGuard, aiSession } from "@/lib/ai/guard";
import { mockRecipeExtract } from "@/lib/ai/mocks";
import { EXTRACT_RULES, asData, system } from "@/lib/ai/prompts";
import { aiObject } from "@/lib/ai/run";
import { RecipeExtractSchema, extractToDraft } from "@/lib/ai/schemas";
import { needsTranslation, pageLanguage, pageText, recipeFromHtml } from "@/lib/recipe-jsonld";

// Rezept aus einem Link: zuerst schema.org-JSON-LD (kostenlos, ohne KI).
// Fremdsprachige Rezepte übersetzt die KI, Seiten ohne Rezeptdaten liest sie ganz.

export const maxDuration = 60;

export async function POST(request: NextRequest) {
  try {
    await aiSession();
    const body = await request.json().catch(() => ({}));
    const url = parseUserUrl(body.url);
    const page = await fetchPage(url);
    const source = page.url.toString();

    const fromLd = recipeFromHtml(page.html, source);
    if (fromLd) {
      if (!needsTranslation(fromLd, pageLanguage(page.html))) return NextResponse.json({ draft: fromLd, via: "jsonld" });
      // Ohne KI lieber das Original als gar nichts
      const ctx = await aiGuard().catch(() => null);
      if (!ctx) return NextResponse.json({ draft: fromLd, via: "jsonld" });
      const { image_url, ...rest } = fromLd;
      const { data, cached } = await aiObject({
        ctx,
        feature: "rezept-url",
        system: system(`Du übersetzt Rezepte ins Deutsche.\n${EXTRACT_RULES}`),
        input: `Übersetze dieses Rezept ins Deutsche und rechne alle Mengen metrisch um.\n\n${asData(source, JSON.stringify(rest))}`,
        schema: RecipeExtractSchema,
        cacheInput: `${source}#uebersetzt`,
        mock: () => mockRecipeExtract("Mock-Übersetzung"),
      });
      if (!data.is_recipe) return NextResponse.json({ draft: fromLd, via: "jsonld" });
      return NextResponse.json({ draft: { ...extractToDraft(data, source), image_url }, via: "jsonld-ki", cached });
    }

    const text = pageText(page.html);
    if (text.length < 200) throw new AiError("Auf der Seite steht kaum Text – vielleicht ist sie hinter einem Login.", 422, "bad-request");
    const ctx = await aiGuard().catch((e) => {
      if (e instanceof AiError && e.code === "not-configured") {
        throw new AiError("Die Seite liefert keine Rezeptdaten mit, und die KI ist noch nicht eingerichtet.", 422, "not-configured");
      }
      throw e;
    });
    const { data, cached } = await aiObject({
      ctx,
      feature: "rezept-url",
      system: system(`Du liest Rezepte von Webseiten aus.\n${EXTRACT_RULES}`),
      input: `Quelle: ${source}\n\n${asData(source, text)}`,
      schema: RecipeExtractSchema,
      cacheInput: source,
      mock: () => mockRecipeExtract(),
    });
    if (!data.is_recipe) throw new AiError("Auf der Seite wurde kein Rezept gefunden.", 422, "bad-request");
    return NextResponse.json({ draft: extractToDraft(data, source), via: "ki", cached });
  } catch (e) {
    return aiErrorResponse(e);
  }
}
