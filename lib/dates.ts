// Datumshilfen. Alle Datumswerte sind lokale Kalendertage "YYYY-MM-DD" (Europe/Berlin).

import type { WeekdayKey } from "./types";

export const WEEKDAY_KEYS: WeekdayKey[] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
export const WEEKDAY_SHORT = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];
export const WEEKDAY_LONG = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"];

function pad(n: number) {
  return String(n).padStart(2, "0");
}

export function toISODate(d: Date): string {
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

export function parseISODate(s: string): Date {
  const [y, m, d] = s.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

/** Heutiges Datum in Berlin */
export function todayBerlin(now: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Berlin", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}

export function addDays(date: string, days: number): string {
  const d = parseISODate(date);
  d.setUTCDate(d.getUTCDate() + days);
  return toISODate(d);
}

/** 0 = Montag … 6 = Sonntag */
export function weekdayIndex(date: string): number {
  return (parseISODate(date).getUTCDay() + 6) % 7;
}

export function daysBetween(a: string, b: string): number {
  return Math.round((parseISODate(b).getTime() - parseISODate(a).getTime()) / 86400000);
}

export function isoWeekOf(date: string): { year: number; week: number } {
  const d = parseISODate(date);
  const day = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - day + 3); // Donnerstag derselben Woche
  const year = d.getUTCFullYear();
  const firstThursday = new Date(Date.UTC(year, 0, 4));
  const fDay = (firstThursday.getUTCDay() + 6) % 7;
  firstThursday.setUTCDate(firstThursday.getUTCDate() - fDay + 3);
  const week = 1 + Math.round((d.getTime() - firstThursday.getTime()) / (7 * 86400000));
  return { year, week };
}

export function isoWeekString(date: string): string {
  const { year, week } = isoWeekOf(date);
  return `${year}-W${pad(week)}`;
}

export function mondayOfIsoWeek(isoWeek: string): string {
  const m = isoWeek.match(/^(\d{4})-W(\d{2})$/);
  if (!m) throw new Error(`Ungültige Kalenderwoche: ${isoWeek}`);
  const year = Number(m[1]);
  const week = Number(m[2]);
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const day = (jan4.getUTCDay() + 6) % 7;
  jan4.setUTCDate(jan4.getUTCDate() - day + (week - 1) * 7);
  return toISODate(jan4);
}

export function weekDates(isoWeek: string): string[] {
  const monday = mondayOfIsoWeek(isoWeek);
  return Array.from({ length: 7 }, (_, i) => addDays(monday, i));
}

export function shiftWeek(isoWeek: string, delta: number): string {
  return isoWeekString(addDays(mondayOfIsoWeek(isoWeek), delta * 7));
}

export function formatDateDE(date: string, opts: Intl.DateTimeFormatOptions = { day: "2-digit", month: "2-digit", year: "numeric" }): string {
  return parseISODate(date).toLocaleDateString("de-DE", { ...opts, timeZone: "UTC" });
}

export function weekNumberLabel(isoWeek: string): string {
  return `KW ${Number(isoWeek.slice(6))}`;
}

/** „Aktuelle Woche“, „Nächste Woche“, „Letzte Woche“ – sonst „KW 45“ */
export function relativeWeekLabel(isoWeek: string, today: string): string {
  const diff = Math.round(daysBetween(mondayOfIsoWeek(isoWeekString(today)), mondayOfIsoWeek(isoWeek)) / 7);
  if (diff === 0) return "Aktuelle Woche";
  if (diff === 1) return "Nächste Woche";
  if (diff === -1) return "Letzte Woche";
  return weekNumberLabel(isoWeek);
}
