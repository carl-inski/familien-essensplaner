"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useApp } from "@/components/app-data";
import { daysFrom } from "@/lib/dates";
import type { Attendance, AttendanceStatus, MealPlanEntry, Meal } from "@/lib/types";

export { MEALS } from "@/lib/meals";

/** Sieben Tage ab `start` (Planansicht beginnt mit heute) */
export function useWeek(start: string) {
  const { sb, household, members } = useApp();
  const dates = useMemo(() => daysFrom(start), [start]);
  const [attendance, setAttendance] = useState<Attendance[]>([]);
  const [plan, setPlan] = useState<MealPlanEntry[]>([]);
  const [loadedFor, setLoadedFor] = useState<string | null>(null);
  const from = dates[0];
  const to = dates[6];

  const fetchWeek = useCallback(async () => {
    const memberIds = members.map((m) => m.id);
    const [a, p] = await Promise.all([
      sb.from("ep_attendance").select("*").gte("date", from).lte("date", to).in("member_id", memberIds),
      sb.from("ep_meal_plan").select("*").gte("date", from).lte("date", to),
    ]);
    return { attendance: (a.data ?? []) as Attendance[], plan: (p.data ?? []) as MealPlanEntry[] };
  }, [sb, members, from, to]);

  const apply = useCallback(
    (data: { attendance: Attendance[]; plan: MealPlanEntry[] }) => {
      setAttendance(data.attendance);
      setPlan(data.plan);
      setLoadedFor(from);
    },
    [from],
  );

  // Eigene Schreibvorgänge laufen nacheinander; solange einer unterwegs ist, wird kein
  // (möglicherweise veralteter) Server-Stand über den optimistischen Zustand gelegt.
  const queue = useRef<Promise<unknown>>(Promise.resolve());
  const pending = useRef(0);
  const stale = useRef(false);
  // Zählt eigene Schreibvorgänge: eine Antwort, deren Abfrage vor einem Schreiben startete, ist veraltet
  const writeGen = useRef(0);

  const load = useCallback(async () => {
    for (;;) {
      const gen = writeGen.current;
      const data = await fetchWeek();
      if (pending.current > 0) {
        stale.current = true;
        return;
      }
      if (gen === writeGen.current) {
        apply(data);
        return;
      }
      // während der Abfrage wurde geschrieben → neu abfragen
    }
  }, [apply, fetchWeek]);

  const enqueue = useCallback(
    <T,>(fn: () => PromiseLike<T>): Promise<T> => {
      pending.current += 1;
      writeGen.current += 1;
      const run = queue.current.then(() => fn());
      queue.current = run
        .catch(() => undefined)
        .then(() => {
          pending.current -= 1;
          if (pending.current === 0 && stale.current) {
            stale.current = false;
            void load();
          }
        });
      return run;
    },
    [load],
  );

  useEffect(() => {
    let cancelled = false;
    const gen = writeGen.current;
    fetchWeek().then((data) => !cancelled && pending.current === 0 && gen === writeGen.current && apply(data));
    return () => {
      cancelled = true;
    };
  }, [fetchWeek, apply]);

  // Realtime: Änderungen anderer erscheinen ohne Reload
  useEffect(() => {
    const channel = sb
      .channel(`ep-week-${from}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_attendance" }, () => void load())
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_meal_plan" }, () => void load())
      .subscribe();
    const onFocus = () => void load();
    window.addEventListener("focus", onFocus);
    return () => {
      void sb.removeChannel(channel);
      window.removeEventListener("focus", onFocus);
    };
  }, [sb, from, load]);

  const setStatus = useCallback(
    async (memberId: string, date: string, meal: Meal, status: AttendanceStatus, guests = 0) => {
      // optimistisch
      setAttendance((cur) => {
        const rest = cur.filter((a) => !(a.member_id === memberId && a.date === date && a.meal === meal));
        return [...rest, { id: `tmp-${memberId}-${date}-${meal}`, member_id: memberId, date, meal, status, guests }];
      });
      stale.current = true; // nach dem Schreiben einmal frisch laden
      const { error } = await enqueue(() =>
        sb.from("ep_attendance").upsert({ member_id: memberId, date, meal, status, guests: status === "weg" ? 0 : guests }, { onConflict: "member_id,date,meal" }),
      );
      return error;
    },
    [sb, enqueue],
  );

  const upsertSlot = useCallback(
    async (date: string, meal: Meal, patch: Partial<MealPlanEntry>) => {
      const existing = plan.find((p) => p.date === date && p.meal === meal);
      setPlan((cur) => {
        if (existing) return cur.map((p) => (p.id === existing.id ? { ...p, ...patch } : p));
        return [
          ...cur,
          { id: `tmp-${date}-${meal}`, household_id: household.id, date, meal, recipe_id: null, leftover_of: null, cook_id: null, cook2_id: null, servings_override: null, status: "geplant", note: null, ...patch },
        ];
      });
      stale.current = true;
      const { data, error } = await enqueue(() =>
        sb
          .from("ep_meal_plan")
          .upsert({ household_id: household.id, date, meal, ...stripLocal(patch) }, { onConflict: "household_id,date,meal" })
          .select()
          .single(),
      );
      if (error) return { error, entry: null };
      if (pending.current === 0) setPlan((cur) => [...cur.filter((p) => !(p.date === date && p.meal === meal)), data as MealPlanEntry]);
      return { error: null, entry: data as MealPlanEntry };
    },
    [sb, plan, household.id, enqueue],
  );

  return { dates, attendance, plan, loaded: loadedFor === from, setStatus, upsertSlot, reload: load };
}

function stripLocal(patch: Partial<MealPlanEntry>) {
  const { id: _id, household_id: _h, ...rest } = patch;
  void _id;
  void _h;
  return rest;
}
