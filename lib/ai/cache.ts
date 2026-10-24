import "server-only";
import { createHash } from "node:crypto";
import type { AiContext } from "./guard";

// Gleiche Eingabe (URL, Bild, Zutatenname …) → kein neuer KI-Aufruf.
// Schlüssel aus Funktion, Haushalt und Hash der Eingabe.

export function cacheKey(feature: string, householdId: string, input: unknown): string {
  const hash = createHash("sha256").update(typeof input === "string" ? input : JSON.stringify(input)).digest("hex");
  return `${feature}:${householdId}:${hash}`;
}

export async function cacheGet<T>(ctx: AiContext, key: string): Promise<T | null> {
  const { data } = await ctx.sb.from("ep_ai_cache").select("result, expires_at").eq("key", key).maybeSingle();
  if (!data) return null;
  if (data.expires_at && new Date(data.expires_at) < new Date()) return null;
  return data.result as T;
}

export async function cacheSet(ctx: AiContext, key: string, feature: string, result: unknown, ttlDays = 30) {
  const expires_at = new Date(Date.now() + ttlDays * 86400000).toISOString();
  await ctx.sb
    .from("ep_ai_cache")
    .upsert({ key, feature, household_id: ctx.householdId, result, expires_at, created_at: new Date().toISOString() });
}
