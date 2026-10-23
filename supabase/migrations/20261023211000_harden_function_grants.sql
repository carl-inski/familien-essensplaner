-- Trigger-Funktionen brauchen kein EXECUTE für API-Rollen (Trigger feuern trotzdem).
revoke execute on function public.ep_members_guard() from public, anon, authenticated;
revoke execute on function public.ep_recipes_search_trigger() from public, anon, authenticated;
revoke execute on function public.ep_ingredients_search_trigger() from public, anon, authenticated;
revoke execute on function public.ep_meal_plan_cook_check() from public, anon, authenticated;
revoke execute on function public.ep_meal_plan_history() from public, anon, authenticated;

-- RLS-Helfer nur für eingeloggte Nutzer (Policies laufen als authenticated).
revoke execute on function public.ep_my_household_ids() from public, anon;
revoke execute on function public.ep_is_admin(uuid) from public, anon;
grant execute on function public.ep_my_household_ids() to authenticated;
grant execute on function public.ep_is_admin(uuid) to authenticated;

-- Bewusst öffentlich (Bring!-Import): ep_public_recipe, ep_public_shopping – nur per nicht erratbarem Slug.
