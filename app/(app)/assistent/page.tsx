"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useRef } from "react";
import { useAiStatus } from "@/components/ai-status";
import { AssistantChat } from "@/components/assistant/assistant-chat";
import { useAssistant } from "@/components/assistant/assistant-provider";
import { useApp } from "@/components/app-data";
import { PageHeader } from "@/components/nav";

export default function AssistantPage() {
  return (
    <Suspense>
      <Assistant />
    </Suspense>
  );
}

function Assistant() {
  const { chat, kontext, setKontext } = useAssistant();
  const { recipesById } = useApp();
  const { status: ai } = useAiStatus();
  const params = useSearchParams();
  const router = useRouter();
  const handled = useRef<string | null>(null);

  // Einstieg mit Kontext: /assistent?rezept=<id>&frage=…
  useEffect(() => {
    const key = params.toString();
    if (!key || handled.current === key) return;
    handled.current = key;
    const rid = params.get("rezept");
    const recipe = rid ? recipesById.get(rid) : undefined;
    if (recipe) setKontext({ rezept_id: recipe.id, rezept_titel: recipe.title });
    const frage = params.get("frage");
    if (frage && ai?.enabled !== false) void chat.sendMessage({ text: frage });
    router.replace("/assistent");
  }, [params, recipesById, setKontext, chat, router, ai?.enabled]);

  return (
    <>
      <PageHeader
        title="KI"
        tabRoot
        subtitle={kontext.rezept_titel ? <>Zum Rezept <strong>{kontext.rezept_titel}</strong></> : "Fragt eure Rezepte, plant mit, schreibt Notizen"}
      />
      <AssistantChat variant="page" />
    </>
  );
}
