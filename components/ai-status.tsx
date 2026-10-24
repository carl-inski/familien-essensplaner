"use client";

// KI-Status und -Verbrauch (aus /api/ai/status). Ohne Schlüssel: „noch nicht eingerichtet“.

import { useCallback, useEffect, useState } from "react";
import { IconSparkles } from "@/components/icons";
import { useToast } from "@/components/toast";
import { Section } from "@/components/ui";
import { formatEur } from "@/lib/ai/cost";

export interface AiStatus {
  enabled: boolean;
  reason: string | null;
  provider: string;
  models: { text: string; vision: string; strong: string } | null;
  limits: { dailyCallsPerMember: number; monthlyBudgetEur: number };
  usage: { month_calls: number; month_cache_hits: number; month_cost_eur: number; my_calls_today: number };
}

export function useAiStatus() {
  const [status, setStatus] = useState<AiStatus | null>(null);
  const reload = useCallback(async () => {
    const res = await fetch("/api/ai/status", { cache: "no-store" });
    if (res.ok) setStatus(await res.json());
  }, []);
  useEffect(() => {
    let alive = true;
    fetch("/api/ai/status", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .then((s) => alive && s && setStatus(s));
    return () => {
      alive = false;
    };
  }, []);
  return { status, reload };
}

export function AiUsageSection() {
  const { status, reload } = useAiStatus();
  const toast = useToast();
  const [testing, setTesting] = useState(false);
  if (!status) return null;

  async function test() {
    setTesting(true);
    const res = await fetch("/api/ai/test", { method: "POST" });
    const body = await res.json().catch(() => ({}));
    setTesting(false);
    toast(res.ok ? { text: `${body.text} (${(body.ms / 1000).toFixed(1).replace(".", ",")} s)` } : { text: body.error ?? "Test fehlgeschlagen", tone: "error" });
    void reload();
  }

  const u = status.usage;
  const share = Math.min(1, u.month_cost_eur / Math.max(status.limits.monthlyBudgetEur, 0.0001));
  return (
    <Section
      title="KI"
      footer={
        status.enabled
          ? `Höchstens ${status.limits.dailyCallsPerMember} Anfragen pro Person und Tag, Budget ${formatEur(status.limits.monthlyBudgetEur)} pro Monat.`
          : "Sobald ein API-Schlüssel in Vercel hinterlegt ist, schaltet sich die KI hier frei."
      }
    >
      <div className="card px-4 py-3">
        <div className="flex items-center gap-3">
          <span style={{ color: status.enabled ? "var(--accent)" : "var(--label-3)" }}><IconSparkles /></span>
          <div className="min-w-0 flex-1">
            <p className="t-sub font-semibold">{status.enabled ? "Eingerichtet" : "KI noch nicht eingerichtet"}</p>
            <p className="t-footnote truncate" style={{ color: "var(--label-2)" }}>
              {status.enabled ? `${status.models?.text}${status.provider === "mock" ? " · Testmodus" : ""}` : status.reason}
            </p>
          </div>
          {status.enabled && (
            <button className="btn btn-gray btn-sm pressable" disabled={testing} onClick={test}>{testing ? "Teste …" : "Testen"}</button>
          )}
        </div>
        {status.enabled && (
          <>
            <div className="mt-3 grid grid-cols-3 gap-2">
              <Stat value={String(u.month_calls)} label="Anfragen im Monat" />
              <Stat value={formatEur(u.month_cost_eur)} label="Kosten im Monat" />
              <Stat value={String(u.month_cache_hits)} label="aus dem Cache" />
            </div>
            <div className="mt-3 h-1.5 overflow-hidden rounded-full" style={{ background: "var(--fill)" }} role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(share * 100)} aria-label="Anteil vom Monatsbudget">
              <div className="h-full rounded-full" style={{ width: `${Math.max(share * 100, u.month_cost_eur > 0 ? 2 : 0)}%`, background: share > 0.8 ? "var(--red)" : "var(--accent)" }} />
            </div>
            <p className="t-caption mt-1" style={{ color: "var(--label-2)" }}>Du heute: {u.my_calls_today} von {status.limits.dailyCallsPerMember}</p>
          </>
        )}
      </div>
    </Section>
  );
}

function Stat({ value, label }: { value: string; label: string }) {
  return (
    <div>
      <p className="t-headline tabular-nums">{value}</p>
      <p className="t-caption" style={{ color: "var(--label-2)" }}>{label}</p>
    </div>
  );
}
