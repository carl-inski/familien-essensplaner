"use client";

// Offene Runden der Familie (Lobby oder mitten im Spiel), live.

import { useCallback, useEffect, useState } from "react";
import { useApp } from "@/components/app-data";
import type { DecideSession } from "@/lib/decide";

/** Vergessene Runden (zwei Stunden ohne Bewegung) zählen nicht mehr – wie in ep_decide_create */
const MAX_AGE_MS = 2 * 60 * 60 * 1000;

export function useOpenSessions(): DecideSession[] {
  const { sb } = useApp();
  const [sessions, setSessions] = useState<DecideSession[]>([]);

  const fetchOpen = useCallback(async () => {
    const { data } = await sb
      .from("ep_decide_sessions")
      .select("*")
      .in("status", ["lobby", "playing"])
      .gte("updated_at", new Date(Date.now() - MAX_AGE_MS).toISOString())
      .order("created_at", { ascending: false });
    return (data ?? []) as DecideSession[];
  }, [sb]);

  useEffect(() => {
    let cancelled = false;
    const load = () => fetchOpen().then((list) => !cancelled && setSessions(list));
    void load();
    // eigener Kanalname je Nutzung: die Liste und der Hinweis oben hören beide zu
    const channel = sb
      .channel(`ep-decide-open-${Math.random().toString(36).slice(2)}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_decide_sessions" }, () => void load())
      .subscribe();
    const onFocus = () => document.visibilityState === "visible" && void load();
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onFocus);
    const poll = setInterval(onFocus, 20000);
    return () => {
      cancelled = true;
      void sb.removeChannel(channel);
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onFocus);
      clearInterval(poll);
    };
  }, [sb, fetchOpen]);

  return sessions;
}
