import "server-only";
import { createClient } from "@supabase/supabase-js";
import { headers } from "next/headers";
import { supabaseEnv } from "@/lib/supabase/env";

// Öffentliche Seiten lesen ausschließlich über die Slug-RPCs (security definer, nur Lesezugriff).
export function anonClient() {
  const { url, key } = supabaseEnv();
  return createClient(url, key, { auth: { persistSession: false } });
}

export async function requestOrigin(): Promise<string> {
  if (process.env.NEXT_PUBLIC_SITE_URL) return process.env.NEXT_PUBLIC_SITE_URL.replace(/\/$/, "");
  const h = await headers();
  const host = h.get("x-forwarded-host") ?? h.get("host") ?? "localhost:3000";
  const proto = h.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
  return `${proto}://${host}`;
}

export function jsonLd(data: unknown): string {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}
