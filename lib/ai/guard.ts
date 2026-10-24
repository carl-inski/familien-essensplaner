import "server-only";
import type { SupabaseClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { supabaseServer } from "@/lib/supabase/server";
import type { Member } from "@/lib/types";
import { readAiConfig, type AiConfig } from "./config";
import { estimateCostEur, limitMessage, type TokenUsage } from "./cost";

export class AiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code: "unauthorized" | "no-access" | "not-configured" | "limit" | "bad-request" | "failed",
  ) {
    super(message);
  }
}

export interface AiContext {
  sb: SupabaseClient;
  cfg: AiConfig;
  member: Member;
  householdId: string;
}

export interface UsageSummary {
  month_calls: number;
  month_cache_hits: number;
  month_cost_eur: number;
  my_calls_today: number;
}

/** Session, Haushaltsmitglied und Konfiguration – ohne Limitprüfung */
export async function aiSession(): Promise<AiContext> {
  const sb = await supabaseServer();
  const { data: auth } = await sb.auth.getUser();
  if (!auth.user) throw new AiError("Bitte melde dich an.", 401, "unauthorized");
  const { data } = await sb.from("ep_members").select("*").eq("user_id", auth.user.id).limit(1);
  const member = (data as Member[] | null)?.[0];
  if (!member) throw new AiError("Kein Zugang zu einem Haushalt.", 403, "no-access");
  return { sb, cfg: readAiConfig(), member, householdId: member.household_id };
}

export async function usageSummary(ctx: AiContext): Promise<UsageSummary> {
  const { data, error } = await ctx.sb.rpc("ep_ai_usage_summary", { p_household: ctx.householdId, p_member: ctx.member.id });
  if (error) throw new AiError("Verbrauch konnte nicht gelesen werden.", 500, "failed");
  const row = (data as UsageSummary[] | null)?.[0];
  return {
    month_calls: row?.month_calls ?? 0,
    month_cache_hits: row?.month_cache_hits ?? 0,
    month_cost_eur: Number(row?.month_cost_eur ?? 0),
    my_calls_today: row?.my_calls_today ?? 0,
  };
}

/** Für jede KI-Route: angemeldet, eingerichtet, Limits nicht überschritten */
export async function aiGuard(): Promise<AiContext> {
  const ctx = await aiSession();
  if (!ctx.cfg.enabled) throw new AiError(`KI noch nicht eingerichtet. ${ctx.cfg.reason ?? ""}`.trim(), 503, "not-configured");
  const u = await usageSummary(ctx);
  const msg = limitMessage({ callsToday: u.my_calls_today, costMonthEur: u.month_cost_eur }, ctx.cfg.limits);
  if (msg) throw new AiError(msg, 429, "limit");
  return ctx;
}

export async function logUsage(ctx: AiContext, entry: { feature: string; model: string; usage?: TokenUsage; cacheHit?: boolean }) {
  const cost = entry.cacheHit || !entry.usage ? 0 : estimateCostEur(entry.usage, ctx.cfg.prices);
  await ctx.sb.from("ep_ai_usage").insert({
    household_id: ctx.householdId,
    member_id: ctx.member.id,
    feature: entry.feature,
    model: entry.model,
    tokens_in: entry.usage?.inputTokens ?? null,
    tokens_out: entry.usage?.outputTokens ?? null,
    cost_eur: cost,
    cache_hit: entry.cacheHit ?? false,
  });
}

/** Einheitliche Fehlerantwort für alle KI-Routen */
export function aiErrorResponse(e: unknown) {
  if (e instanceof AiError) return NextResponse.json({ error: e.message, code: e.code }, { status: e.status });
  console.error("[ai]", e);
  return NextResponse.json({ error: "Die KI hat gerade nicht geantwortet. Bitte später nochmal versuchen.", code: "failed" }, { status: 502 });
}
