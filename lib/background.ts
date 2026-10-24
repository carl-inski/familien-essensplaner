// Supabase-Abfragen sind „lazy“: Sie gehen erst raus, wenn jemand .then() aufruft.
// `void sb.from(...).insert(...)` schickt deshalb nichts ab. inBackground startet
// die Abfrage, ohne auf sie zu warten; Fehler landen nur in der Konsole.

export function inBackground(query: PromiseLike<{ error: { message: string } | null }>, label = "Hintergrund"): void {
  query.then(
    ({ error }) => {
      if (error) console.warn(`[${label}]`, error.message);
    },
    (e: unknown) => console.warn(`[${label}]`, e),
  );
}
