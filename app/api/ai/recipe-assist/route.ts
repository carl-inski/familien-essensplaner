import { NextResponse, type NextRequest } from "next/server";
import { z } from "zod";
import { AiError, aiErrorResponse, aiGuard } from "@/lib/ai/guard";
import { readImportBody } from "@/lib/ai/import-input";
import { asData, system } from "@/lib/ai/prompts";
import { aiObject } from "@/lib/ai/run";

const title = z.string().trim().min(1).max(300);
const names = z.array(z.string().trim().min(1).max(240)).min(1).max(100);
const requestSchema = z.discriminatedUnion("task", [
  z.object({ task: z.literal("review"), title, ingredients: names, steps: z.array(z.string().max(4000)).min(1).max(80) }),
  z.object({ task: z.literal("price"), title, ingredients: names, servings: z.number().int().min(1).max(200) }),
]);
const review = z.object({
  aliases: z.array(z.object({ index: z.number().int().min(0), text: z.string().trim().min(1).max(90) })).max(150),
  missing: z.array(z.number().int().min(0)).max(100),
});
const price = z.object({ cents: z.number().int().min(0).max(100_000) });
const words = (text: string) => text.normalize("NFC").toLocaleLowerCase("de").match(/[\p{L}\p{N}]+/gu) ?? [];

export const maxDuration = 35;

export async function POST(request: NextRequest) {
  try {
    const ctx = await aiGuard(request);
    const parsed = requestSchema.safeParse(await readImportBody(request));
    if (!parsed.success) throw new AiError("Bitte gib ein vollständiges Rezept an.", 400, "bad-request");
    const input = parsed.data;
    if (input.task === "price") {
      const result = await aiObject({
        ctx, feature: "rezept-preisschaetzung", schema: price, timeoutMs: 24000,
        system: system("Schätze den Zutatenpreis pro Portion in Euro-Cent für einen üblichen Supermarkteinkauf in Deutschland. Berechne nur tatsächlich verwendete Mengen und teile durch die angegebenen Portionen. Runde auf fünf Cent. Es ist eine grobe Schätzung, keine Auskunft über aktuelle Ladenpreise."),
        input: asData("Rezept", JSON.stringify(input)), cacheInput: input, cacheDays: 7,
        mock: () => JSON.stringify({ cents: 325 }),
      });
      return NextResponse.json(result.data);
    }
    const result = await aiObject({
      ctx, feature: "rezept-zutatenabgleich", schema: review, timeoutMs: 24000,
      system: system("Prüfe die Zubereitung gegen die Zutatenliste. Gib Textstellen aus den Schritten mit dem Index (beginnend bei 0) der zugehörigen Zutat zurück. Finde besonders Diminutive, Synonyme, Kurzformen, zusammengesetzte Wörter und Alternativen. Zitiere die konkrete Zutat genau aus dem Schritt, ohne Mengenzahlen oder Verben. Bei Gruppenbegriffen, die mehrere Zutaten meinen, und bei Mehrdeutigkeit keine Zuordnung. Melde in missing nur wesentliche, nicht optionale Zutaten, die in keinem Schritt verwendet werden. Schreibe nichts um und erfinde keine Wörter."),
      input: asData("Zutaten und Schritte", JSON.stringify(input)), cacheInput: input, cacheDays: 30,
      mock: () => JSON.stringify({ aliases: [], missing: [] }),
    });
    const steps = input.steps.map((step) => ` ${words(step).join(" ")} `);
    const aliases = result.data.aliases.filter(({ index, text }) => {
      const phrase = words(text);
      return index < input.ingredients.length && phrase.length > 0 && phrase.length <= 6 &&
        steps.some((step) => step.includes(` ${phrase.join(" ")} `));
    });
    const mapped = new Set(aliases.map(({ index }) => index));
    const missing = [...new Set(result.data.missing)].filter((index) => index < input.ingredients.length && !mapped.has(index));
    return NextResponse.json({ aliases, missing });
  } catch (error) {
    return aiErrorResponse(error);
  }
}
