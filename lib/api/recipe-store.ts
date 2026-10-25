import "server-only";
import { anonClient } from "@/lib/public/data";
import type { Cookbook, Recipe } from "@/lib/types";
import type { RecipeStore } from "./recipes";

// Datenbankzugriff der Rezept-Schnittstelle: nur über die security-definer-RPCs
// ep_api_snapshot / ep_api_save_recipe. Der Haushalt ergibt sich dort aus dem
// (gehashten) Token – nie aus der Anfrage.

export function rpcRecipeStore(token: string): RecipeStore {
  const sb = anonClient();
  return {
    async snapshot() {
      const { data, error } = await sb.rpc("ep_api_snapshot", { p_token: token });
      if (error) throw new Error(error.message);
      const d = data as { recipes: Recipe[]; cookbooks: Cookbook[] };
      return { recipes: d.recipes ?? [], cookbooks: d.cookbooks ?? [] };
    },
    async save({ recipe, ingredients, existingId, createCookbook }) {
      const { data, error } = await sb.rpc("ep_api_save_recipe", {
        p_token: token,
        p_recipe: recipe,
        p_ingredients: ingredients,
        p_existing: existingId,
        p_cookbook_title: createCookbook,
      });
      if (error) throw new Error(error.message);
      return data as string;
    },
  };
}
