import "server-only";
import { generateText, NoObjectGeneratedError, Output, type LanguageModelUsage, type ModelMessage } from "ai";
import type { z } from "zod";
import { cacheGet, cacheKey, cacheSet } from "./cache";
import type { ModelKind } from "./config";
import type { TokenUsage } from "./cost";
import { logUsage, type AiContext } from "./guard";
import { aiModel, aiProviderOptions, type Effort, type MockReply } from "./provider";

export function toTokenUsage(u: LanguageModelUsage | undefined): TokenUsage | undefined {
  if (!u) return undefined;
  return {
    inputTokens: u.inputTokens,
    outputTokens: u.outputTokens,
    cacheReadTokens: u.inputTokenDetails?.cacheReadTokens,
    cacheWriteTokens: u.inputTokenDetails?.cacheWriteTokens,
  };
}

interface ObjectCall<S extends z.ZodType> {
  ctx: AiContext;
  feature: string;
  kind?: ModelKind;
  system: string;
  input: string | ModelMessage[];
  schema: S;
  effort?: Effort;
  /** Eingabe für den Cache-Schlüssel; ohne Angabe kein Cache */
  cacheInput?: unknown;
  cacheDays?: number;
  mock?: MockReply;
}

/**
 * Strukturierte KI-Antwort: Cache → Modell → Prüfung per Zod (bei
 * ungültiger Antwort ein zweiter Versuch) → Protokoll → Cache.
 */
export async function aiObject<S extends z.ZodType>(call: ObjectCall<S>): Promise<{ data: z.infer<S>; cached: boolean }> {
  const { ctx, feature, kind = "text" } = call;
  const model = ctx.cfg.models[kind];
  const key = call.cacheInput !== undefined ? cacheKey(feature, ctx.householdId, call.cacheInput) : null;
  if (key) {
    const hit = await cacheGet<z.infer<S>>(ctx, key);
    if (hit) {
      await logUsage(ctx, { feature, model, cacheHit: true });
      return { data: hit, cached: true };
    }
  }

  const run = () =>
    generateText({
      model: aiModel(ctx.cfg, kind, call.mock),
      system: call.system,
      ...(typeof call.input === "string" ? { prompt: call.input } : { messages: call.input }),
      output: Output.object({ schema: call.schema }),
      providerOptions: aiProviderOptions(ctx.cfg, call.effort),
      maxRetries: 1,
    });

  let result;
  try {
    result = await run();
  } catch (e) {
    if (!NoObjectGeneratedError.isInstance(e)) throw e;
    await logUsage(ctx, { feature, model, usage: toTokenUsage(e.usage) });
    result = await run();
  }
  await logUsage(ctx, { feature, model, usage: toTokenUsage(result.usage) });
  const data = result.output as z.infer<S>;
  if (key) await cacheSet(ctx, key, feature, data, call.cacheDays);
  return { data, cached: false };
}
