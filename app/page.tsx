import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { Landing } from "@/components/landing/landing";
import { supabaseServer } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: { absolute: "Gnocchi · Gemeinsam planen, passend einkaufen" },
  description: "Gemeinsamer Wochenplan für Familien. Wer mitisst, bestimmt die Einkaufsliste. Ändert sich etwas, sehen alle sofort, was noch fehlt.",
};

// Angemeldet: direkt in die Woche. Sonst die Startseite für neue Familien.
export default async function Home() {
  const sb = await supabaseServer();
  const { data } = await sb.auth.getClaims();
  if (data?.claims) redirect("/woche");

  return <Landing />;
}
