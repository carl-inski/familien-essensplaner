"use client";

import { useEffect, useState } from "react";
import { PageHeader } from "@/components/nav";
import { RecipeForm } from "@/components/recipe-form";
import { RecipeImport } from "@/components/recipe-import";
import { clearDraft, peekDraft, type PendingDraft } from "@/lib/draft-handoff";

export default function NewRecipePage() {
  // Entwurf vom Assistenten (sessionStorage) oder aus „Aus Link“/„Aus Foto“
  const [pending, setPending] = useState<(PendingDraft & { n: number }) | null>(() => {
    const p = typeof window === "undefined" ? null : peekDraft();
    return p ? { ...p, n: 0 } : null;
  });
  const [manual, setManual] = useState(false);
  useEffect(() => clearDraft(), []);

  if (!manual && !pending) return (
    <>
      <PageHeader title="Rezept hinzufügen" back={{ href: "/rezepte", label: "Rezepte" }} />
      <div className="page lg:[&>*]:max-w-3xl">
        <RecipeImport onManual={() => setManual(true)} onDraft={(p) => setPending({ ...p, n: 0 })} />
      </div>
    </>
  );

  return (
    <RecipeForm
      key={pending?.n ?? -1}
      draft={pending?.draft}
      notice={pending?.notice}
    />
  );
}
