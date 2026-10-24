"use client";

import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from "react";

interface ToastData {
  id: number;
  text: string;
  tone?: "default" | "warning" | "error";
  action?: { label: string; run: () => void };
}

const Ctx = createContext<(t: Omit<ToastData, "id">) => void>(() => {});

export function useToast() {
  return useContext(Ctx);
}

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<ToastData | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reduce = useReducedMotion();

  const show = useCallback((t: Omit<ToastData, "id">) => {
    if (timer.current) clearTimeout(timer.current);
    const data = { ...t, id: Date.now() };
    setToast(data);
    timer.current = setTimeout(() => setToast((cur) => (cur?.id === data.id ? null : cur)), t.action ? 5000 : 3200);
  }, []);

  return (
    <Ctx value={show}>
      {children}
      <div className="toast-dock pointer-events-none fixed right-0 z-[60] flex justify-center px-4" aria-live="polite">
        <AnimatePresence>
          {toast && (
            <motion.div
              key={toast.id}
              className="material pointer-events-auto flex max-w-md items-center gap-3 rounded-2xl px-4 py-3 shadow-lg"
              style={{
                boxShadow: "0 8px 30px rgba(0,0,0,.18)",
                border: "0.5px solid var(--material-edge)",
                color: toast.tone === "error" ? "var(--red)" : undefined,
              }}
              initial={reduce ? { opacity: 0 } : { opacity: 0, y: 16, scale: 0.96, filter: "blur(6px)" }}
              animate={{ opacity: 1, y: 0, scale: 1, filter: "blur(0px)" }}
              exit={reduce ? { opacity: 0 } : { opacity: 0, y: 16, scale: 0.96, filter: "blur(6px)" }}
              transition={{ type: "spring", bounce: 0, duration: 0.35 }}
            >
              {toast.tone === "warning" && <span aria-hidden>⚠︎</span>}
              <span className="t-sub font-medium">{toast.text}</span>
              {toast.action && (
                <button
                  className="pressable t-sub font-semibold"
                  style={{ color: "var(--accent)" }}
                  onClick={() => {
                    toast.action?.run();
                    setToast(null);
                  }}
                >
                  {toast.action.label}
                </button>
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </Ctx>
  );
}
