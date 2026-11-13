import Testing
@testable import Gnocchi

@Suite("App")
struct AppSmokeTests {
    @Test("Backend zeigt auf das Projekt der Web-App")
    func backend() {
        #expect(Backend.url.host() == "xamzkxjjiwyrraavlgxw.supabase.co")
    }
}
