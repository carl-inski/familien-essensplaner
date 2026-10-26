"use client";

import { useParams } from "next/navigation";
import { RecipeView } from "@/components/recipe-view";

export default function RecipeDetailPage() {
  const { id } = useParams<{ id: string }>();
  return <RecipeView id={id} />;
}
