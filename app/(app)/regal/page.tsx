"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useApp } from "@/components/app-data";
import { BookCover, BookSheet } from "@/components/book";
import { IconPlus } from "@/components/icons";
import { AccountButton } from "@/components/account-button";
import { IconButton, PageHeader } from "@/components/nav";
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
        subtitle={`${cookbooks.length} Kochbücher`}
        trailing={
          <>
            <IconButton label="Buch hinzufügen" onClick={() => setAdding(true)}><IconPlus /></IconButton>
            <AccountButton />
          </>
        }
      />
      <div className="mx-auto mt-5 grid max-w-2xl grid-cols-3 gap-x-4 gap-y-6 px-4 sm:grid-cols-4">
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
        <button className="pressable flex aspect-[2/3] w-full items-center justify-center rounded-md" style={{ boxShadow: "inset 0 0 0 1.5px var(--separator)", color: "var(--label-3)" }} onClick={() => setAdding(true)} aria-label="Buch hinzufügen">
          <IconPlus size={28} />
        </button>
      </div>
      <BookSheet open={adding} onClose={() => setAdding(false)} onSaved={(id) => router.push(`/regal/${id}`)} />
    </>
  );
}
