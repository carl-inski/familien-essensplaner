"use client";

import { useParams } from "next/navigation";
import { useApp } from "@/components/app-data";
import { RecipeForm } from "@/components/recipe-form";
import { Empty } from "@/components/ui";

export default function EditRecipePage() {
  const { id } = useParams<{ id: string }>();
  const recipe = useApp().recipesById.get(id);
  if (!recipe) return <Empty title="Rezept nicht gefunden" />;
  return <RecipeForm recipe={recipe} />;
}
