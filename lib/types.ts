export type Diet = "fleisch" | "fisch" | "vegetarisch";
export type Meal = "fruehstueck" | "mittag" | "abend";
export type AttendanceStatus = "da" | "weg";
export type PlanStatus = "geplant" | "gekocht" | "ausgefallen";

export interface Household {
  id: string;
  name: string;
}

export type DefaultWeek = Partial<Record<WeekdayKey, Partial<Record<Meal, AttendanceStatus>>>>;
export type WeekdayKey = "mon" | "tue" | "wed" | "thu" | "fri" | "sat" | "sun";

export interface Member {
  id: string;
  household_id: string;
  name: string;
  email: string | null;
  user_id: string | null;
  role: "admin" | "member";
  default_week: DefaultWeek;
  position: number;
}

export interface Cookbook {
  id: string;
  household_id: string;
  title: string;
  authors: string[];
  publisher: string | null;
  year: number | null;
  isbn: string | null;
  cover_url: string | null;
  notes: string | null;
}

export interface Ingredient {
  id?: string;
  recipe_id?: string;
  position: number;
  group_name: string | null;
  name: string;
  amount: number | null;
  unit: string | null;
  amount_text: string | null;
  aisle?: string | null;
}

export interface Nutrition {
  [key: string]: string;
}

export interface Recipe {
  id: string;
  household_id: string;
  title: string;
  subtitle: string | null;
  source: string | null;
  categories: string[];
  diet: Diet | null;
  time_text: string | null;
  time_min: number | null;
  servings: number | null;
  servings_text: string | null;
  steps: string[];
  tip: string | null;
  nutrition: Nutrition | null;
  nutrition_estimated: boolean;
  cookbook_id: string | null;
  cookbook_page: number | null;
  cookbook_link_confirmed: boolean;
  tags: string[];
  image_url: string | null;
  variant_of: string | null;
  extra_meta: Record<string, string> | null;
  public_slug: string;
  created_at: string;
  updated_at: string;
  ep_recipe_ingredients?: Ingredient[];
  /** Anzahl Notizen (Supabase-Aggregat) */
  ep_recipe_notes?: { count: number }[];
}

export interface CookStats {
  recipe_id: string;
  last_cooked_on: string;
  times_cooked: number;
  days_since: number;
}

export interface Attendance {
  id: string;
  member_id: string;
  date: string;
  meal: Meal;
  status: AttendanceStatus;
  guests: number;
}

export interface MealPlanEntry {
  id: string;
  household_id: string;
  date: string;
  meal: Meal;
  recipe_id: string | null;
  leftover_of: string | null;
  cook_id: string | null;
  cook2_id: string | null;
  servings_override: number | null;
  status: PlanStatus;
  note: string | null;
}

export interface CookingHistoryEntry {
  id: string;
  household_id: string;
  recipe_id: string;
  cooked_on: string;
  meal_plan_id: string | null;
  cook_id: string | null;
  servings: number | null;
  source: "plan" | "manuell" | "nachgetragen";
}

export interface ShoppingItem {
  name: string;
  amount: number | null;
  unit: string | null;
  text: string;
  aisle: string;
  recipes: string[];
}
