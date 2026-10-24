import { generateText } from "ai";
import { NextResponse } from "next/server";
import { aiErrorResponse, aiGuard, logUsage } from "@/lib/ai/guard";
import { system } from "@/lib/ai/prompts";
import { aiModel, aiProviderOptions } from "@/lib/ai/provider";
import { toTokenUsage } from "@/lib/ai/run";

// Verbindungstest aus dem Haushalt: ein winziger Aufruf, Kosten < 0,01 Cent.

export async function POST() {
  try {
    const ctx = await aiGuard();
    const started = Date.now();
    const result = await generateText({
      model: aiModel(ctx.cfg, "text", () => "Hallo, die KI ist bereit."),
      system: system("Bestätige in einem kurzen Satz, dass du bereit bist."),
      prompt: "Bist du bereit?",
      providerOptions: aiProviderOptions(ctx.cfg, "low"),
      maxRetries: 1,
    });
    await logUsage(ctx, { feature: "test", model: ctx.cfg.models.text, usage: toTokenUsage(result.usage) });
    return NextResponse.json({ text: result.text, model: ctx.cfg.models.text, ms: Date.now() - started });
  } catch (e) {
    return aiErrorResponse(e);
  }
}
