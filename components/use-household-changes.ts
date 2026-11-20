"use client";

// Live-Änderungen einer Familie. Ein einziger privater Broadcast-Kanal je Familie
// (`ep:household:<id>`, Migration 20261119100000_realtime_haushalt.sql) statt
// ungefilterter postgres_changes auf ganzen Tabellen: Supabase muss so nicht mehr
// jede Änderung jeder Familie gegen jedes verbundene Gerät prüfen.
//
// Ist die Migration noch nicht eingespielt (Kanal wird abgelehnt), fällt der Hook auf
// gefilterte postgres_changes zurück – Einfügen und Ändern nur der eigenen Familie.

import { useEffect, useRef } from "react";
import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import { useApp } from "@/components/app-data";

export type LiveTable =
  | "ep_meal_plan"
  | "ep_attendance"
  | "ep_pantry"
  | "ep_purchases"
  | "ep_shopping_extra"
  | "ep_cooking_history"
  | "ep_decide_sessions"
  | "ep_decide_players";

type Listener = (table: string) => void;

interface Shared {
  channel: RealtimeChannel;
  listeners: Set<Listener>;
  fallback: RealtimeChannel | null;
  memberIds: string[];
}

// Ein Kanal je Client und Familie; supabase-js gibt für dasselbe Thema denselben Kanal zurück,
// darum zählen wir die Nutzer selbst und schließen erst, wenn der letzte geht.
const shared = new WeakMap<SupabaseClient, Map<string, Shared>>();

const ALL_TABLES: LiveTable[] = [
  "ep_meal_plan", "ep_attendance", "ep_pantry", "ep_purchases",
  "ep_shopping_extra", "ep_cooking_history", "ep_decide_sessions",
];

function startFallback(sb: SupabaseClient, householdId: string, entry: Shared) {
  if (entry.fallback) return;
  const notify = (table: string) => () => entry.listeners.forEach((l) => l(table));
  let ch = sb.channel(`ep-fallback-${householdId}-${Math.random().toString(36).slice(2)}`);
  for (const table of ALL_TABLES) {
    const filter = table === "ep_attendance"
      ? entry.memberIds.length ? `member_id=in.(${entry.memberIds.slice(0, 100).join(",")})` : null
      : `household_id=eq.${householdId}`;
    if (!filter) continue;
    for (const event of ["INSERT", "UPDATE"] as const) {
      ch = ch.on("postgres_changes", { event, schema: "public", table, filter }, notify(table));
    }
  }
  entry.fallback = ch.subscribe();
}

export function subscribeHousehold(sb: SupabaseClient, householdId: string, memberIds: string[], listener: Listener) {
  let byHousehold = shared.get(sb);
  if (!byHousehold) shared.set(sb, (byHousehold = new Map()));
  let entry = byHousehold.get(householdId);
  if (!entry) {
    const channel = sb.channel(`ep:household:${householdId}`, { config: { private: true } });
    const created: Shared = { channel, listeners: new Set(), fallback: null, memberIds };
    entry = created;
    channel
      .on("broadcast", { event: "change" }, ({ payload }) => {
        const table = typeof payload?.table === "string" ? payload.table : "";
        created.listeners.forEach((l) => l(table));
      })
      .subscribe((status) => {
        if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") startFallback(sb, householdId, created);
      });
    byHousehold.set(householdId, entry);
  }
  entry.memberIds = memberIds;
  entry.listeners.add(listener);
  const current = entry;
  return () => {
    current.listeners.delete(listener);
    if (current.listeners.size) return;
    byHousehold!.delete(householdId);
    void sb.removeChannel(current.channel);
    if (current.fallback) void sb.removeChannel(current.fallback);
  };
}

/**
 * Ruft `onChange` (gebündelt, höchstens alle `waitMs`) auf, wenn sich eine der Tabellen
 * in der aktiven Familie ändert. Ein Einkauf mit 30 Haken löst so ein Nachladen aus, nicht 30.
 */
export function useHouseholdChanges(tables: readonly LiveTable[], onChange: () => void, waitMs = 250) {
  const { sb, household, members } = useApp();
  const latest = useRef(onChange);
  useEffect(() => {
    latest.current = onChange;
  });
  const key = tables.join(",");
  const memberKey = members.map((m) => m.id).join(",");

  useEffect(() => {
    const wanted = new Set(key.split(","));
    let timer: ReturnType<typeof setTimeout> | null = null;
    const release = subscribeHousehold(sb, household.id, memberKey ? memberKey.split(",") : [], (table) => {
      if (table && !wanted.has(table)) return;
      if (timer) return;
      timer = setTimeout(() => {
        timer = null;
        latest.current();
      }, waitMs);
    });
    return () => {
      if (timer) clearTimeout(timer);
      release();
    };
  }, [sb, household.id, key, memberKey, waitMs]);
}
