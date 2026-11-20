import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { operator } from "@/lib/legal";

export const metadata: Metadata = { title: "Datenschutz" };

// Entwurf, an die tatsächlich eingesetzten Dienste angepasst. Vor dem Start juristisch
// prüfen lassen und Auftragsverarbeitungsverträge (AVV) mit allen Diensten abschließen.

function Part({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="mt-8">
      <h2 className="t-headline">{title}</h2>
      <div className="t-sub mt-2 space-y-2">{children}</div>
    </section>
  );
}

export default function DatenschutzPage() {
  const op = operator();
  return (
    <main className="mx-auto max-w-2xl px-4 py-10 pb-16">
      <p className="t-footnote" style={{ color: "var(--label-2)" }}>
        <Link href="/" className="underline-offset-4 hover:underline">Gnocchi</Link>
      </p>
      <h1 className="t-large-title mt-1">Datenschutzerklärung</h1>

      <Part title="Verantwortlich">
        <p>
          {op.name}
          {op.address.map((line) => <span key={line} className="block">{line}</span>)}
          <span className="block">E-Mail: {op.email}</span>
        </p>
      </Part>

      <Part title="Was wir speichern">
        <p>
          Für dein Konto: E-Mail-Adresse und Passwort (nur als Hash). Für eure Familie: Namen der
          Mitglieder, wer wann mitisst, Wochenplan, Rezepte, Fotos, Einkaufsliste, Vorrat,
          Kochhistorie und Notizen. Diese Daten sieht nur, wer zu eurer Familie gehört.
        </p>
        <p>
          Rechtsgrundlage ist die Erfüllung des Nutzungsvertrags (Art. 6 Abs. 1 lit. b DSGVO).
          Kinderkonten legen Eltern als Admins an; sie sind für die Einwilligung verantwortlich.
        </p>
      </Part>

      <Part title="Cookies">
        <p>
          Wir setzen nur technisch notwendige Cookies, die dich angemeldet halten (§ 25 Abs. 2 TDDDG).
          Es gibt keine Werbe- oder Tracking-Cookies.
        </p>
      </Part>

      <Part title="Dienstleister">
        <ul className="list-disc space-y-1 pl-5">
          <li><b>Vercel Inc.</b> – Hosting der Website, Server in Frankfurt. Server-Protokolle mit IP-Adresse für kurze Zeit.</li>
          <li><b>Supabase Inc.</b> – Datenbank, Anmeldung, Dateispeicher und Live-Abgleich.</li>
          <li><b>Anbieter des KI-Modells</b> (z. B. Anthropic PBC) – nur wenn du eine KI-Funktion nutzt: deine Nachricht, der Rezept-Link oder das Foto, das du einliest. Die Anbieter verwenden diese Daten laut Vertrag nicht zum Training.</li>
          <li><b>Open Library / Google Books</b> – nur die ISBN, wenn du ein Kochbuch einscannst.</li>
          <li><b>Bring!</b> – nur wenn du „In Bring übernehmen“ tippst: Bring! liest dann die öffentliche Zutatenliste ohne Namen.</li>
        </ul>
        <p>
          Bei Diensten mit Sitz in den USA erfolgt die Übermittlung auf Grundlage des EU-US Data
          Privacy Framework bzw. von Standardvertragsklauseln.
        </p>
      </Part>

      <Part title="Wie lange">
        <p>
          Solange dein Konto besteht. Löschst du dein Konto (Haushalt → Konto löschen), entfernen wir
          Login und E-Mail sofort. Familien, in denen niemand mehr ein Konto hat, löschen wir mit allen Daten.
        </p>
      </Part>

      <Part title="Deine Rechte">
        <p>
          Du hast das Recht auf Auskunft, Berichtigung, Löschung, Einschränkung, Datenübertragbarkeit
          (Rezepte lassen sich als Markdown exportieren) und Widerspruch. Schreib uns dazu eine E-Mail.
          Außerdem kannst du dich bei einer Datenschutz-Aufsichtsbehörde beschweren.
        </p>
      </Part>

      <p className="t-footnote mt-10" style={{ color: "var(--label-2)" }}>
        <Link href="/impressum" className="underline">Impressum</Link>
      </p>
    </main>
  );
}
