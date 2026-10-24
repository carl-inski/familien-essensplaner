"use client";

// Eine Chat-Instanz für die ganze Sitzung: Das Gespräch bleibt beim Wechsel
// zwischen den Tabs erhalten. Kontext (z. B. offenes Rezept) geht mit jeder Anfrage mit.

import { Chat } from "@ai-sdk/react";
import { DefaultChatTransport, type UIMessage } from "ai";
import { createContext, useContext, useState, type ReactNode } from "react";
import type { AssistantContext } from "@/lib/ai/assistant-schemas";

interface AssistantState {
  chat: Chat<UIMessage>;
  kontext: AssistantContext;
  setKontext: (k: AssistantContext) => void;
  reset: () => void;
}

const Ctx = createContext<AssistantState | null>(null);

export function useAssistant(): AssistantState {
  const v = useContext(Ctx);
  if (!v) throw new Error("useAssistant außerhalb von AssistantProvider");
  return v;
}

/** Chat plus Kontext, den der Transport bei jeder Anfrage mitschickt */
function createSession() {
  let kontext: AssistantContext = {};
  const chat = new Chat<UIMessage>({
    // Nach „Übernehmen“ geht bewusst keine neue Anfrage raus: Die Karte zeigt das
    // Ergebnis, die KI sieht es mit der nächsten Nachricht.
    transport: new DefaultChatTransport({ api: "/api/ai/chat", body: () => ({ kontext }) }),
  });
  return {
    chat,
    setKontext: (k: AssistantContext) => {
      kontext = k;
    },
  };
}

export function AssistantProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState(createSession);
  const [kontext, setKontextState] = useState<AssistantContext>({});

  const setKontext = (k: AssistantContext) => {
    session.setKontext(k);
    setKontextState(k);
  };
  const reset = () => {
    void session.chat.stop();
    setKontextState({});
    setSession(createSession());
  };

  return <Ctx value={{ chat: session.chat, kontext, setKontext, reset }}>{children}</Ctx>;
}
