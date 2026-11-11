"use client";

// Erster Start: Das Konto gehört noch zu keiner Familie.

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase/client";
import { CreateFamilyForm, JoinFamilyForm } from "./family-forms";
import { Segmented } from "./ui";

export function Onboarding({ email }: { email: string | null }) {
  const router = useRouter();
  const [mode, setMode] = useState<"neu" | "code">("neu");
  const [name, setName] = useState<string | null>(null);

  useEffect(() => {
    supabase()
      .auth.getUser()
      .then(({ data }) => setName(typeof data.user?.user_metadata?.name === "string" ? data.user.user_metadata.name : ""));
  }, []);

  return (
    <main className="mx-auto flex min-h-dvh max-w-sm flex-col justify-center gap-5 px-6 py-12">
      <div className="text-center">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/icon.svg" alt="" width={64} height={64} className="mx-auto mb-4 rounded-[16px] shadow-sm" />
        <h1 className="t-title">Willkommen!</h1>
        <p className="t-sub mt-1" style={{ color: "var(--label-2)" }}>
          Der Essensplaner gehört immer einer Familie. Leg eure an – oder tritt mit einem Einladungscode bei.
        </p>
      </div>
      <Segmented<"neu" | "code">
        label="Start"
        value={mode}
        onChange={setMode}
        options={[
          { value: "neu", label: "Familie anlegen" },
          { value: "code", label: "Ich habe einen Code" },
        ]}
      />
      {/* Erst rendern, wenn der Name aus dem Konto da ist – sonst bliebe das Feld leer */}
      {name !== null && (mode === "neu" ? <CreateFamilyForm defaultName={name} /> : <JoinFamilyForm defaultName={name} />)}
      <button
        className="btn-plain t-footnote pressable mx-auto"
        style={{ color: "var(--label-2)" }}
        onClick={async () => {
          await supabase().auth.signOut();
          router.replace("/login");
        }}
      >
        {email ? `Angemeldet als ${email} · ` : ""}Abmelden
      </button>
    </main>
  );
}
