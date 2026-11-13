"use client";

// Daten für den Einkauf über Wochengrenzen: kommende Gerichte, Anwesenheit und
// die freie „Noch offen“-Liste, live gehalten über Realtime.

import { useCallback, useEffect, useRef, useState } from "react";
import { useApp } from "@/components/app-data";
import { addDays } from "@/lib/dates";
import { STOCK_DAYS, type NewPurchase, type Purchase } from "@/lib/shopping";
import type { Attendance, MealPlanEntry } from "@/lib/types";

/** So weit voraus zeigt die Liste geplante Gerichte */
export const HORIZON_DAYS = 42;

export interface ShoppingExtra {
  id: string;
  text: string;
  aisle: string | null;
  carried: boolean;
  created_at: string;
}

/** ok = alles gesichert, saving = unterwegs, offline = wartet auf Netz und wird nachgeholt */
export type SyncState = "ok" | "saving" | "offline";

type Job = { kind: "buy"; rows: NewPurchase[] } | { kind: "undo"; clientIds: string[] };

export function useShopping() {
  const { sb, members, today } = useApp();
  const [purchases, setPurchases] = useState<Purchase[]>([]);
  const [sync, setSync] = useState<SyncState>("ok");
  const [plan, setPlan] = useState<MealPlanEntry[]>([]);
  const [attendance, setAttendance] = useState<Attendance[]>([]);
  const [extras, setExtras] = useState<ShoppingExtra[]>([]);
  const [loaded, setLoaded] = useState(false);
  const to = addDays(today, HORIZON_DAYS);

  const fetchAll = useCallback(async () => {
    const [p, a, x, k] = await Promise.all([
      sb.from("ep_meal_plan").select("*").gte("date", today).lte("date", to),
      sb.from("ep_attendance").select("*").gte("date", today).lte("date", to).in("member_id", members.map((m) => m.id)),
      sb.from("ep_shopping_extra").select("id, text, aisle, carried, created_at").order("created_at"),
      sb.from("ep_purchases").select("*").gte("bought_at", `${addDays(today, -STOCK_DAYS - 1)}T00:00:00Z`).order("bought_at"),
    ]);
    return {
      plan: (p.data ?? []) as MealPlanEntry[],
      attendance: (a.data ?? []) as Attendance[],
      extras: (x.data ?? []) as ShoppingExtra[],
      // amount kommt als Text (numeric) – in Zahlen wandeln
      purchases: ((k.data ?? []) as Purchase[]).map((r) => ({ ...r, amount: r.amount === null ? null : Number(r.amount) })),
      failed: !!(p.error || k.error),
    };
  }, [sb, members, today, to]);

  // Eigene Schreibvorgänge laufen nacheinander. Solange welche warten, überschreibt kein
  // Server-Stand das, was hier schon abgehakt ist.
  const queue = useRef<Job[]>([]);
  const running = useRef(false);
  const stale = useRef(false);

  const apply = useCallback((d: Awaited<ReturnType<typeof fetchAll>>) => {
    if (d.failed) return; // Netz weg: letzten Stand behalten
    setPlan(d.plan);
    setAttendance(d.attendance);
    setExtras(d.extras);
    if (queue.current.length || running.current) stale.current = true;
    else setPurchases(d.purchases);
    setLoaded(true);
  }, []);

  const reload = useCallback(async () => apply(await fetchAll()), [fetchAll, apply]);

  const flush = useCallback(async () => {
    if (running.current) return;
    running.current = true;
    while (queue.current.length) {
      const job = queue.current[0];
      setSync("saving");
      const { error } =
        job.kind === "buy"
          ? await sb.from("ep_purchases").upsert(job.rows, { onConflict: "client_id", ignoreDuplicates: true })
          : await sb.from("ep_purchases").delete().in("client_id", job.clientIds);
      // Von der Datenbank abgelehnt (hat einen Fehlercode): Wiederholen hilft nicht – verwerfen,
      // der frische Stand unten nimmt den Haken wieder zurück.
      if (error && !error.code) {
        // Kein Netz oder Server nicht erreichbar: stehen lassen, später noch einmal
        running.current = false;
        setSync("offline");
        return;
      }
      queue.current.shift();
    }
    running.current = false;
    setSync("ok");
    stale.current = false;
    await reload();
  }, [sb, reload]);

  /** Abhaken: sofort sichtbar, im Hintergrund gesichert. Liefert die client_ids fürs Zurücknehmen. */
  const buy = useCallback(
    (rows: NewPurchase[]): string[] => {
      if (!rows.length) return [];
      const at = new Date().toISOString();
      setPurchases((cur) => [...cur, ...rows.map((r) => ({ ...r, id: `tmp-${r.client_id}`, bought_at: at }))]);
      queue.current.push({ kind: "buy", rows });
      void flush();
      return rows.map((r) => r.client_id);
    },
    [flush],
  );

  /** Käufe zurücknehmen (Haken entfernen, Rückgängig, „aufgebraucht“) */
  const undo = useCallback(
    (clientIds: string[]) => {
      if (!clientIds.length) return;
      const gone = new Set(clientIds);
      setPurchases((cur) => cur.filter((p) => !gone.has(p.client_id)));
      queue.current.push({ kind: "undo", clientIds });
      void flush();
    },
    [flush],
  );

  useEffect(() => {
    let alive = true;
    fetchAll().then((d) => alive && apply(d));
    const channel = sb
      // eigener Name je Nutzung: Liste, Planänderung und KI-Karte können gleichzeitig offen sein
      .channel(`ep-shopping-${Math.random().toString(36).slice(2)}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_meal_plan" }, () => void reload())
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_attendance" }, () => void reload())
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_shopping_extra" }, () => void reload())
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_purchases" }, () => void reload())
      .subscribe();
    // Zurück in der App oder wieder Netz: Wartendes nachholen, dann frisch laden
    const onFocus = () => void (queue.current.length ? flush() : reload());
    window.addEventListener("focus", onFocus);
    window.addEventListener("online", onFocus);
    const retry = setInterval(() => queue.current.length && void flush(), 8000);
    return () => {
      alive = false;
      void sb.removeChannel(channel);
      window.removeEventListener("focus", onFocus);
      window.removeEventListener("online", onFocus);
      clearInterval(retry);
    };
  }, [sb, fetchAll, apply, reload, flush]);

  return { plan, attendance, extras, purchases, sync, loaded, reload, setExtras, buy, undo };
}
