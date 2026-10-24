"use client";

// Eine Chat-Instanz für die ganze Sitzung: Das Gespräch bleibt beim Wechsel
// zwischen den Tabs erhalten. Kontext (z. B. offenes Rezept) geht mit jeder Anfrage mit.
// Am Computer lebt der Chat zusätzlich in einem Seitenpanel rechts (⌘J), das auf jeder
// Seite bereitsteht; auf dem Handy führt ask() zur KI-Seite.

import { Chat } from "@ai-sdk/react";
import { DefaultChatTransport, type UIMessage } from "ai";
import { usePathname, useRouter } from "next/navigation";
import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { useAiStatus } from "@/components/ai-status";
import { useIsDesktop } from "@/components/use-media";
import type { AssistantContext } from "@/lib/ai/assistant-schemas";

interface AssistantState {
  chat: Chat<UIMessage>;
  kontext: AssistantContext;
  setKontext: (k: AssistantContext) => void;
  reset: () => void;
  /** Frage stellen: am Computer im Panel, sonst auf der KI-Seite */
  ask: (frage?: string, kontext?: AssistantContext) => void;
  /** Seitenpanel (nur Computer, nicht auf der KI-Seite selbst) */
  panelOpen: boolean;
  panelAvailable: boolean;
  setPanelOpen: (open: boolean) => void;
  /** null solange unbekannt */
  aiEnabled: boolean | null;
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

const PANEL_KEY = "ki-panel";

export function AssistantProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState(createSession);
  const [kontext, setKontextState] = useState<AssistantContext>({});
  const desktop = useIsDesktop();
  const path = usePathname();
  const router = useRouter();
  const { status: aiStatus } = useAiStatus();
  const aiEnabled = aiStatus ? aiStatus.enabled : null;
  const panelAvailable = desktop && path !== "/assistent";
  const [panelWanted, setPanelWanted] = useState(() => {
    try {
      return typeof window !== "undefined" && localStorage.getItem(PANEL_KEY) === "1";
    } catch {
      return false;
    }
  });
  const panelOpen = panelAvailable && panelWanted;

  const setPanelOpen = useCallback((open: boolean) => {
    setPanelWanted(open);
    try {
      localStorage.setItem(PANEL_KEY, open ? "1" : "0");
    } catch {}
  }, []);

  const setKontext = useCallback(
    (k: AssistantContext) => {
      session.setKontext(k);
      setKontextState(k);
    },
    [session],
  );
  const reset = () => {
    void session.chat.stop();
    setKontextState({});
    setSession(createSession());
  };

  const ask = useCallback(
    (frage?: string, k?: AssistantContext) => {
      if (!panelAvailable) {
        const q = new URLSearchParams();
        if (frage) q.set("frage", frage);
        if (k?.rezept_id) q.set("rezept", k.rezept_id);
        router.push(`/assistent${q.size ? `?${q}` : ""}`);
        return;
      }
      if (k) setKontext(k);
      setPanelOpen(true);
      const busy = session.chat.status === "submitted" || session.chat.status === "streaming";
      if (frage?.trim() && !busy) void session.chat.sendMessage({ text: frage.trim() });
    },
    [panelAvailable, router, setKontext, setPanelOpen, session],
  );

  // Das Panel nimmt rechts Platz ein; Layout und schwebende Leisten rücken per CSS-Variable
  useEffect(() => {
    document.documentElement.dataset.kiPanel = panelOpen ? "open" : "closed";
  }, [panelOpen]);

  // ⌘J / Strg+J: KI ein- und ausblenden (wie in Notion)
  useEffect(() => {
    if (!panelAvailable) return;
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "j") {
        e.preventDefault();
        setPanelOpen(!panelWanted);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [panelAvailable, panelWanted, setPanelOpen]);

  return (
    <Ctx value={{ chat: session.chat, kontext, setKontext, reset, ask, panelOpen, panelAvailable, setPanelOpen, aiEnabled }}>
      {children}
    </Ctx>
  );
}
