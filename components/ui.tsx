"use client";

import type { ReactNode } from "react";
import { formatDateDE } from "@/lib/dates";
import type { CookStats, Diet, Member, Recipe } from "@/lib/types";
import { IconFish, IconLeaf, IconMeat, IconMinus, IconPlus } from "./icons";

const AVATAR_HUES = [24, 205, 140, 280, 340, 50, 180];

export function memberHue(member: Member): number {
  return AVATAR_HUES[member.position % AVATAR_HUES.length];
}

export function Avatar({ member, size = 32, dim = false }: { member: Member; size?: number; dim?: boolean }) {
  const hue = memberHue(member);
  return (
    <span
      className="inline-flex shrink-0 items-center justify-center rounded-full font-semibold"
      style={{
        width: size,
        height: size,
        fontSize: size * 0.42,
        background: dim ? "var(--fill)" : `hsl(${hue} 70% 50%)`,
        color: dim ? "var(--label-3)" : "#fff",
      }}
      aria-hidden
    >
      {member.name.slice(0, 1)}
    </span>
  );
}

export const DIET_LABEL: Record<Diet, string> = { fleisch: "Fleisch", fisch: "Fisch", vegetarisch: "Vegetarisch" };

export function DietIcon({ diet, size = 16 }: { diet: Diet | null; size?: number }) {
  if (diet === "fisch") return <IconFish size={size} style={{ color: "#0a84ff" }} aria-label="Fisch" />;
  if (diet === "fleisch") return <IconMeat size={size} style={{ color: "#c2410c" }} aria-label="Fleisch" />;
  if (diet === "vegetarisch") return <IconLeaf size={size} style={{ color: "#16a34a" }} aria-label="Vegetarisch" />;
  return null;
}

const PLACEHOLDER_HUES: Record<string, number> = { fleisch: 18, fisch: 205, vegetarisch: 120 };

/** Foto oder ruhiger Farbverlauf mit Initiale als Platzhalter */
export function RecipeImage({ recipe, className = "", rounded = 12 }: { recipe: Pick<Recipe, "title" | "image_url" | "diet">; className?: string; rounded?: number }) {
  if (recipe.image_url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={recipe.image_url} alt="" className={`object-cover ${className}`} style={{ borderRadius: rounded }} loading="lazy" />;
  }
  const hue = PLACEHOLDER_HUES[recipe.diet ?? ""] ?? 30;
  return (
    <div
      className={`flex items-center justify-center ${className}`}
      style={{
        borderRadius: rounded,
        background: `linear-gradient(140deg, hsl(${hue} 70% 62%), hsl(${hue + 25} 65% 45%))`,
      }}
      aria-hidden
    >
      <span className="font-semibold text-white/90" style={{ fontSize: "1.75em", letterSpacing: "-0.02em" }}>
        {recipe.title.slice(0, 1)}
      </span>
    </div>
  );
}

export function lastCookedLabel(stats: CookStats | undefined): string {
  if (!stats) return "noch nie gekocht";
  return `zuletzt gekocht am ${formatDateDE(stats.last_cooked_on)} · ${stats.times_cooked}×`;
}

export function Stepper({ value, onChange, min = 0, max = 99, label }: { value: number; onChange: (v: number) => void; min?: number; max?: number; label: string }) {
  return (
    <div className="inline-flex items-center rounded-full" style={{ background: "var(--fill)" }} role="group" aria-label={label}>
      <button className="pressable flex h-9 w-10 items-center justify-center" aria-label={`${label} verringern`} disabled={value <= min} onClick={() => onChange(Math.max(min, value - 1))}>
        <IconMinus size={18} />
      </button>
      <span className="t-headline min-w-7 text-center tabular-nums" aria-live="polite">{value}</span>
      <button className="pressable flex h-9 w-10 items-center justify-center" aria-label={`${label} erhöhen`} disabled={value >= max} onClick={() => onChange(Math.min(max, value + 1))}>
        <IconPlus size={18} />
      </button>
    </div>
  );
}

export function Section({ title, children, footer, trailing }: { title?: string; children: ReactNode; footer?: ReactNode; trailing?: ReactNode }) {
  return (
    <section className="mt-6">
      {(title || trailing) && (
        <div className="mb-1.5 flex items-end justify-between px-4">
          {title && <h2 className="t-section">{title}</h2>}
          {trailing}
        </div>
      )}
      {children}
      {footer && <p className="t-footnote mt-1.5 px-4" style={{ color: "var(--label-2)" }}>{footer}</p>}
    </section>
  );
}

export function Empty({ title, text, action }: { title: string; text?: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-12 text-center">
      <p className="t-headline">{title}</p>
      {text && <p className="t-sub" style={{ color: "var(--label-2)" }}>{text}</p>}
      {action && <div className="mt-2">{action}</div>}
    </div>
  );
}

export function Segmented<T extends string>({ value, options, onChange, label }: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void; label: string }) {
  return (
    <div className="segmented" role="radiogroup" aria-label={label}>
      {options.map((o) => (
        <button key={o.value} role="radio" aria-checked={value === o.value} data-on={value === o.value} className="pressable" onClick={() => onChange(o.value)}>
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function downloadText(filename: string, text: string, type = "text/markdown") {
  const blob = new Blob([text], { type: `${type};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
