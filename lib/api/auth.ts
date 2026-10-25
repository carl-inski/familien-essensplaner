import "server-only";
import { NextResponse } from "next/server";
import { checkBearer } from "./recipes";

/** Prüft den Bearer-Token; liefert ihn zurück oder eine fertige Fehlerantwort */
export function requireRecipesToken(request: Request): { token: string } | { response: NextResponse } {
  const expected = process.env.RECIPES_API_TOKEN;
  const result = checkBearer(request.headers.get("authorization"), expected);
  if (result === "not-configured") return { response: NextResponse.json({ error: "Schnittstelle nicht eingerichtet" }, { status: 503 }) };
  if (result === "unauthorized") return { response: NextResponse.json({ error: "Nicht autorisiert" }, { status: 401, headers: { "WWW-Authenticate": "Bearer" } }) };
  return { token: expected!.trim() };
}
