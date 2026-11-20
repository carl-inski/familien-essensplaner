import "server-only";
import { z } from "zod";
import { asData, EXTRACT_RULES, system } from "./prompts";
import { RecipeExtractSchema } from "./schemas";

const ResponseSchema = z.object({
  candidates: z.array(z.object({
    content: z.object({ parts: z.array(z.object({ text: z.string().optional(), thought: z.boolean().optional() })) }),
  })),
  usageMetadata: z.object({ promptTokenCount: z.number().optional(), candidatesTokenCount: z.number().optional() }).optional(),
});

export function socialVideoConfig() {
  const key = process.env.GEMINI_API_KEY?.trim();
  const model = process.env.GEMINI_RECIPE_VIDEO_MODEL?.trim() || "gemini-3.8-flash";
  return key && /^[a-z0-9.-]+$/i.test(model) ? { key, model } : null;
}

export async function extractSocialVideo(
  config: NonNullable<ReturnType<typeof socialVideoConfig>>,
  video: URL,
  sourceText: string,
  timeoutMs: number,
) {
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${config.model}:generateContent`, {
    method: "POST",
    redirect: "error",
    headers: { "Content-Type": "application/json", "x-goog-api-key": config.key },
    signal: AbortSignal.timeout(timeoutMs),
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: system(`Lies genau ein Rezept aus dem beigefügten Video und der Beschreibung. Nutze Ton und eingeblendeten Text. Mengen, Schritte und Zutaten nur übernehmen, wenn sie in einer dieser Quellen nachvollziehbar sind. Bei reiner Werbung oder einem Gericht ohne Rezept setze is_recipe=false.\n${EXTRACT_RULES}`) }] },
      contents: [{ parts: [
        { fileData: { fileUri: video.href, ...(video.hostname === "www.youtube.com" ? {} : { mimeType: "video/mp4" }) } },
        { text: asData("Öffentliche Beitragsbeschreibung", sourceText) },
      ] }],
      generationConfig: {
        responseMimeType: "application/json",
        responseJsonSchema: z.toJSONSchema(RecipeExtractSchema),
      },
    }),
  });
  if (!response.ok) return null;
  const payload = ResponseSchema.parse(await response.json());
  const text = payload.candidates[0]?.content.parts.filter((part) => !part.thought).map((part) => part.text ?? "").join("");
  if (!text) return null;
  const parsed = RecipeExtractSchema.safeParse(JSON.parse(text));
  return parsed.success ? { data: parsed.data, usage: {
    inputTokens: payload.usageMetadata?.promptTokenCount,
    outputTokens: payload.usageMetadata?.candidatesTokenCount,
  } } : null;
}
