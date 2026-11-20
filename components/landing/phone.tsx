// Der Wochen-Bildschirm der iPhone-App, nachgebaut in HTML. Zeigt Beispieldaten
// und ist nur Anschauung: für Screenreader steht eine Beschreibung bereit.

import { IconFork } from "@/components/icons";

const DAYS: [string, number, number][] = [["MO", 16, 1], ["DI", 17, 0.5], ["MI", 18, 1], ["DO", 19, 0], ["FR", 20, 0.5], ["SA", 21, 0], ["SO", 22, 0]];

function Ring({ value, size, stroke, color = "var(--g-tomato)", children }: { value: number; size: number; stroke: number; color?: string; children: React.ReactNode }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return (
    <span className="relative inline-flex shrink-0 items-center justify-center" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="absolute inset-0 -rotate-90" aria-hidden>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--g-well)" strokeWidth={stroke} />
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeDasharray={`${c * value} ${c}`} />
      </svg>
      <span className="relative">{children}</span>
    </span>
  );
}

function Meal({ label, title, detail, tone }: { label: string; title: string; detail: string; tone: string }) {
  return (
    <div className="flex items-center gap-3 py-2.5">
      <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-[13px] text-white" style={{ background: tone }}>
        <IconFork size={18} />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[0.625rem] text-[var(--g-ink-2)]">{label}</span>
        <span className="block truncate text-[0.8125rem] leading-tight font-semibold">{title}</span>
        <span className="block text-[0.625rem] text-[var(--g-ink-2)]">{detail}</span>
      </span>
      <span className="flex -space-x-1.5" aria-hidden>
        {["L", "M", "T"].map((n) => (
          <span key={n} className="flex h-5 w-5 items-center justify-center rounded-full text-[0.5rem] font-bold ring-2 ring-[var(--g-card)]" style={{ background: "var(--g-tomato-soft)" }}>{n}</span>
        ))}
      </span>
    </div>
  );
}

export function PhoneMock() {
  return (
    <div className="lp-phone" role="img" aria-label="Die Gnocchi-App auf dem iPhone: Begrüßung, 6 von 14 Mahlzeiten geplant, darunter die Gerichte für heute.">
      <div className="lp-phone-screen" aria-hidden>
        <div className="lp-phone-island" />
        <div className="flex items-start gap-2 px-4 pt-12">
          <p className="flex-1 text-[1.0625rem] leading-[1.15] font-bold tracking-[-0.02em]">
            Guten Abend, Lin.
            <br />
            <span className="text-[var(--g-ink-3)]">Heute Abend gibt es </span>
            Ofenlachs
            <span className="text-[var(--g-ink-3)]">.</span>
          </p>
          <Ring value={6 / 14} size={50} stroke={5}>
            <span className="flex flex-col items-center leading-none">
              <span className="text-sm font-bold">6</span>
              <span className="text-[0.4375rem] text-[var(--g-ink-2)]">von 14</span>
            </span>
          </Ring>
        </div>
        <div className="mx-3 mt-3.5 flex justify-between rounded-[18px] bg-[var(--g-card)] px-2 py-2 shadow-[inset_0_0_0_1px_var(--g-hairline)]">
          {DAYS.map(([d, n, v]) => (
            <span key={d} className="flex flex-col items-center gap-1">
              <span className="text-[0.4375rem] font-semibold" style={{ color: n === 16 ? "var(--g-tomato)" : "var(--g-ink-2)" }}>{d}</span>
              <Ring value={v} size={24} stroke={2.2} color={v === 1 ? "var(--g-basil)" : "var(--g-tomato)"}>
                <span className="text-[0.5625rem] font-semibold">{n}</span>
              </Ring>
            </span>
          ))}
        </div>
        <p className="mt-3.5 px-5 text-[0.6875rem] font-semibold text-[var(--g-ink-2)]">Heute, Montag</p>
        <div className="mx-3 mt-1.5 divide-y divide-[var(--g-hairline)] rounded-[20px] bg-[var(--g-card)] px-3 shadow-[inset_0_0_0_1px_var(--g-hairline)]">
          <Meal label="Mittag" title="Tomaten-Gnocchi mit Burrata" detail="Lin kocht" tone="linear-gradient(135deg,#f0603c,#c63f26)" />
          <Meal label="Abend" title="Ofenlachs mit Gemüse" detail="35 Minuten · Meli kocht" tone="linear-gradient(135deg,#f3c24f,#e08a2e)" />
        </div>
        <p className="mt-3.5 px-5 text-[0.6875rem] font-semibold text-[var(--g-ink-2)]">Dienstag</p>
        <div className="mx-3 mt-1.5 rounded-[20px] bg-[var(--g-card)] px-3 shadow-[inset_0_0_0_1px_var(--g-hairline)]">
          <Meal label="Mittag" title="Reste: Tomaten-Gnocchi" detail="Von Montag" tone="linear-gradient(135deg,#4cc38a,#2e8b57)" />
        </div>
        <div className="lp-phone-tabs">
          {["Woche", "Rezepte", "Einkauf", "Spielen", "KI"].map((t, i) => (
            <span key={t} className={i === 0 ? "text-[var(--g-tomato)]" : ""}>{t}</span>
          ))}
        </div>
      </div>
    </div>
  );
}
