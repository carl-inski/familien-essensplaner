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

type Mode = "anmelden" | "neu" | "vergessen";

function germanError(message: string): string {
  const m = message.toLowerCase();
  if (m.includes("invalid login")) return "E-Mail oder Passwort stimmt nicht.";
  if (m.includes("rate") || m.includes("security purposes")) return "Zu viele Versuche – bitte kurz warten.";
  if (m.includes("already registered") || m.includes("already been registered")) return "Zu dieser E-Mail gibt es schon ein Konto. Melde dich an.";
  if (m.includes("not confirmed")) return "Bitte bestätige zuerst deine E-Mail – der Link steht in der Mail von uns.";
  if (m.includes("signups not allowed") || m.includes("signup is disabled")) return "Neue Konten sind gerade nicht freigeschaltet.";
  if (m.includes("password")) return "Das Passwort braucht mindestens 8 Zeichen.";
  if (m.includes("valid email") || m.includes("invalid format")) return "Diese E-Mail-Adresse sieht nicht richtig aus.";
  return message;
}

function Login() {
  const params = useSearchParams();
  const router = useRouter();
  const rawNext = params.get("next") ?? "/woche";
  const next = rawNext.startsWith("/") && !rawNext.startsWith("//") ? rawNext : "/woche";
  // Wer über einen Einladungslink kommt, hat meist noch kein Konto
  const [mode, setMode] = useState<Mode>(next.startsWith("/beitreten") ? "neu" : "anmelden");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [info, setInfo] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(params.get("fehler") ? "Der Link ist abgelaufen oder ungültig." : null);

  function switchMode(m: Mode) {
    setMode(m);
    setError(null);
    setInfo(null);
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setInfo(null);
    const sb = supabase();
    const mail = email.trim();
    const confirmUrl = (to: string) => `${window.location.origin}/auth/confirm?next=${encodeURIComponent(to)}`;

    if (mode === "vergessen") {
      const { error } = await sb.auth.resetPasswordForEmail(mail, { redirectTo: confirmUrl("/haushalt") });
      setBusy(false);
      if (error) return setError(germanError(error.message));
      return setInfo("Wenn es ein Konto mit dieser Adresse gibt, ist eine Mail unterwegs. Über den Link kommst du hinein und setzt unter „Mein Konto“ ein neues Passwort.");
    }

    if (mode === "neu") {
      if (password.length < 8) {
        setBusy(false);
        return setError("Das Passwort braucht mindestens 8 Zeichen.");
      }
      const { data, error } = await sb.auth.signUp({
        email: mail,
        password,
        options: { data: { name: name.trim() }, emailRedirectTo: confirmUrl(next) },
      });
      if (error) {
        setBusy(false);
        return setError(germanError(error.message));
      }
      if (!data.session) {
        // E-Mail-Bestätigung ist eingeschaltet (oder die Adresse ist schon vergeben – Supabase verrät das nicht)
        setBusy(false);
        return setInfo(`Fast geschafft: Wir haben eine Mail an ${mail} geschickt. Bestätige sie über den Link, dann geht es weiter.`);
      }
    } else {
      const { error } = await sb.auth.signInWithPassword({ email: mail, password });
      if (error) {
        setBusy(false);
        return setError(germanError(error.message));
      }
    }
    router.replace(next);
    router.refresh();
  }

  const ready = !!email && (mode === "vergessen" || !!password) && (mode !== "neu" || !!name.trim());

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

      {mode !== "vergessen" && (
        <div className="segmented mb-4" role="radiogroup" aria-label="Anmelden oder neues Konto">
          <button type="button" role="radio" aria-checked={mode === "anmelden"} data-on={mode === "anmelden"} className="pressable" onClick={() => switchMode("anmelden")}>Anmelden</button>
          <button type="button" role="radio" aria-checked={mode === "neu"} data-on={mode === "neu"} className="pressable" onClick={() => switchMode("neu")}>Neues Konto</button>
        </div>
      )}

      <form onSubmit={submit} className="flex flex-col gap-3">
        {mode === "vergessen" && <p className="t-sub" style={{ color: "var(--label-2)" }}>Wir schicken dir einen Link, mit dem du wieder hineinkommst.</p>}
        <div className="group">
          {mode === "neu" && (
            <input
              id="name"
              className="input !rounded-none !bg-transparent"
              autoComplete="given-name"
              required
              maxLength={40}
              placeholder="Dein Name"
              aria-label="Dein Name"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          )}
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
          {mode !== "vergessen" && (
            <input
              id="password"
              className="input !rounded-none !bg-transparent"
              type="password"
              autoComplete={mode === "neu" ? "new-password" : "current-password"}
              required
              minLength={mode === "neu" ? 8 : undefined}
              placeholder={mode === "neu" ? "Passwort (mind. 8 Zeichen)" : "Passwort"}
              aria-label="Passwort"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          )}
        </div>
        {error && (
          <p className="t-footnote rounded-xl px-3 py-2" role="alert" style={{ background: "var(--red-soft)", color: "var(--red)" }}>
            {error}
          </p>
        )}
        {info && (
          <p className="t-footnote rounded-xl px-3 py-2" role="status" style={{ background: "var(--green-soft)", color: "var(--green)" }}>
            {info}
          </p>
        )}
        <button className="btn btn-primary pressable mt-2 w-full" disabled={busy || !ready}>
          {busy ? "Einen Moment …" : mode === "neu" ? "Konto erstellen" : mode === "vergessen" ? "Link schicken" : "Anmelden"}
        </button>
        <p className="t-footnote mt-2 text-center" style={{ color: "var(--label-2)" }}>
          {mode === "neu" && "Danach legst du eure Familie an oder trittst mit einem Einladungscode bei."}
          {mode === "anmelden" && (
            <button type="button" className="btn-plain pressable" onClick={() => switchMode("vergessen")}>Passwort vergessen?</button>
          )}
          {mode === "vergessen" && (
            <button type="button" className="btn-plain pressable" onClick={() => switchMode("anmelden")}>Zurück zum Anmelden</button>
          )}
        </p>
      </form>
    </main>
  );
}
