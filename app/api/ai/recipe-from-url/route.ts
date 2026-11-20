import { NextResponse, type NextRequest } from "next/server";
import { fetchRecipeCover, parseUserUrl } from "@/lib/ai/fetch-page";
import { AiError, aiErrorResponse, aiGuard, aiSession, logUsage } from "@/lib/ai/guard";
import { assertRecipeDraft, importImages, readImportBody } from "@/lib/ai/import-input";
import { mockRecipeExtract } from "@/lib/ai/mocks";
import { EXTRACT_RULES, asData, system } from "@/lib/ai/prompts";
import { aiObject } from "@/lib/ai/run";
import { RecipeExtractSchema, extractToDraft } from "@/lib/ai/schemas";
import { needsTranslation } from "@/lib/recipe-jsonld";
import { recipeImportWarnings } from "@/lib/recipe-source";
import { readRecipeSource } from "@/lib/ai/read-recipe-source";
import { extractSocialVideo, socialVideoConfig } from "@/lib/ai/social-video";
import type { RecipeDraft } from "@/lib/markdown";

export const maxDuration = 60;
export const runtime = "nodejs";

const supplementResponse = (source: string, message: string) => NextResponse.json({
  error: message, code: "source-incomplete", needs_input: true, source,
}, { status: 422 });

export async function POST(request: NextRequest) {
  const deadline = Date.now() + 55_000;
  try {
    await aiSession(request);
    const body = await readImportBody(request);
    const url = parseUserUrl(body.url);
    const images = importImages(body.images);
    if (body.text !== undefined && (typeof body.text !== "string" || body.text.length > 24000)) throw new AiError("Die Beschreibung darf höchstens 24.000 Zeichen enthalten.", 400, "bad-request");
    const description = typeof body.text === "string" ? body.text.trim() : "";
    const candidate = /^https?:\/\/[^\s<>"“”]+$/i.test(description) ? parseUserUrl(description) : undefined;
    const linkedRecipe = candidate?.href !== url.href ? candidate : undefined;
    const suppliedText = linkedRecipe ? "" : description;
    const supplemented = Boolean(suppliedText || images.length);
    const { source, text, transcript, draft: fromLd, language, sourceFailure, warnings, cover, video, partialDraft, platform } =
      await readRecipeSource(linkedRecipe ?? url, linkedRecipe ? "web" : body.mode, supplemented);
    if (linkedRecipe) warnings.push("Das Rezept stammt vom ergänzten Link.");
    const respond = (draft: RecipeDraft, via: string, cached?: boolean) => {
      assertRecipeDraft(draft);
      const finish = (image_data?: RecipeDraft["image_data"]) => NextResponse.json({
        draft: image_data ? { ...draft, image_data } : draft, via, cached, warnings: [...warnings, ...recipeImportWarnings(draft)],
      });
      const available = Math.min(2_500, deadline - Date.now());
      if (!draft.image_url && cover && platform && available > 100) {
        return fetchRecipeCover(cover, platform, available).then(finish, () => finish());
      }
      return Promise.resolve(finish());
    };
    if (fromLd && !supplemented && (!platform || fromLd.ingredients.length && fromLd.steps.length || !video)) {
      if (!needsTranslation(fromLd, language)) return respond(fromLd, "jsonld");
      try {
        const ctx = await aiGuard(request);
        const { image_url, ...recipe } = fromLd;
        const { data, cached } = await aiObject({
          ctx, feature: "rezept-url", timeoutMs: 30_000,
          system: system(`Du übersetzt Rezepte ins Deutsche.\n${EXTRACT_RULES}`),
          input: `Übersetze das Rezept ins Deutsche.\n${asData(source, JSON.stringify(recipe))}`,
          schema: RecipeExtractSchema, cacheInput: { version: 2, source, recipe, translation: true },
          mock: () => mockRecipeExtract("Mock-Übersetzung"),
        });
        const translated = extractToDraft(data, source);
        // Keep the complete original when a translation loses ingredients or steps.
        if (!data.is_recipe || translated.ingredients.length < fromLd.ingredients.length || translated.steps.length < fromLd.steps.length) throw new Error("Incomplete translation");
        return respond({ ...translated, image_url }, "jsonld-ki", cached);
      } catch {
        warnings.push("Die Übersetzung war nicht verfügbar. Das Original wurde übernommen.");
        return respond(fromLd, "jsonld");
      }
    }

    if (text.length < 20 && !transcript && !supplemented && !video) {
      return supplementResponse(source, sourceFailure ?? "Dieser öffentliche Link liefert keine lesbaren Rezeptangaben.");
    }
    if (sourceFailure && supplemented) warnings.push("Der Link war nicht lesbar. Der Entwurf beruht auf deinen Ergänzungen.");
    const ctx = await aiGuard(request);
    const content = [
      text && asData(source, text),
      transcript && asData("Öffentliche Untertitel", transcript),
      suppliedText && asData("Ergänzung zur Quelle", suppliedText),
    ].filter(Boolean).join("\n\n");
    const videoConfig = socialVideoConfig();

    const { data, cached } = content || images.length ? await aiObject({
      ctx, feature: "rezept-url", kind: images.length ? "strong" : "text", effort: "medium", timeoutMs: videoConfig && video ? 12_000 : 28_000,
      system: system(`Du überträgst Rezepte aus Webseiten, Beitragsbeschreibungen und optionalen Screenshots.\n${EXTRACT_RULES}\n- Ein Titel, ein Bild des fertigen Gerichts, Werbung oder ein Link allein sind kein Rezept.\n- Ergänze keine Zutaten oder Arbeitsschritte aus Vorwissen. Ohne Zutaten und ohne Zubereitung: is_recipe=false.\n- Übernimm nur das Rezept des verlinkten Beitrags, keine Kommentare oder Empfehlungen.\n- Fotos und kopierter Text ergänzen die Quelle; widersprüchliche Angaben nicht zusammenraten, im tip benennen.`),
      input: images.length ? [{ role: "user", content: [
        { type: "text", text: content },
        ...images.map((image) => ({ type: "file" as const, mediaType: image.mediaType, data: image.data })),
      ] }] : content,
      schema: RecipeExtractSchema, cacheInput: { version: 3, source, text: content, images },
      mock: () => mockRecipeExtract(),
    }).catch((error: unknown) => {
      if (videoConfig && video) return { data: null, cached: false };
      throw error;
    }) : { data: null, cached: false };
    let draft = data?.is_recipe ? extractToDraft(data, source) : null;
    let via = "ki";
    const remaining = deadline - Date.now();
    if ((!draft?.ingredients.length || !draft.steps.length) && videoConfig && video && remaining > 5_000) {
      try {
        const analysis = await extractSocialVideo(videoConfig, video, content, Math.min(remaining, 35_000));
        if (analysis) {
          await logUsage(ctx, { feature: "rezept-video", model: videoConfig.model, usage: analysis.usage });
          const candidate = analysis.data.is_recipe ? extractToDraft(analysis.data, source) : null;
          if (candidate?.title && (!draft || candidate.ingredients.length >= draft.ingredients.length && candidate.steps.length >= draft.steps.length)) {
            draft = candidate;
            via = "video";
          }
        }
      } catch { /* An inaccessible video must not discard a draft from the caption. */ }
    }
    if (!draft?.title || !draft.ingredients.length && !draft.steps.length) {
      if (fromLd) return respond(fromLd, "jsonld");
      if (partialDraft) return respond(partialDraft, "caption");
      return supplementResponse(source, "Der öffentlich abrufbare Beitrag enthält derzeit keine ausreichenden Rezeptangaben.");
    }
    if (transcript) warnings.push("Öffentliche Untertitel wurden mit ausgewertet. Bitte Mengen und Namen prüfen.");
    if (via === "video") warnings.push("Aus Ton und eingeblendetem Text des Videos übernommen. Bitte Mengen und Zubereitung prüfen.");
    return respond({ ...draft, image_url: fromLd?.image_url }, via, cached && via !== "video");
  } catch (error) {
    return aiErrorResponse(error);
  }
}
