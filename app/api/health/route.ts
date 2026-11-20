import { NextResponse } from "next/server";
import { supabaseEnv } from "@/lib/supabase/env";

// Für Uptime-Monitore (z. B. Better Stack, UptimeRobot): prüft, ob die App läuft und
// Supabase (Auth) antwortet. Gibt keine Daten preis.
export const dynamic = "force-dynamic";

export async function GET() {
  const started = Date.now();
  let supabase: "ok" | "down" = "down";
  try {
    const { url, key } = supabaseEnv();
    const res = await fetch(`${url}/auth/v1/health`, {
      headers: { apikey: key },
      signal: AbortSignal.timeout(3000),
      cache: "no-store",
    });
    if (res.ok) supabase = "ok";
  } catch {
    // bleibt "down"
  }
  const ok = supabase === "ok";
  return NextResponse.json(
    { status: ok ? "ok" : "degraded", supabase, ms: Date.now() - started },
    { status: ok ? 200 : 503, headers: { "Cache-Control": "no-store" } },
  );
}
