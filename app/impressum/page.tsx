import type { Metadata } from "next";
import Link from "next/link";
import { operator } from "@/lib/legal";

export const metadata: Metadata = { title: "Impressum" };

export default function ImpressumPage() {
  const op = operator();
  return (
    <main className="mx-auto max-w-2xl px-4 py-10 pb-16">
      <p className="t-footnote" style={{ color: "var(--label-2)" }}>
        <Link href="/" className="underline-offset-4 hover:underline">Gnocchi</Link>
      </p>
      <h1 className="t-large-title mt-1">Impressum</h1>
      <h2 className="t-headline mt-8">Angaben gemäß § 5 DDG</h2>
      <p className="t-sub mt-2">
        {op.name}
        {op.address.map((line) => (
          <span key={line} className="block">{line}</span>
        ))}
      </p>
      <h2 className="t-headline mt-6">Kontakt</h2>
      <p className="t-sub mt-2">
        E-Mail: {op.email.includes("@") ? <a className="underline" href={`mailto:${op.email}`}>{op.email}</a> : op.email}
      </p>
      <h2 className="t-headline mt-6">Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV</h2>
      <p className="t-sub mt-2">{op.name}, Anschrift wie oben.</p>
      <h2 className="t-headline mt-6">Verbraucherstreitbeilegung</h2>
      <p className="t-sub mt-2">
        Wir sind nicht bereit oder verpflichtet, an Streitbeilegungsverfahren vor einer
        Verbraucherschlichtungsstelle teilzunehmen.
      </p>
      <p className="t-footnote mt-10" style={{ color: "var(--label-2)" }}>
        <Link href="/datenschutz" className="underline">Datenschutzerklärung</Link>
      </p>
    </main>
  );
}
