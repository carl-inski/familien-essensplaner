"use client";

import { useSearchParams } from "next/navigation";
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
  const next = params.get("next") ?? "/woche";
  const failed = params.get("fehler");
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setState("sending");
    setError(null);
    const redirect = `${window.location.origin}/auth/confirm?next=${encodeURIComponent(next)}`;
    const { error } = await supabase().auth.signInWithOtp({
      email: email.trim(),
      options: { emailRedirectTo: redirect, shouldCreateUser: true },
    });
    if (error) {
      setState("error");
      setError(error.message.includes("rate") ? "Zu viele Anfragen – bitte in ein paar Minuten erneut versuchen." : error.message);
    } else {
      setState("sent");
    }
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

      {state === "sent" ? (
        <div className="card p-5 text-center">
          <p className="t-headline">Schau in dein Postfach</p>
          <p className="t-sub mt-2" style={{ color: "var(--label-2)" }}>
            Wir haben einen Anmeldelink an <strong>{email}</strong> geschickt. Öffne ihn auf diesem Gerät.
          </p>
          <button className="btn btn-plain pressable mt-3" onClick={() => setState("idle")}>
            Andere E-Mail verwenden
          </button>
        </div>
      ) : (
        <form onSubmit={submit} className="flex flex-col gap-3">
          {failed && (
            <p className="t-footnote rounded-xl px-3 py-2" style={{ background: "var(--red-soft)", color: "var(--red)" }}>
              Der Anmeldelink ist abgelaufen oder ungültig. Fordere einfach einen neuen an.
            </p>
          )}
          <label className="t-footnote px-1" style={{ color: "var(--label-2)" }} htmlFor="email">
            E-Mail-Adresse
          </label>
          <input
            id="email"
            className="input"
            type="email"
            inputMode="email"
            autoComplete="email"
            required
            placeholder="name@beispiel.de"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          {error && (
            <p className="t-footnote px-1" style={{ color: "var(--red)" }}>
              {error}
            </p>
          )}
          <button className="btn btn-primary pressable mt-2 w-full" disabled={state === "sending" || !email}>
            {state === "sending" ? "Sende Link …" : "Anmeldelink senden"}
          </button>
          <p className="t-footnote mt-2 text-center" style={{ color: "var(--label-3)" }}>
            Kein Passwort nötig. Zugang haben nur eingetragene Familienmitglieder.
          </p>
        </form>
      )}
    </main>
  );
}
