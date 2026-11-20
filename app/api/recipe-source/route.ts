import { NextResponse } from "next/server";
import { fetchRecipeCover, parseUserUrl } from "@/lib/ai/fetch-page";
import { AiError, aiErrorResponse, aiSession } from "@/lib/ai/guard";
import { readImportBody } from "@/lib/ai/import-input";
import { readRecipeSource } from "@/lib/ai/read-recipe-source";
import { needsTranslation } from "@/lib/recipe-jsonld";
import { recipeImportWarnings } from "@/lib/recipe-source";

export const runtime = "nodejs";
export const maxDuration = 35;

let pending = 0;

export async function POST(request: Request) {
  // Nur angemeldet: sonst wäre die Route ein offener Abruf-Dienst für beliebige Links.
  try {
    await aiSession(request);
  } catch (error) {
    return aiErrorResponse(error instanceof AiError ? error : new AiError("Bitte melde dich an.", 401, "unauthorized"));
  }
  if (pending >= 6) return NextResponse.json({ error: "Der Linkabruf ist gerade ausgelastet." }, { status: 429 });
  pending++;
  try {
    const body = await readImportBody(request, 8192);
    const { source, draft, text, transcript, language, warnings, cover, video, images = [], partialDraft, platform, sourceFailure } =
      await readRecipeSource(parseUserUrl(body.url), body.mode, body.supplemented === true);
    const fullDraft = draft?.ingredients.length && draft.steps.length ? draft : undefined;
    const videoURL = platform === "instagram" || platform === "tiktok" || platform === "facebook" ? video?.href : undefined;
    const media = !fullDraft && platform && body.supplemented !== true
      ? await Promise.all(images.map((url) => fetchRecipeCover(url, platform, 2000).catch(() => undefined)))
      : [];
    const postImages = media.filter((image) => image && image.data.length <= 700_000);
    if (!fullDraft && text.length < 20 && !transcript && !videoURL && !postImages.length) {
      return NextResponse.json({
        source, needs_input: true, error: sourceFailure ?? "Der öffentliche Link enthält keine lesbaren Rezeptangaben.",
      }, { status: 422 });
    }
    const downloadedCover = media[images.findIndex((url) => url.href === cover?.href)];
    const image = downloadedCover ??
      (cover && platform ? await fetchRecipeCover(cover, platform, 2000).catch(() => undefined) : undefined) ??
      postImages[0];
    return NextResponse.json({
      source, text, transcript, draft: fullDraft,
      partial_draft: fullDraft ? undefined : draft?.ingredients.length ? draft : partialDraft,
      image_data: image, video_url: videoURL, post_images: postImages,
      needs_translation: fullDraft ? needsTranslation(fullDraft, language) : false,
      warnings: [...warnings, ...(fullDraft ? recipeImportWarnings(fullDraft) : [])],
    }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    return aiErrorResponse(error instanceof AiError ? error : new AiError("Der öffentliche Link konnte nicht gelesen werden.", 502, "failed"));
  } finally {
    pending--;
  }
}
