"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useApp } from "@/components/app-data";
import { weekDates } from "@/lib/dates";
import type { Attendance, AttendanceStatus, MealPlanEntry, Meal } from "@/lib/types";

export const MEAL: Meal = "abend"; // MVP: nur Abendessen sichtbar

export function useWeek(isoWeek: string) {
  const { sb, household, members } = useApp();
  const dates = useMemo(() => weekDates(isoWeek), [isoWeek]);
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

  const load = useCallback(async () => apply(await fetchWeek()), [apply, fetchWeek]);

  useEffect(() => {
    let cancelled = false;
    fetchWeek().then((data) => !cancelled && apply(data));
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
    async (memberId: string, date: string, status: AttendanceStatus, guests = 0) => {
      // optimistisch
      setAttendance((cur) => {
        const rest = cur.filter((a) => !(a.member_id === memberId && a.date === date && a.meal === MEAL));
        return [...rest, { id: `tmp-${memberId}-${date}`, member_id: memberId, date, meal: MEAL, status, guests }];
      });
      const { error } = await sb
        .from("ep_attendance")
        .upsert({ member_id: memberId, date, meal: MEAL, status, guests: status === "weg" ? 0 : guests }, { onConflict: "member_id,date,meal" });
      if (error) await load();
      return error;
    },
    [sb, load],
  );

  const upsertSlot = useCallback(
    async (date: string, patch: Partial<MealPlanEntry>) => {
      const existing = plan.find((p) => p.date === date && p.meal === MEAL);
      setPlan((cur) => {
        if (existing) return cur.map((p) => (p.id === existing.id ? { ...p, ...patch } : p));
        return [
          ...cur,
          { id: `tmp-${date}`, household_id: household.id, date, meal: MEAL, recipe_id: null, leftover_of: null, cook_id: null, cook2_id: null, servings_override: null, status: "geplant", note: null, ...patch },
        ];
      });
      const { data, error } = await sb
        .from("ep_meal_plan")
        .upsert({ household_id: household.id, date, meal: MEAL, ...stripLocal(patch) }, { onConflict: "household_id,date,meal" })
        .select()
        .single();
      if (error) {
        await load();
        return { error, entry: null };
      }
      setPlan((cur) => [...cur.filter((p) => !(p.date === date && p.meal === MEAL)), data as MealPlanEntry]);
      return { error: null, entry: data as MealPlanEntry };
    },
    [sb, plan, household.id, load],
  );

  return { dates, attendance, plan, loaded: loadedFor === from, setStatus, upsertSlot, reload: load };
}

function stripLocal(patch: Partial<MealPlanEntry>) {
  const { id: _id, household_id: _h, ...rest } = patch;
  void _id;
  void _h;
  return rest;
}
