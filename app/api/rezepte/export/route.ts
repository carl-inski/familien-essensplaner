import { NextResponse, type NextRequest } from "next/server";
import { requireRecipesToken } from "@/lib/api/auth";
import { rpcRecipeStore } from "@/lib/api/recipe-store";
import { collectionToMarkdown } from "@/lib/markdown";
import { recipeToDraft } from "@/lib/recipe-draft";

// Ganze Sammlung als Markdown – wie der Export-Button in der App

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const auth = requireRecipesToken(request);
  if ("response" in auth) return auth.response;
  try {
    const { recipes, cookbooks } = await rpcRecipeStore(auth.token).snapshot();
    const byId = new Map(cookbooks.map((c) => [c.id, c]));
    const md = collectionToMarkdown(recipes.map((r) => recipeToDraft(r, byId)));
    return new NextResponse(md, { headers: { "Content-Type": "text/markdown; charset=utf-8", "Content-Disposition": 'inline; filename="rezeptsammlung.md"' } });
  } catch (e) {
    console.error("[api/rezepte/export]", e);
    return NextResponse.json({ error: "Lesen nicht möglich" }, { status: 500 });
  }
}
