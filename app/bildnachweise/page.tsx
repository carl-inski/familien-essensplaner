import type { Metadata } from "next";
import { BookCover } from "@/components/book";
import { RecipeImage } from "@/components/ui";
import { CATALOG_BOOKS, DISH_PHOTOS } from "@/lib/medien";

export const metadata: Metadata = {
  title: "Bildnachweise",
  robots: { index: false, follow: false },
};

export default function CreditsPage() {
  const missing = DISH_PHOTOS.filter((d) => !d.src);
  return (
    <main className="mx-auto max-w-5xl px-4 py-8 pb-16">
      <p className="t-footnote" style={{ color: "var(--label-2)" }}>Familien-Essensplaner</p>
      <h1 className="t-large-title mt-1">Gerichte und Regal</h1>
      <p className="t-sub mt-2 max-w-2xl" style={{ color: "var(--label-2)" }}>
        Die Fotos sind Beispielbilder für die private App. Die Quelle steht bei jedem Bild.
        Eine ISBN erscheint nur, wenn eine Quelle genau diese Ausgabe nennt. Bei mehreren Ausgaben
        zeigt das Cover die jüngste deutsche Ausgabe, das ISBN-Feld bleibt leer.
      </p>

      <h2 className="t-title-2 mt-8">Rezepte</h2>
      <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
        {DISH_PHOTOS.map((d) => (
          <article key={d.title} className="card flex flex-col overflow-hidden">
            <RecipeImage recipe={{ title: d.title, image_url: null, diet: null }} className="aspect-[4/3] w-full" rounded={0} />
            <div className="flex flex-1 flex-col gap-1 p-3">
              <h3 className="t-sub line-clamp-2 font-semibold leading-snug">{d.title}</h3>
              <p className="t-caption" style={{ color: "var(--label-3)" }}>
                {d.author}
                {d.licenseUrl && (
                  <>
                    {" · "}
                    <a href={d.licenseUrl} className="underline" target="_blank" rel="noopener license">{d.license}</a>
                  </>
                )}
                {d.hinweis ? ` · ${d.hinweis}` : ""}
              </p>
            </div>
          </article>
        ))}
      </div>

      <h2 className="t-title-2 mt-10">Kochbücher</h2>
      <div className="mt-4 grid grid-cols-3 gap-x-3 gap-y-6 sm:grid-cols-4 lg:grid-cols-5">
        {CATALOG_BOOKS.map((b) => (
          <article key={b.title} className="flex flex-col gap-1.5">
            <BookCover book={{ title: b.title, cover_url: b.coverUrl, authors: b.authors }} className="aspect-[2/3] w-full" />
            <span className="t-footnote line-clamp-2 font-medium leading-tight">{b.title}</span>
            <span className="t-caption truncate" style={{ color: "var(--label-2)" }}>{b.authors[0] ?? " "}</span>
            <span className="t-caption truncate tabular-nums" style={{ color: "var(--label-3)" }}>{b.isbn ?? "ISBN offen"}</span>
          </article>
        ))}
      </div>

      <h2 className="t-title-2 mt-10">Nachweise</h2>
      <ul className="mt-3 flex max-w-3xl flex-col gap-2">
        {DISH_PHOTOS.filter((d) => d.src).map((d) => (
          <li key={d.title} className="t-sub">
            <span className="font-semibold">{d.title}.</span> {d.author}.{" "}
            <a className="underline" href={d.sourceUrl ?? "/bildnachweise"}>Quelle</a>
            {d.hinweis ? <span style={{ color: "var(--label-2)" }}> {d.hinweis}</span> : null}
          </li>
        ))}
      </ul>
      <h2 className="t-title-2 mt-10">Cover</h2>
      <ul className="mt-3 flex max-w-3xl flex-col gap-2">
        {CATALOG_BOOKS.map((b) => (
          <li key={b.title} className="t-sub">
            <span className="font-semibold">{b.title}.</span> {b.coverQuelle}
            {b.isbn ? ` ISBN ${b.isbn}.` : " ISBN-Feld leer."}
          </li>
        ))}
      </ul>
      {missing.length > 0 && (
        <p className="t-sub mt-4 max-w-3xl" style={{ color: "var(--label-2)" }}>
          Ohne Beispielbild: {missing.map((d) => d.title).join(" · ")}.
        </p>
      )}
      <p className="t-footnote mt-6 max-w-3xl" style={{ color: "var(--label-3)" }}>
        In einer schon befüllten Datenbank setzt{" "}
        <span className="tabular-nums">supabase/manual/20261024_bilder_und_kochbuecher.sql</span> dieselben
        Pfade. Die Datei läuft nicht von selbst.
      </p>
    </main>
  );
}
