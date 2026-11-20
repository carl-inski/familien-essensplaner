import Link from "next/link";
import { BringLogo, KnusprLogo } from "@/components/brand-icons";
import { IconCalendar, IconCart, IconCheck, IconDice, IconFork, IconHome, IconPeople } from "@/components/icons";
import { LandingDemo } from "@/components/landing/demo";
import { Gnocco } from "@/components/landing/gnocco";
import { PhoneMock } from "@/components/landing/phone";

// Die Startseite für neue Familien. Gestaltung: Abschnitt „Gnocchi-Gestaltung“ in app/globals.css.
export function Landing() {
  return (
    <div className="landing min-h-dvh text-label">
      <header className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4 sm:px-6" style={{ paddingTop: "env(safe-area-inset-top)" }}>
        <Link href="/" className="flex items-center gap-2 text-lg font-bold tracking-[-0.02em]">
          <Gnocco size={34} />
          Gnocchi
        </Link>
        <Link href="/login" className="lp-btn lp-btn-soft pressable !min-h-10 !px-4 text-sm">Anmelden</Link>
      </header>

      <main>
        {/* Einstieg: große Zeile mit eingesetzten Symbolen, darunter die App */}
        <section className="mx-auto max-w-6xl px-4 pt-10 pb-8 text-center sm:px-6 sm:pt-16">
          <div className="landing-rise">
            <p className="lp-eyebrow">Der Essensplaner für Familien</p>
            <h1 className="lp-display mx-auto mt-4 max-w-[17ch]">
              Wer <span className="whitespace-nowrap"><Chip tone="tomato"><IconPeople size={22} />mitisst</Chip>,</span> bestimmt den <span className="whitespace-nowrap"><Chip tone="basil"><IconCart size={22} />Einkauf</Chip>.</span>
            </h1>
            <p className="mx-auto mt-6 max-w-[38ch] text-lg leading-relaxed text-label-2">
              Ein Wochenplan für alle am Tisch. Ändert sich etwas, zeigt die Liste sofort, was noch fehlt.
            </p>
            <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
              <Link href="/login?konto=neu" className="lp-btn lp-btn-ink pressable">Erste Woche planen</Link>
              <Link href="/beitreten" className="lp-btn lp-btn-soft pressable">Ich habe einen Einladungscode</Link>
            </div>
          </div>

          <div className="landing-rise landing-rise-late lp-stage mt-14">
            <div className="lp-blob lp-blob-a" aria-hidden />
            <div className="lp-blob lp-blob-b" aria-hidden />
            <PhoneMock />
            <div className="lp-float lp-float-left">
              <Gnocco mood="curious" size={84} />
              <span className="lp-bubble">Was kochen wir heute?</span>
            </div>
            <div className="lp-float lp-float-right">
              <span className="lp-toast"><IconCheck size={16} strokeWidth={3} />Einkauf erledigt</span>
              <Gnocco mood="cheering" size={72} />
            </div>
          </div>
        </section>

        {/* Vier Wörter, eines scharf: derselbe Einstieg wie in der App */}
        <section className="mx-auto max-w-6xl px-4 py-14 sm:px-6 lg:py-20" aria-label="Planen, einkaufen, kochen, entscheiden">
          <ul className="lp-words" aria-hidden>
            <li><IconCalendar size={30} />Planen</li>
            <li><IconCart size={30} />Einkaufen</li>
            <li><IconFork size={30} />Kochen</li>
            <li><IconDice size={30} />Entscheiden</li>
          </ul>
        </section>

        <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6 lg:py-20">
          <p className="lp-eyebrow">So funktioniert es</p>
          <h2 className="lp-title mt-3 max-w-[18ch]">Ein Plan für alle am Tisch</h2>
          <div className="mt-10 grid gap-3 md:grid-cols-6">
            <Tile className="md:col-span-4" tone="tomato" icon={<IconPeople size={22} />} title="Jede Person sagt selbst, ob sie mitisst">
              Eine Standardwoche für den Alltag, Ausnahmen mit einem Tipp. Gäste zählen mit, die Portionen rechnen sich von allein.
            </Tile>
            <Tile className="md:col-span-2" tone="plain" icon={<IconCart size={22} />} title="Zu zweit im Laden">
              Abgehakt ist abgehakt, auf jedem Handy. Auch ohne Netz.
            </Tile>
            <Tile className="md:col-span-2" tone="plain" icon={<IconHome size={22} />} title="Was noch da ist, zählt mit">
              Fällt ein Essen aus, bleibt der Einkauf erhalten und wird beim nächsten Gericht abgezogen.
            </Tile>
            <Tile className="md:col-span-4" tone="basil" icon={<IconDice size={22} />} title="Keine Lust zu entscheiden?">
              Swipen, Duell, Glücksrad oder Löffel: Jede Person spielt am eigenen Handy, und es gewinnt ein Gericht, das niemand abgelehnt hat.
            </Tile>
          </div>
        </section>

        {/* Zum Anfassen: dieselbe Logik wie in der App */}
        <section className="mx-auto grid max-w-6xl items-center gap-10 px-4 py-12 sm:px-6 lg:grid-cols-[1fr_minmax(0,30rem)] lg:gap-16 lg:py-20">
          <div>
            <p className="lp-eyebrow">Zum Ausprobieren</p>
            <h2 className="lp-title mt-3 max-w-[16ch]">Der Plan ändert sich. Die Liste kommt mit.</h2>
            <p className="mt-4 max-w-[42ch] text-lg leading-relaxed text-label-2">
              Mittwoch, 17:30 Uhr, ihr esst doch auswärts. Schaltet es um und seht, was mit dem Einkauf passiert. Hier rechnet dieselbe Logik wie in der App.
            </p>
          </div>
          <LandingDemo />
        </section>

        <section className="mx-auto max-w-6xl px-4 py-12 sm:px-6">
          <div className="lp-card flex flex-col items-start gap-6 p-6 sm:p-8 md:flex-row md:items-center md:justify-between">
            <div>
              <h2 className="text-2xl font-bold tracking-[-0.02em]">Einkaufen, wo ihr wollt</h2>
              <p className="mt-2 max-w-[48ch] text-label-2">Die Liste geht an Bring!, als Auftrag an Knuspr oder als Text in jede andere App.</p>
            </div>
            <div className="flex gap-3" aria-label="Bring! und Knuspr">
              <span className="flex h-14 w-14 items-center justify-center rounded-[18px]" style={{ background: "#333e44" }}>
                <BringLogo size={30} />
                <span className="sr-only">Bring!</span>
              </span>
              <span className="flex h-14 w-14 items-center justify-center rounded-[18px]" style={{ background: "#ff7400" }}>
                <KnusprLogo size={28} />
                <span className="sr-only">Knuspr</span>
              </span>
            </div>
          </div>
        </section>

        {/* Abschluss: drei Schritte wie im Onboarding der App */}
        <section className="mx-auto max-w-6xl px-4 pt-12 pb-20 sm:px-6 lg:pb-28">
          <div className="lp-final">
            <Gnocco mood="cheering" size={112} className="mx-auto" />
            <h2 className="lp-title mx-auto mt-5 max-w-[14ch]">Diese Woche zusammen planen.</h2>
            <ol className="lp-steps">
              <li><span>1</span>Konto anlegen</li>
              <li><span>2</span>Drei Gerichte eintragen</li>
              <li><span>3</span>Die anderen per Link einladen</li>
            </ol>
            <Link href="/login?konto=neu" className="lp-btn lp-btn-ink pressable mt-8">Erste Woche planen</Link>
          </div>
        </section>
      </main>

      <footer className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 border-t border-separator px-4 py-6 text-sm text-label-2 sm:px-6">
        <span>Gnocchi · der Familien-Essensplaner</span>
        <nav className="flex gap-4">
          <Link href="/impressum" className="underline-offset-4 hover:underline">Impressum</Link>
          <Link href="/datenschutz" className="underline-offset-4 hover:underline">Datenschutz</Link>
          <Link href="/login" className="underline-offset-4 hover:underline">Anmelden</Link>
        </nav>
      </footer>
    </div>
  );
}

function Chip({ tone, children }: { tone: "tomato" | "basil"; children: React.ReactNode }) {
  return <span className={`lp-chip lp-chip-${tone}`}>{children}</span>;
}

function Tile({ className = "", tone, icon, title, children }: { className?: string; tone: "tomato" | "basil" | "plain"; icon: React.ReactNode; title: string; children: React.ReactNode }) {
  return (
    <article className={`lp-card lp-tile lp-tile-${tone} flex flex-col gap-3 p-6 sm:p-7 ${className}`}>
      <span className="lp-tile-icon">{icon}</span>
      <h3 className="text-xl leading-snug font-bold tracking-[-0.015em]">{title}</h3>
      <p className="max-w-[52ch] leading-relaxed text-label-2">{children}</p>
    </article>
  );
}
