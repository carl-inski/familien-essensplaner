import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { weekNumberLabel } from "@/lib/dates";
import { groupByAisle } from "@/lib/planning";
import { anonClient, jsonLd, requestOrigin } from "@/lib/public/data";
import type { ShoppingItem } from "@/lib/types";

// Wocheneinkauf als ein kombiniertes Pseudo-Rezept für den Bring!-Import

export const metadata: Metadata = { robots: { index: false, follow: false } };

export default async function PublicShoppingPage({ params }: PageProps<"/einkauf/[slug]">) {
  const { slug } = await params;
  const { data } = await anonClient().rpc("ep_public_shopping", { p_slug: slug });
  const list = data as { iso_week: string; items: ShoppingItem[] } | null;
  if (!list) notFound();

  const name = `Wocheneinkauf ${weekNumberLabel(list.iso_week)}`;
  const origin = await requestOrigin();
  const ld = {
    "@context": "https://schema.org",
    "@type": "Recipe",
    name,
    author: { "@type": "Organization", name: "Familien-Essensplaner" },
    image: `${origin}/og?t=${encodeURIComponent(name)}`,
    recipeYield: "1",
    recipeIngredient: list.items.map((i) => i.text),
  };

  return (
    <main className="mx-auto max-w-xl px-5 py-10">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLd(ld) }} />
      <p className="t-footnote" style={{ color: "var(--label-2)" }}>Familien-Essensplaner</p>
      <h1 className="t-title mt-1">{name}</h1>
      <p className="t-sub mt-1" style={{ color: "var(--label-2)" }}>{list.items.length} Zutaten</p>
      {groupByAisle(list.items).map(([aisle, items]) => (
        <section key={aisle}>
          <h2 className="t-section mt-6 mb-2">{aisle}</h2>
          <ul className="group">
            {items.map((i, idx) => <li key={idx} className="row t-sub">{i.text}</li>)}
          </ul>
        </section>
      ))}
    </main>
  );
}
