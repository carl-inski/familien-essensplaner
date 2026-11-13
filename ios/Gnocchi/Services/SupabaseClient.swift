import Foundation
import Supabase

/// Dasselbe Supabase-Projekt wie die Web-App. Der Publishable Key ist öffentlich
/// (steckt auch in der Web-App); Zugriffe schützt die Datenbank mit RLS.
enum Backend {
    static let url = URL(string: "https://xamzkxjjiwyrraavlgxw.supabase.co")!
    static let publishableKey = "sb_publishable_o4__9vGXh_rkv-ShEcClfw_ZygaByW8"

    static let client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)
}
