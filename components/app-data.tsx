"use client";

// Zentraler Datenkontext für den eingeloggten Bereich:
// Haushalt, Mitglieder, Rezepte (mit Zutaten), Kochbücher und Kochhistorie.

import type { SupabaseClient, User } from "@supabase/supabase-js";
import { useRouter } from "next/navigation";
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { todayBerlin } from "@/lib/dates";
import { cookStatsFromHistory } from "@/lib/history";
import { supabase } from "@/lib/supabase/client";
import type { Cookbook, CookingHistoryEntry, CookStats, Household, Member, Recipe } from "@/lib/types";

interface AppData {
  sb: SupabaseClient;
  user: User;
  household: Household;
  me: Member;
  members: Member[];
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
}

const Ctx = createContext<AppData | null>(null);

export function useApp(): AppData {
  const v = useContext(Ctx);
  if (!v) throw new Error("useApp außerhalb von AppDataProvider");
  return v;
}

const RECIPE_SELECT = "*, ep_recipe_ingredients(*)";

type State =
  | { phase: "loading" }
  | { phase: "no-access"; email: string | null }
  | { phase: "error"; message: string }
  | { phase: "ready"; user: User; household: Household; me: Member };

export function AppDataProvider({ children }: { children: ReactNode }) {
  const sb = supabase();
  const router = useRouter();
  const [state, setState] = useState<State>({ phase: "loading" });
  const [members, setMembers] = useState<Member[]>([]);
  const [recipes, setRecipes] = useState<Recipe[]>([]);
  const [cookbooks, setCookbooks] = useState<Cookbook[]>([]);
  const [history, setHistory] = useState<CookingHistoryEntry[]>([]);
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

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data: auth } = await sb.auth.getUser();
      if (!auth.user) {
        router.replace("/login");
        return;
      }
      const { data: linked, error } = await sb.rpc("ep_link_member");
      if (cancelled) return;
      if (error) {
        setState({ phase: "error", message: error.message });
        return;
      }
      const me = (linked as Member[] | null)?.[0];
      if (!me) {
        setState({ phase: "no-access", email: auth.user.email ?? null });
        return;
      }
      const { data: hh } = await sb.from("ep_households").select("id, name").eq("id", me.household_id).single();
      await Promise.all([reloadMembers(), reloadRecipes(), reloadCookbooks(), reloadHistory()]);
      if (!cancelled) setState({ phase: "ready", user: auth.user, household: hh as Household, me });
    })();
    return () => {
      cancelled = true;
    };
  }, [sb, router, reloadMembers, reloadRecipes, reloadCookbooks, reloadHistory]);

  // Kochhistorie live halten (gekocht ✓ von anderen Geräten)
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
    };
  }, [state, sb, members, recipes, cookbooks, history, today, reloadRecipes, reloadCookbooks, reloadHistory, reloadMembers]);

  if (state.phase === "loading") return <LoadingScreen />;
  if (state.phase === "error") return <Message title="Etwas ist schiefgelaufen" text={state.message} />;
  if (state.phase === "no-access")
    return (
      <Message
        title="Noch kein Zugang"
        text={`Die E-Mail ${state.email ?? ""} ist keinem Haushalt zugeordnet. Bitte Carl, dich unter „Haushalt“ mit dieser Adresse einzutragen, und melde dich danach erneut an.`}
        logout
      />
    );
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
