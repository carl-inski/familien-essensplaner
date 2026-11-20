import { NextResponse } from "next/server";
import { aiErrorResponse, aiSession, usageSummary } from "@/lib/ai/guard";

// Ist die KI eingerichtet, welches Modell, wie viel wurde verbraucht?

export async function GET(request: Request) {
  try {
    const ctx = await aiSession(request);
    const { cfg } = ctx;
    return NextResponse.json({
      enabled: cfg.enabled,
      reason: cfg.reason,
      provider: cfg.provider,
      models: cfg.enabled ? cfg.models : null,
      limits: cfg.limits,
      usage: await usageSummary(ctx),
    }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (e) {
    return aiErrorResponse(e);
  }
}
