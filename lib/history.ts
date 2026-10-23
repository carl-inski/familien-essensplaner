// Spiegel der View ep_recipe_cook_stats für optimistische Updates im Client

import { daysBetween } from "./dates";
import type { CookStats } from "./types";

export function cookStatsFromHistory(history: { recipe_id: string; cooked_on: string }[], today: string): Map<string, CookStats> {
  const stats = new Map<string, CookStats>();
  for (const h of history) {
    const s = stats.get(h.recipe_id);
    if (!s) {
      stats.set(h.recipe_id, { recipe_id: h.recipe_id, last_cooked_on: h.cooked_on, times_cooked: 1, days_since: 0 });
    } else {
      s.times_cooked += 1;
      if (h.cooked_on > s.last_cooked_on) s.last_cooked_on = h.cooked_on;
    }
  }
  for (const s of stats.values()) s.days_since = daysBetween(s.last_cooked_on, today);
  return stats;
}
