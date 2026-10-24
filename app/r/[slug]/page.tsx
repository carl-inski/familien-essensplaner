import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { scaleIngredients } from "@/lib/planning";
import { dishPhoto } from "@/lib/medien";
import { anonClient, jsonLd, requestOrigin } from "@/lib/public/data";
import type { Ingredient } from "@/lib/types";

// Öffentliche Rezeptseite für den Bring!-Import (schema.org/Recipe als JSON-LD)

interface PublicRecipe {
  title: string;
  subtitle: string | null;
  servings: number | null;
  servings_text: string | null;
  time_text: string | null;
  image_url: string | null;
  steps: string[];
  ingredients: Omit<Ingredient, "position">[];
}

async function load(slug: string) {
  const { data } = await anonClient().rpc("ep_public_recipe", { p_slug: slug });
  return (data as PublicRecipe | null) ?? null;
}

export const metadata: Metadata = { robots: { index: false, follow: false } };

export default async function PublicRecipePage({ params, searchParams }: PageProps<"/r/[slug]">) {
  const { slug } = await params;
  const sp = await searchParams;
  const recipe = await load(slug);
  if (!recipe) notFound();

  const requested = Number.parseInt(String(sp.p ?? ""), 10);
  const servings = Number.isFinite(requested) && requested > 0 && requested <= 60 ? requested : recipe.servings;
  const ingredients = scaleIngredients(
    recipe.ingredients.map((i, position) => ({ ...i, position, amount: i.amount === null ? null : Number(i.amount) })),
    recipe.servings,
    servings ?? recipe.servings ?? 1,
  );
  const origin = await requestOrigin();
  const example = dishPhoto(recipe.title);
  const storedImage = recipe.image_url
    ? recipe.image_url.startsWith("http") ? recipe.image_url : `${origin}${recipe.image_url}`
    : null;
  const image = storedImage ?? (example ? `${origin}${example.src}` : `${origin}/og?t=${encodeURIComponent(recipe.title)}`);

  const ld = {
    "@context": "https://schema.org",
    "@type": "Recipe",
    name: recipe.title,
    author: { "@type": "Organization", name: "Familien-Essensplaner" },
    image,
    recipeYield: String(servings ?? 1),
    recipeIngredient: ingredients.map((i) => i.text),
    ...(recipe.steps.length ? { recipeInstructions: recipe.steps.map((text) => ({ "@type": "HowToStep", text })) } : {}),
  };

  return (
    <main className="mx-auto max-w-xl px-5 py-10">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: jsonLd(ld) }} />
      <p className="t-footnote" style={{ color: "var(--label-2)" }}>Familien-Essensplaner</p>
      <h1 className="t-title mt-1">{recipe.title}</h1>
      {recipe.subtitle && <p className="t-sub mt-1" style={{ color: "var(--label-2)" }}>{recipe.subtitle}</p>}
      {(storedImage || example) && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={image} alt="" className="mt-4 aspect-[16/9] w-full object-cover" style={{ borderRadius: 16 }} />
      )}
      <p className="t-sub mt-3">{servings ? `${servings} Portionen` : recipe.servings_text}{recipe.time_text ? ` · ${recipe.time_text}` : ""}</p>
      <h2 className="t-section mt-6 mb-2">Zutaten</h2>
      <ul className="group">
        {ingredients.map((i, idx) => <li key={idx} className="row t-sub">{i.text}</li>)}
      </ul>
      {recipe.steps.length > 0 && (
        <>
          <h2 className="t-section mt-6 mb-2">Zubereitung</h2>
          <ol className="flex flex-col gap-2">
            {recipe.steps.map((s, idx) => <li key={idx} className="card t-sub px-4 py-3"><strong style={{ color: "var(--accent)" }}>{idx + 1}.</strong> {s}</li>)}
          </ol>
        </>
      )}
    </main>
  );
}
