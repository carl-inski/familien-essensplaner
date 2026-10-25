"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useApp } from "@/components/app-data";
import { BookCover, BookSheet } from "@/components/book";
import { IconPlus } from "@/components/icons";
import { CollectionSwitch } from "@/components/collection-switch";
import { PageHeader } from "@/components/nav";
import { presentCookbook } from "@/lib/medien";

export default function ShelfPage() {
  const { cookbooks, recipes } = useApp();
  const router = useRouter();
  const [adding, setAdding] = useState(false);
  const count = (id: string) => recipes.filter((r) => r.cookbook_id === id).length;
  const shelf = cookbooks.map(presentCookbook);

  return (
    <>
      <PageHeader
        title="Regal"
        width="wide"
        tabRoot
        subtitle={`${cookbooks.length} Kochbücher im Regal`}
      >
        <CollectionSwitch active="regal" />
      </PageHeader>
      <div className="page-wide mt-5 grid grid-cols-3 gap-x-4 gap-y-6 sm:grid-cols-4 lg:grid-cols-6 lg:gap-x-6 lg:gap-y-8 xl:grid-cols-8 2xl:grid-cols-10">
        {/* Immer zuerst: neues Buch – ISBN-Abfrage, Foto oder von Hand */}
        <button className="pressable flex flex-col gap-1.5 text-left" onClick={() => setAdding(true)} aria-label="Neues Buch hinzufügen">
          <span className="flex aspect-[2/3] w-full items-center justify-center rounded-md" style={{ background: "var(--accent-soft)", color: "var(--accent)" }}>
            <IconPlus size={30} strokeWidth={2} />
          </span>
          <span className="t-footnote font-medium leading-tight">Neues Buch</span>
          <span className="t-caption -mt-1" style={{ color: "var(--label-2)" }}>per ISBN oder von Hand</span>
        </button>
        {shelf.map((b) => (
          <Link key={b.id} href={`/regal/${b.id}`} className="pressable flex flex-col gap-1.5">
            <BookCover book={b} className="aspect-[2/3] w-full" />
            <span className="t-footnote line-clamp-2 font-medium leading-tight">{b.title}</span>
            <span className="t-caption -mt-1 truncate" style={{ color: "var(--label-2)" }}>
              {b.authors[0] ?? (count(b.id) ? `${count(b.id)} Rezept${count(b.id) === 1 ? "" : "e"}` : " ")}
            </span>
            {b.isbn && <span className="t-caption -mt-1 truncate tabular-nums" style={{ color: "var(--label-3)" }}>{b.isbn}</span>}
          </Link>
        ))}
      </div>
      <BookSheet open={adding} onClose={() => setAdding(false)} onSaved={(id) => router.push(`/regal/${id}`)} />
    </>
  );
}
