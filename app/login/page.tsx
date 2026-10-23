"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import { supabase } from "@/lib/supabase/client";

export default function LoginPage() {
  return (
    <Suspense>
      <Login />
    </Suspense>
  );
}

function Login() {
  const params = useSearchParams();
  const router = useRouter();
  const next = params.get("next") ?? "/woche";
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(params.get("fehler") ? "Der Anmeldelink ist abgelaufen oder ungültig." : null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await supabase().auth.signInWithPassword({ email: email.trim(), password });
    if (error) {
      setBusy(false);
      setError(
        error.message.toLowerCase().includes("invalid")
          ? "E-Mail oder Passwort stimmt nicht."
          : error.message.toLowerCase().includes("rate")
            ? "Zu viele Versuche – bitte kurz warten."
            : error.message,
      );
      return;
    }
    router.replace(next.startsWith("/") && !next.startsWith("//") ? next : "/woche");
    router.refresh();
  }

  return (
    <main className="mx-auto flex min-h-dvh max-w-sm flex-col justify-center px-6 py-12">
      <div className="mb-8 flex flex-col items-center gap-4 text-center">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/icon.svg" alt="" width={72} height={72} className="rounded-[18px] shadow-sm" />
        <div>
          <h1 className="t-title">Essensplaner</h1>
          <p className="t-sub mt-1" style={{ color: "var(--label-2)" }}>
            Wochenplan, Rezepte und Einkauf für die Familie
          </p>
        </div>
      </div>

      <form onSubmit={submit} className="flex flex-col gap-3">
        <div className="group">
          <input
            id="email"
            className="input !rounded-none !bg-transparent"
            type="email"
            inputMode="email"
            autoComplete="username"
            required
            placeholder="E-Mail"
            aria-label="E-Mail"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          <input
            id="password"
            className="input !rounded-none !bg-transparent"
            type="password"
            autoComplete="current-password"
            required
            placeholder="Passwort"
            aria-label="Passwort"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </div>
        {error && (
          <p className="t-footnote rounded-xl px-3 py-2" role="alert" style={{ background: "var(--red-soft)", color: "var(--red)" }}>
            {error}
          </p>
        )}
        <button className="btn btn-primary pressable mt-2 w-full" disabled={busy || !email || !password}>
          {busy ? "Melde an …" : "Anmelden"}
        </button>
        <p className="t-footnote mt-2 text-center" style={{ color: "var(--label-3)" }}>
          Zugang haben nur eingetragene Familienmitglieder. Passwort vergessen? Carl kann es unter „Haushalt“ neu setzen.
        </p>
      </form>
    </main>
  );
}
