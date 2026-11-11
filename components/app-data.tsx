"use client";

// Zentraler Datenkontext für den eingeloggten Bereich:
// Haushalt, Mitglieder, Rezepte (mit Zutaten), Kochbücher und Kochhistorie.

import type { SupabaseClient, User } from "@supabase/supabase-js";
import { useRouter } from "next/navigation";
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { todayBerlin } from "@/lib/dates";
import { cookStatsFromHistory } from "@/lib/history";
import { supabase } from "@/lib/supabase/client";
import { Onboarding } from "./onboarding";
import type { Cookbook, CookingHistoryEntry, CookStats, Household, Member, Membership, Recipe, RecipeFolder } from "@/lib/types";

interface AppData {
  sb: SupabaseClient;
  user: User;
  household: Household;
  me: Member;
  members: Member[];
  /** Alle Familien dieses Kontos (die aktive ist `household`) */
  memberships: Membership[];
  folders: RecipeFolder[];
  recipes: Recipe[];
  recipesById: Map<string, Recipe>;
  cookbooks: Cookbook[];
  cookbooksById: Map<string, Cookbook>;
  history: CookingHistoryEntry[];
  stats: Map<string, CookStats>;
  today: string;
  reloadRecipes: () => Promise<void>;
  reloadCookbooks: () => Promise<void>;
  reloadHistory: () => Promise<void>;
  reloadMembers: () => Promise<void>;
  reloadFolders: () => Promise<void>;
  reloadHousehold: () => Promise<void>;
}

const Ctx = createContext<AppData | null>(null);

export function useApp(): AppData {
  const v = useContext(Ctx);
  if (!v) throw new Error("useApp außerhalb von AppDataProvider");
  return v;
}

const RECIPE_SELECT = "*, ep_recipe_ingredients(*), ep_recipe_notes(count)";

type State =
  | { phase: "loading" }
  | { phase: "no-access"; email: string | null }
  | { phase: "error"; message: string }
  | { phase: "ready"; user: User; household: Household; me: Member; memberships: Membership[] };

export function AppDataProvider({ children }: { children: ReactNode }) {
  const sb = supabase();
  const router = useRouter();
  const [state, setState] = useState<State>({ phase: "loading" });
  const [members, setMembers] = useState<Member[]>([]);
  const [recipes, setRecipes] = useState<Recipe[]>([]);
  const [cookbooks, setCookbooks] = useState<Cookbook[]>([]);
  const [history, setHistory] = useState<CookingHistoryEntry[]>([]);
  const [folders, setFolders] = useState<RecipeFolder[]>([]);
  const today = todayBerlin();

  const reloadRecipes = useCallback(async () => {
    const { data } = await sb.from("ep_recipes").select(RECIPE_SELECT).order("title");
    setRecipes(
      ((data ?? []) as Recipe[]).map((r) => ({
        ...r,
        ep_recipe_ingredients: [...(r.ep_recipe_ingredients ?? [])].sort((a, b) => a.position - b.position),
      })),
    );
  }, [sb]);

  const reloadCookbooks = useCallback(async () => {
    const { data } = await sb.from("ep_cookbooks").select("*").order("title");
    setCookbooks((data ?? []) as Cookbook[]);
  }, [sb]);

  const reloadHistory = useCallback(async () => {
    const { data } = await sb.from("ep_cooking_history").select("*").order("cooked_on", { ascending: false });
    setHistory((data ?? []) as CookingHistoryEntry[]);
  }, [sb]);

  const reloadMembers = useCallback(async () => {
    const { data } = await sb.from("ep_members").select("*").order("position");
    setMembers((data ?? []) as Member[]);
  }, [sb]);

  const reloadFolders = useCallback(async () => {
    const { data } = await sb.from("ep_recipe_folders").select("*").order("position").order("name");
    setFolders((data ?? []) as RecipeFolder[]);
  }, [sb]);

  const reloadHousehold = useCallback(async () => {
    const { data } = await sb.from("ep_households").select("id, name, invite_code").single();
    if (data) setState((s) => (s.phase === "ready" ? { ...s, household: data as Household } : s));
  }, [sb]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data: auth } = await sb.auth.getUser();
      if (!auth.user) {
        router.replace("/login");
        return;
      }
      const { data: list, error } = await sb.rpc("ep_my_memberships");
      if (cancelled) return;
      if (error) {
        setState({ phase: "error", message: error.message });
        return;
      }
      const memberships = (list ?? []) as Membership[];
      const active = memberships.find((m) => m.active) ?? memberships[0];
      if (!active) {
        setState({ phase: "no-access", email: auth.user.email ?? null });
        return;
      }
      // RLS zeigt nur die aktive Familie – darum reichen Abfragen ohne Familien-Filter
      const [{ data: mine }, { data: hh }] = await Promise.all([
        sb.from("ep_members").select("*").eq("id", active.member_id).single(),
        sb.from("ep_households").select("id, name, invite_code").eq("id", active.household_id).single(),
      ]);
      const me = mine as Member | null;
      if (!me || !hh) {
        setState({ phase: "error", message: "Die Familie konnte nicht geladen werden." });
        return;
      }
      // Vergangene Gerichte gelten als gekocht – vor dem Laden der Historie verbuchen
      await sb.rpc("ep_mark_past_cooked");
      await Promise.all([reloadMembers(), reloadRecipes(), reloadCookbooks(), reloadHistory(), reloadFolders()]);
      if (!cancelled) setState({ phase: "ready", user: auth.user, household: hh as Household, me, memberships });
    })();
    return () => {
      cancelled = true;
    };
  }, [sb, router, reloadMembers, reloadRecipes, reloadCookbooks, reloadHistory, reloadFolders]);

  // Kochhistorie live halten (Änderungen von anderen Geräten)
  useEffect(() => {
    if (state.phase !== "ready") return;
    const channel = sb
      .channel("ep-history")
      .on("postgres_changes", { event: "*", schema: "public", table: "ep_cooking_history" }, () => void reloadHistory())
      .subscribe();
    return () => {
      void sb.removeChannel(channel);
    };
  }, [sb, state.phase, reloadHistory]);

  const value = useMemo<AppData | null>(() => {
    if (state.phase !== "ready") return null;
    const me = members.find((m) => m.id === state.me.id) ?? state.me;
    return {
      sb,
      user: state.user,
      household: state.household,
      me,
      members,
      memberships: state.memberships,
      folders,
      recipes,
      recipesById: new Map(recipes.map((r) => [r.id, r])),
      cookbooks,
      cookbooksById: new Map(cookbooks.map((c) => [c.id, c])),
      history,
      stats: cookStatsFromHistory(history, today),
      today,
      reloadRecipes,
      reloadCookbooks,
      reloadHistory,
      reloadMembers,
      reloadFolders,
      reloadHousehold,
    };
  }, [state, sb, members, folders, recipes, cookbooks, history, today, reloadRecipes, reloadCookbooks, reloadHistory, reloadMembers, reloadFolders, reloadHousehold]);

  if (state.phase === "loading") return <LoadingScreen />;
  if (state.phase === "error") return <Message title="Etwas ist schiefgelaufen" text={state.message} />;
  if (state.phase === "no-access") return <Onboarding email={state.email} />;
  return <Ctx value={value}>{children}</Ctx>;
}

function LoadingScreen() {
  return (
    <div className="mx-auto max-w-2xl px-4 pt-16" aria-busy="true" aria-label="Lädt">
      <div className="skeleton mb-6 h-9 w-48" />
      {Array.from({ length: 4 }).map((_, i) => (
        <div key={i} className="skeleton mb-3 h-28 w-full" style={{ borderRadius: 14 }} />
      ))}
    </div>
  );
}

function Message({ title, text, logout }: { title: string; text: string; logout?: boolean }) {
  const router = useRouter();
  return (
    <div className="mx-auto flex min-h-dvh max-w-md flex-col justify-center gap-4 px-6 text-center">
      <h1 className="t-title">{title}</h1>
      <p className="t-sub" style={{ color: "var(--label-2)" }}>{text}</p>
      {logout && (
        <button
          className="btn btn-gray pressable mx-auto"
          onClick={async () => {
            await supabase().auth.signOut();
            router.replace("/login");
          }}
        >
          Abmelden
        </button>
      )}
    </div>
  );
}
