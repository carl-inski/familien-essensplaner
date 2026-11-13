import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { BringLogo, KnusprLogo } from "@/components/brand-icons";
import { IconCart, IconCheck, IconHome, IconPeople } from "@/components/icons";
import { LandingDemo } from "@/components/landing/demo";
import { supabaseServer } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: { absolute: "Essensplaner · Gemeinsam planen, passend einkaufen" },
  description: "Gemeinsamer Wochenplan für Familien. Wer mitisst, bestimmt die Einkaufsliste. Ändert sich etwas, sehen alle sofort, was noch fehlt.",
};

// Angemeldet: direkt in die Woche. Sonst die Startseite für neue Familien.
export default async function Home() {
  const sb = await supabaseServer();
  const { data } = await sb.auth.getClaims();
  if (data?.claims) redirect("/woche");

  return (
    <div className="landing min-h-dvh bg-bg text-label">
      <header className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4 sm:px-6" style={{ paddingTop: "env(safe-area-inset-top)" }}>
        <Link href="/" className="flex items-center gap-2.5 font-semibold">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/icon.svg" alt="" width={30} height={30} className="rounded-[8px]" />
          Essensplaner
        </Link>
        <Link href="/login" className="btn btn-gray btn-sm pressable">Anmelden</Link>
      </header>

      <main>
        <section className="mx-auto grid max-w-6xl items-center gap-10 px-4 pt-8 pb-16 sm:px-6 lg:min-h-[calc(100dvh-4rem)] lg:grid-cols-[1fr_minmax(0,30rem)] lg:gap-16 lg:pt-4 lg:pb-20">
          <div className="landing-rise">
            <h1 className="text-[2.5rem] leading-[1.05] font-bold tracking-[-0.03em] sm:text-5xl lg:text-[3.75rem]">
              Wer mitisst, bestimmt den Einkauf.
            </h1>
            <p className="mt-5 max-w-[34ch] text-lg leading-relaxed text-label-2">
              Ein Wochenplan für die ganze Familie. Ändert sich etwas, zeigt die Liste sofort, was noch fehlt.
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-3">
              <Link href="/login?konto=neu" className="btn btn-primary pressable !min-h-12 !px-6 text-base">Erste Woche planen</Link>
              <Link href="/beitreten" className="btn btn-plain pressable !min-h-12">Ich habe einen Einladungscode</Link>
            </div>
          </div>
          <div className="landing-rise landing-rise-late">
            <LandingDemo />
          </div>
        </section>

        <section className="mx-auto max-w-6xl px-4 py-16 sm:px-6 lg:py-24">
          <h2 className="max-w-[18ch] text-3xl leading-tight font-bold tracking-[-0.02em] sm:text-4xl">Ein Plan für alle am Tisch</h2>
          <div className="mt-10 grid gap-3 md:grid-cols-6 md:grid-rows-[auto_auto]">
            <Tile className="md:col-span-4" tone="accent" icon={<IconPeople size={22} />} title="Jede Person sagt selbst, ob sie mitisst">
              Eine Standardwoche für den Alltag, Ausnahmen mit einem Tipp. Gäste zählen mit, die Portionen rechnen sich von allein.
            </Tile>
            <Tile className="md:col-span-2" tone="plain" icon={<IconCart size={22} />} title="Zu zweit im Laden">
              Abgehakt ist abgehakt, auf jedem Handy. Auch ohne Netz.
            </Tile>
            <Tile className="md:col-span-2" tone="plain" icon={<IconHome size={22} />} title="Was noch da ist, zählt mit">
              Fällt ein Essen aus, bleibt der Einkauf erhalten und wird beim nächsten Gericht abgezogen.
            </Tile>
            <Tile className="md:col-span-4" tone="ai" icon={<IconCheck size={22} />} title="Keine Lust zu entscheiden?">
              Swipen, Duell, Glücksrad oder Löffel: Jede Person spielt am eigenen Handy, und es gewinnt ein Gericht, das niemand abgelehnt hat.
            </Tile>
          </div>
        </section>

        <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
          <div className="flex flex-col items-start gap-6 rounded-[22px] bg-surface p-6 sm:p-8 md:flex-row md:items-center md:justify-between" style={{ boxShadow: "var(--card-edge)" }}>
            <div>
              <h2 className="text-2xl font-bold tracking-[-0.02em]">Einkaufen, wo ihr wollt</h2>
              <p className="mt-2 max-w-[48ch] text-label-2">Die Liste geht an Bring!, als Auftrag an Knuspr oder als Text in jede andere App.</p>
            </div>
            <div className="flex gap-3" aria-label="Bring! und Knuspr">
              <span className="flex h-14 w-14 items-center justify-center rounded-[14px]" style={{ background: "#333e44" }}>
                <BringLogo size={30} />
                <span className="sr-only">Bring!</span>
              </span>
              <span className="flex h-14 w-14 items-center justify-center rounded-[14px]" style={{ background: "#ff7400" }}>
                <KnusprLogo size={28} />
                <span className="sr-only">Knuspr</span>
              </span>
            </div>
          </div>
        </section>

        <section className="mx-auto max-w-6xl px-4 pt-12 pb-20 sm:px-6 lg:pb-28">
          <h2 className="max-w-[20ch] text-3xl leading-tight font-bold tracking-[-0.02em] sm:text-4xl">Diese Woche zusammen planen.</h2>
          <p className="mt-3 max-w-[44ch] text-lg text-label-2">Konto anlegen, drei Gerichte eintragen, die anderen per Link einladen.</p>
          <Link href="/login?konto=neu" className="btn btn-primary pressable mt-7 !min-h-12 !px-6 text-base">Erste Woche planen</Link>
        </section>
      </main>

      <footer className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 border-t border-separator px-4 py-6 text-sm text-label-2 sm:px-6">
        <span>Essensplaner</span>
        <Link href="/login" className="underline-offset-4 hover:underline">Anmelden</Link>
      </footer>
    </div>
  );
}

function Tile({ className = "", tone, icon, title, children }: { className?: string; tone: "accent" | "ai" | "plain"; icon: React.ReactNode; title: string; children: React.ReactNode }) {
  const bg = tone === "accent" ? "var(--accent-soft)" : tone === "ai" ? "var(--ai-soft)" : "var(--surface)";
  const fg = tone === "ai" ? "var(--ai)" : "var(--accent)";
  return (
    <article className={`flex flex-col gap-3 rounded-[22px] p-6 sm:p-7 ${className}`} style={{ background: bg, boxShadow: tone === "plain" ? "var(--card-edge)" : undefined }}>
      <span style={{ color: fg }}>{icon}</span>
      <h3 className="text-xl leading-snug font-bold tracking-[-0.01em]">{title}</h3>
      <p className="max-w-[52ch] leading-relaxed text-label-2">{children}</p>
    </article>
  );
}
