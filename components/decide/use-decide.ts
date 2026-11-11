"use client";

// Eine Entscheiden-Runde live: Stand laden, über Realtime (und zur Sicherheit im Takt)
// aktuell halten, eigene Abgaben schreiben – und weiterschalten, sobald alle fertig sind.

import { useCallback, useEffect, useRef, useState } from "react";
import { useApp } from "@/components/app-data";
import { advance, initialState, roundSubmissions, type DecidePlayer, type DecideSession, type DecideState } from "@/lib/decide";

const POLL_MS = 3000;

export function useDecide(id: string) {
  const { sb, me } = useApp();
  // undefined = lädt noch, null = gibt es nicht (mehr)
  const [session, setSession] = useState<DecideSession | null | undefined>(undefined);
  const [players, setPlayers] = useState<DecidePlayer[]>([]);
  const loadSeq = useRef(0);

  const load = useCallback(async () => {
    const seq = ++loadSeq.current;
    const [s, p] = await Promise.all([
      sb.from("ep_decide_sessions").select("*").eq("id", id).maybeSingle(),
      sb.from("ep_decide_players").select("*").eq("session_id", id).order("joined_at"),
    ]);
    // Eine ältere Antwort überschreibt keine neuere
    if (seq !== loadSeq.current) return;
    setSession((s.data as DecideSession | null) ?? null);
    setPlayers((p.data ?? []) as DecidePlayer[]);
  }, [sb, id]);

  const live = session?.status === "lobby" || session?.status === "playing";

  useEffect(() => {
    void load();
    const channel = sb
      .channel(`ep-decide-${id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_decide_sessions", filter: `id=eq.${id}` }, () => void load())
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_decide_players", filter: `session_id=eq.${id}` }, () => void load())
      .subscribe();
    const onFocus = () => void load();
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onFocus);
    return () => {
      void sb.removeChannel(channel);
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onFocus);
    };
  }, [sb, id, load]);

  // Netz für verpasste Realtime-Nachrichten (Handy war kurz weg, Funkloch)
  useEffect(() => {
    if (!live) return;
    const t = setInterval(() => void load(), POLL_MS);
    return () => clearInterval(t);
  }, [live, load]);

  const mine = players.find((p) => p.member_id === me.id) ?? null;

  const join = useCallback(async () => {
    const { error } = await sb.from("ep_decide_players").insert({ session_id: id, member_id: me.id });
    await load();
    return error && error.code !== "23505" ? error : null;
  }, [sb, id, me.id, load]);

  const start = useCallback(async () => {
    if (!session) return null;
    const { error } = await sb
      .from("ep_decide_sessions")
      .update({ status: "playing", round: 0, state: initialState(session.game, session.candidates) })
      .eq("id", id)
      .eq("status", "lobby");
    await load();
    return error;
  }, [sb, id, session, load]);

  const submit = useCallback(
    async (payload: unknown) => {
      if (!session || !mine) return null;
      const round = session.round;
      const data = { ...mine.data, [String(round)]: payload };
      // sofort zeigen: „abgegeben, warte auf die anderen“
      setPlayers((cur) => cur.map((p) => (p.member_id === me.id ? { ...p, data, round_done: round } : p)));
      loadSeq.current += 1;
      const { error } = await sb.from("ep_decide_players").update({ data, round_done: round }).eq("session_id", id).eq("member_id", me.id);
      await load();
      return error;
    },
    [sb, id, me.id, session, mine, load],
  );

  const removePlayer = useCallback(
    async (memberId: string) => {
      const { error } = await sb.from("ep_decide_players").delete().eq("session_id", id).eq("member_id", memberId);
      await load();
      return error;
    },
    [sb, id, load],
  );

  const cancel = useCallback(async () => {
    const { error } = await sb.from("ep_decide_sessions").update({ status: "cancelled" }).eq("id", id).in("status", ["lobby", "playing"]);
    await load();
    return error;
  }, [sb, id, load]);

  // Alle fertig → nächste Runde oder Sieger. Jedes Gerät rechnet dasselbe aus; die
  // Datenbank lässt nur den ersten Schreiber durch (round muss noch stimmen).
  const advanced = useRef<string | null>(null);
  useEffect(() => {
    if (!session || session.status !== "playing" || !mine) return;
    const subs = roundSubmissions(players, session.round);
    if (!subs) return;
    const key = `${session.id}#${session.round}#${players.length}`;
    if (advanced.current === key) return;
    advanced.current = key;
    const state = session.state as DecideState;
    if (!("phase" in state) || state.phase === "fertig") return;
    const next = advance(session.game, state, subs, session.candidates, session.seed, session.round);
    void (async () => {
      if (next.done) {
        await sb.rpc("ep_decide_finish", { p_session: session.id, p_round: session.round, p_recipe: next.winner, p_state: next.state });
      } else {
        await sb
          .from("ep_decide_sessions")
          .update({ round: session.round + 1, state: next.state })
          .eq("id", session.id)
          .eq("status", "playing")
          .eq("round", session.round);
      }
      await load();
    })();
  }, [sb, session, players, mine, load]);

  return { session, players, mine, join, start, submit, removePlayer, cancel, reload: load };
}
