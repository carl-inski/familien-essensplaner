"use client";

import { useEffect, useState } from "react";
import { RecipeForm } from "@/components/recipe-form";
import { RecipeImport } from "@/components/recipe-import";
import { clearDraft, peekDraft, type PendingDraft } from "@/lib/draft-handoff";

export default function NewRecipePage() {
  // Entwurf vom Assistenten (sessionStorage) oder aus „Aus Link“/„Aus Foto“
  const [pending, setPending] = useState<(PendingDraft & { n: number }) | null>(() => {
    const p = typeof window === "undefined" ? null : peekDraft();
    return p ? { ...p, n: 0 } : null;
  });
  useEffect(() => clearDraft(), []);

  return (
    <RecipeForm
      key={pending?.n ?? -1}
      draft={pending?.draft}
      notice={pending?.notice}
      intro={<RecipeImport onDraft={(p) => setPending((cur) => ({ ...p, n: (cur?.n ?? 0) + 1 }))} />}
    />
  );
}
