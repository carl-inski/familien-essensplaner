import { NextResponse, type NextRequest } from "next/server";
import { AiError, aiErrorResponse, aiGuard } from "@/lib/ai/guard";
import { mockRecipeExtract } from "@/lib/ai/mocks";
import { EXTRACT_RULES, system } from "@/lib/ai/prompts";
import { aiObject } from "@/lib/ai/run";
import { RecipeExtractSchema, extractToDraft } from "@/lib/ai/schemas";

// Rezept aus 1–3 Fotos (Kochbuchseite, Zettel, Screenshot). Läuft über das
// starke Modell, falls gesetzt, sonst über das Bildmodell.

export const maxDuration = 60;

const MEDIA = ["image/jpeg", "image/png", "image/webp", "image/gif"];

export async function POST(request: NextRequest) {
  try {
    const ctx = await aiGuard();
    const body = await request.json().catch(() => ({}));
    const images: { data: string; mediaType: string }[] = Array.isArray(body.images) ? body.images : [];
    if (!images.length || images.length > 3) throw new AiError("Bitte 1 bis 3 Fotos auswählen.", 400, "bad-request");
    for (const i of images) {
      if (typeof i?.data !== "string" || !MEDIA.includes(i.mediaType)) throw new AiError("Dieses Bildformat wird nicht unterstützt.", 400, "bad-request");
      if (i.data.length > 4_000_000) throw new AiError("Ein Foto ist zu groß.", 413, "bad-request");
    }
    const hint = typeof body.cookbook === "string" && body.cookbook.trim() ? body.cookbook.trim().slice(0, 120) : null;

    const { data, cached } = await aiObject({
      ctx,
      feature: "rezept-foto",
      kind: "strong",
      effort: "medium",
      system: system(
        `Du liest Rezepte von Fotos ab: Kochbuchseiten, handschriftliche Zettel, Screenshots.\n${EXTRACT_RULES}\n- Steht ein Buchtitel oder eine Seitenzahl auf dem Foto, übernimm sie in cookbook_title und cookbook_page.`,
      ),
      input: [
        {
          role: "user",
          content: [
            { type: "text", text: `Lies das Rezept von ${images.length > 1 ? "diesen Fotos (in Reihenfolge)" : "diesem Foto"} ab.${hint ? ` Es stammt vermutlich aus dem Buch „${hint}“.` : ""}` },
            ...images.map((i) => ({ type: "file" as const, mediaType: i.mediaType, data: i.data })),
          ],
        },
      ],
      schema: RecipeExtractSchema,
      cacheInput: images.map((i) => i.data),
      mock: () => mockRecipeExtract("Mock-Rezept vom Foto"),
    });
    if (!data.is_recipe) throw new AiError("Auf dem Foto wurde kein Rezept erkannt.", 422, "bad-request");
    const draft = extractToDraft(data, null);
    if (hint && !draft.cookbook) draft.cookbook = { title: hint, page: data.cookbook_page ?? null };
    return NextResponse.json({ draft, via: "ki", cached });
  } catch (e) {
    return aiErrorResponse(e);
  }
}
