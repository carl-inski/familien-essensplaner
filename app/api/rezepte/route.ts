import { NextResponse, type NextRequest } from "next/server";
import { requireRecipesToken } from "@/lib/api/auth";
import { rpcRecipeStore } from "@/lib/api/recipe-store";
import { importRecipes, parseModus, parsePayload, recipeSummaries } from "@/lib/api/recipes";

// Schnittstelle für externe Assistenten: Rezepte im Format der
// Rezeptsammlung (Markdown) oder als JSON anlegen; Liste zum Abgleich.

export const dynamic = "force-dynamic";

const MAX_BYTES = 1_000_000;

export async function POST(request: NextRequest) {
  const auth = requireRecipesToken(request);
  if ("response" in auth) return auth.response;

  const modus = parseModus(request.nextUrl.searchParams.get("modus"));
  if (!modus) return NextResponse.json({ error: "modus muss neu, ueberspringen oder ueberschreiben sein" }, { status: 400 });
  const dryRun = ["1", "true", "ja"].includes(request.nextUrl.searchParams.get("dry_run") ?? "");

  const body = await request.text();
  if (body.length > MAX_BYTES) return NextResponse.json({ error: "Anfrage zu groß (max. 1 MB)" }, { status: 413 });
  if (!body.trim()) return NextResponse.json({ error: "Leerer Body" }, { status: 400 });

  try {
    const parsed = parsePayload(request.headers.get("content-type"), body);
    const result = await importRecipes(rpcRecipeStore(auth.token), parsed, modus, dryRun);
    return NextResponse.json(result.body, { status: result.status });
  } catch (e) {
    console.error("[api/rezepte]", e);
    return NextResponse.json({ error: "Speichern nicht möglich" }, { status: 500 });
  }
}

export async function GET(request: NextRequest) {
  const auth = requireRecipesToken(request);
  if ("response" in auth) return auth.response;
  try {
    const { recipes, cookbooks } = await rpcRecipeStore(auth.token).snapshot();
    return NextResponse.json(recipeSummaries(recipes, cookbooks));
  } catch (e) {
    console.error("[api/rezepte]", e);
    return NextResponse.json({ error: "Lesen nicht möglich" }, { status: 500 });
  }
}
