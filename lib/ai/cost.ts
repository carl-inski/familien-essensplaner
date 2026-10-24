// Kostenschätzung pro KI-Aufruf und Prüfung der Limits (rein, ohne I/O).

import type { AiConfig, AiPrices } from "./config";

export interface TokenUsage {
  inputTokens?: number;
  outputTokens?: number;
  /** aus dem Prompt-Cache gelesen (0,1 × Eingabepreis) */
  cacheReadTokens?: number;
  /** in den Prompt-Cache geschrieben (1,25 × Eingabepreis) */
  cacheWriteTokens?: number;
}

export function estimateCostEur(u: TokenUsage, p: AiPrices): number {
  const read = u.cacheReadTokens ?? 0;
  const write = u.cacheWriteTokens ?? 0;
  const plainIn = Math.max(0, (u.inputTokens ?? 0) - read - write);
  const usd = (plainIn * p.inUsdPerM + read * p.inUsdPerM * 0.1 + write * p.inUsdPerM * 1.25 + (u.outputTokens ?? 0) * p.outUsdPerM) / 1_000_000;
  return Math.round(usd * p.usdToEur * 1e6) / 1e6;
}

export interface UsageSoFar {
  /** eigene Aufrufe heute, ohne Cache-Treffer */
  callsToday: number;
  /** Kosten des Haushalts im laufenden Monat */
  costMonthEur: number;
}

/** Meldung, wenn ein Limit erreicht ist, sonst null */
export function limitMessage(usage: UsageSoFar, limits: AiConfig["limits"]): string | null {
  if (usage.costMonthEur >= limits.monthlyBudgetEur) {
    return `Das KI-Budget für diesen Monat (${formatEur(limits.monthlyBudgetEur)}) ist aufgebraucht. Ab dem 1. geht es weiter.`;
  }
  if (usage.callsToday >= limits.dailyCallsPerMember) {
    return `Du hast heute schon ${limits.dailyCallsPerMember} KI-Anfragen gestellt. Morgen geht es weiter.`;
  }
  return null;
}

export function formatEur(n: number): string {
  return new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR", minimumFractionDigits: 2, maximumFractionDigits: n > 0 && n < 0.01 ? 4 : 2 }).format(n);
}
