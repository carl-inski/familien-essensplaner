"use client";

// Einladungslink: /beitreten?code=ABCD2345. Wer nicht angemeldet ist, landet zuerst
// beim Login (proxy.ts) und kommt danach hierher zurück.

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { JoinFamilyForm } from "@/components/family-forms";
import { supabase } from "@/lib/supabase/client";

export default function JoinPage() {
  return (
    <Suspense>
      <Join />
    </Suspense>
  );
}

function Join() {
  const code = useSearchParams().get("code") ?? "";
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
        <h1 className="t-title">Familie beitreten</h1>
        <p className="t-sub mt-1" style={{ color: "var(--label-2)" }}>Gib den Einladungscode ein, den du bekommen hast.</p>
      </div>
      {name !== null && <JoinFamilyForm defaultName={name} initialCode={code} />}
      <Link href="/woche" className="btn-plain t-footnote pressable mx-auto" style={{ color: "var(--label-2)" }}>Abbrechen</Link>
    </main>
  );
}
