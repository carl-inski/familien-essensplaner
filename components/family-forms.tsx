"use client";

// Familie anlegen und per Code beitreten – genutzt beim ersten Start (noch ohne Familie),
// unter „Haushalt & Konto“ und auf der Einladungsseite /beitreten.

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase/client";

/** Nach Anlegen, Beitreten oder Wechseln: alles neu laden – die aktive Familie bestimmt jede Abfrage */
export function enterFamily(path = "/woche") {
  window.location.assign(path);
}

export const cleanCode = (v: string) => v.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8);
export const prettyCode = (code: string) => (code.length > 4 ? `${code.slice(0, 4)}-${code.slice(4)}` : code);

export function inviteUrl(code: string): string {
  const base = typeof window === "undefined" ? "" : window.location.origin;
  return `${base}/beitreten?code=${code}`;
}

function ErrorNote({ text }: { text: string | null }) {
  if (!text) return null;
  return (
    <p className="t-footnote rounded-xl px-3 py-2" role="alert" style={{ background: "var(--red-soft)", color: "var(--red)" }}>
      {text}
    </p>
  );
}

export function CreateFamilyForm({ defaultName = "", onDone = () => enterFamily() }: { defaultName?: string; onDone?: () => void }) {
  const [family, setFamily] = useState("");
  const [name, setName] = useState(defaultName);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await supabase().rpc("ep_create_household", { p_name: family, p_member_name: name });
    if (error) {
      setBusy(false);
      return setError(error.message);
    }
    onDone();
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-2">
      <input className="input" placeholder="Name der Familie, z. B. Familie Sommer" value={family} maxLength={60} onChange={(e) => setFamily(e.target.value)} aria-label="Name der Familie" />
      <input className="input" placeholder="Dein Name" value={name} maxLength={40} autoComplete="given-name" onChange={(e) => setName(e.target.value)} aria-label="Dein Name" />
      <ErrorNote text={error} />
      <button className="btn btn-primary pressable mt-1" disabled={busy || !family.trim() || !name.trim()}>{busy ? "Legt an …" : "Familie anlegen"}</button>
    </form>
  );
}

interface Preview {
  household_name: string;
  member_count: number;
  already_member: boolean;
}

export function JoinFamilyForm({ defaultName = "", initialCode = "", onDone = () => enterFamily() }: { defaultName?: string; initialCode?: string; onDone?: () => void }) {
  const [code, setCode] = useState(cleanCode(initialCode));
  const [name, setName] = useState(defaultName);
  const [preview, setPreview] = useState<{ code: string; hit: Preview | null } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const found = preview && preview.code === code ? preview.hit : null;
  const unknown = code.length === 8 && preview?.code === code && !preview.hit;

  // Sobald der Code vollständig ist: zeigen, welche Familie dahintersteckt
  useEffect(() => {
    if (code.length !== 8) return;
    let cancelled = false;
    supabase()
      .rpc("ep_invite_preview", { p_code: code })
      .then(({ data }) => !cancelled && setPreview({ code, hit: ((data ?? []) as Preview[])[0] ?? null }));
    return () => {
      cancelled = true;
    };
  }, [code]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await supabase().rpc("ep_join_household", { p_code: code, p_member_name: name });
    if (error) {
      setBusy(false);
      return setError(error.message);
    }
    onDone();
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-2">
      <input
        className="input text-center font-mono text-lg tracking-[0.2em]"
        placeholder="CODE"
        value={prettyCode(code)}
        onChange={(e) => setCode(cleanCode(e.target.value))}
        autoCapitalize="characters"
        autoCorrect="off"
        spellCheck={false}
        aria-label="Einladungscode"
      />
      {found && (
        <p className="t-footnote rounded-xl px-3 py-2" role="status" style={{ background: "var(--green-soft)", color: "var(--green)" }}>
          {found.already_member ? `Du gehörst schon zu „${found.household_name}“.` : `„${found.household_name}“ · ${found.member_count} ${found.member_count === 1 ? "Person" : "Personen"}`}
        </p>
      )}
      {unknown && <ErrorNote text="Diesen Code gibt es nicht. Stimmt jede Stelle?" />}
      {!found?.already_member && (
        <input className="input" placeholder="Dein Name" value={name} maxLength={40} autoComplete="given-name" onChange={(e) => setName(e.target.value)} aria-label="Dein Name" />
      )}
      <ErrorNote text={error} />
      <button className="btn btn-primary pressable mt-1" disabled={busy || !found || (!found.already_member && !name.trim())}>
        {busy ? "Einen Moment …" : found?.already_member ? "Zur Familie wechseln" : "Beitreten"}
      </button>
    </form>
  );
}
