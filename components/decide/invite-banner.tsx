"use client";

// Hinweis auf jeder Seite: In der Familie läuft eine Runde, bei der ich noch nicht
// mitspiele. Ein Tipp bringt mich hinein – so findet jede Person am eigenen Handy dazu.

import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import { useApp } from "@/components/app-data";
import { IconClose } from "@/components/icons";
import { GAMES } from "@/lib/decide";
import { useOpenSessions } from "./use-open-sessions";

export function DecideInvite() {
  return (
    <Suspense>
      <Banner />
    </Suspense>
  );
}

function Banner() {
  const { me, members } = useApp();
  const open = useOpenSessions();
  const path = usePathname();
  const viewing = useSearchParams().get("s");
  const reduce = useReducedMotion();
  const [dismissed, setDismissed] = useState<string[]>([]);

  // Nur Einladungen anderer, die noch auf Mitspieler warten – und nicht, wenn ich schon dort bin
  const invite = open.find((s) => s.status === "lobby" && s.created_by !== me.id && !dismissed.includes(s.id) && !(path === "/entscheiden" && (viewing === s.id || !viewing)));
  const host = invite ? members.find((m) => m.id === invite.created_by)?.name ?? "Jemand" : "";
  const game = invite ? GAMES.find((g) => g.id === invite.game) : undefined;

  return (
    <AnimatePresence>
      {invite && (
        <motion.div
          key={invite.id}
          className="fixed inset-x-0 z-50 flex justify-center px-3"
          style={{ top: "calc(var(--top-inset) + 8px)" }}
          initial={reduce ? { opacity: 0 } : { opacity: 0, y: -24, scale: 0.96 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={reduce ? { opacity: 0 } : { opacity: 0, y: -24, scale: 0.96 }}
          transition={{ type: "spring", bounce: 0.25, duration: 0.45 }}
          role="status"
        >
          <div className="material flex w-full max-w-md items-center gap-3 rounded-2xl py-2 pr-2 pl-3" style={{ boxShadow: "0 8px 30px rgba(0,0,0,.18)", border: "0.5px solid var(--material-edge)" }}>
            <span className="text-2xl" aria-hidden>{game?.emoji ?? "🎲"}</span>
            <span className="min-w-0 flex-1">
              <span className="t-sub block truncate font-semibold">{host} will entscheiden</span>
              <span className="t-footnote block truncate" style={{ color: "var(--label-2)" }}>{game?.title} · Steig ein</span>
            </span>
            <Link href={`/entscheiden?s=${invite.id}`} className="btn btn-primary btn-sm pressable">Mitspielen</Link>
            <button className="pressable flex h-8 w-8 items-center justify-center rounded-full" aria-label="Hinweis schließen" onClick={() => setDismissed((d) => [...d, invite.id])}>
              <IconClose size={16} />
            </button>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
