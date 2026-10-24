"use client";

// Daten für den Einkauf über Wochengrenzen: kommende Gerichte, Anwesenheit und
// die freie „Noch offen“-Liste, live gehalten über Realtime.

import { useCallback, useEffect, useState } from "react";
import { useApp } from "@/components/app-data";
import { addDays } from "@/lib/dates";
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

export function useShopping() {
  const { sb, members, today } = useApp();
  const [plan, setPlan] = useState<MealPlanEntry[]>([]);
  const [attendance, setAttendance] = useState<Attendance[]>([]);
  const [extras, setExtras] = useState<ShoppingExtra[]>([]);
  const [loaded, setLoaded] = useState(false);
  const to = addDays(today, HORIZON_DAYS);

  const fetchAll = useCallback(async () => {
    const [p, a, x] = await Promise.all([
      sb.from("ep_meal_plan").select("*").gte("date", today).lte("date", to),
      sb.from("ep_attendance").select("*").gte("date", today).lte("date", to).in("member_id", members.map((m) => m.id)),
      sb.from("ep_shopping_extra").select("id, text, aisle, carried, created_at").order("created_at"),
    ]);
    return { plan: (p.data ?? []) as MealPlanEntry[], attendance: (a.data ?? []) as Attendance[], extras: (x.data ?? []) as ShoppingExtra[] };
  }, [sb, members, today, to]);

  const reload = useCallback(async () => {
    const d = await fetchAll();
    setPlan(d.plan);
    setAttendance(d.attendance);
    setExtras(d.extras);
    setLoaded(true);
  }, [fetchAll]);

  useEffect(() => {
    let alive = true;
    fetchAll().then((d) => {
      if (!alive) return;
      setPlan(d.plan);
      setAttendance(d.attendance);
      setExtras(d.extras);
      setLoaded(true);
    });
    const channel = sb
      .channel("ep-shopping")
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_meal_plan" }, () => void reload())
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_attendance" }, () => void reload())
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_shopping_extra" }, () => void reload())
      .subscribe();
    const onFocus = () => void reload();
    window.addEventListener("focus", onFocus);
    return () => {
      alive = false;
      void sb.removeChannel(channel);
      window.removeEventListener("focus", onFocus);
    };
  }, [sb, fetchAll, reload]);

  return { plan, attendance, extras, loaded, reload, setExtras };
}
