import SwiftUI

@MainActor
@Observable
final class AppPreferences {
    private static let hapticsKey = "hapticsEnabled"

    var hapticsEnabled = UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Self.hapticsKey) }
    }
}

@main
struct GnocchiApp: App {
    @State private var preferences = AppPreferences()
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            content
                .environment(session)
                .environment(preferences)
        }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-household") {
            HouseholdTabs(email: "demo@example.invalid", store: .demo(includeSampleRecipes: true))
        } else if ProcessInfo.processInfo.arguments.contains("--demo-onboarding") {
            HouseholdTabs(email: "demo@example.invalid", store: .demo(onboarding: true))
        } else if ProcessInfo.processInfo.arguments.contains("--demo-welcome") {
            // Onboarding ansehen, ohne etwas zu speichern oder anzumelden
            OnboardingFlow { _ in }
        } else {
            productionContent
        }
        #else
        productionContent
        #endif
    }

    private var productionContent: some View {
        RootView()
            .task { await session.start() }
            .onOpenURL { url in Task { await session.open(url) } }
            .alert("Gnocchi", isPresented: Binding(
                get: { session.linkError != nil }, set: { if !$0 { session.linkError = nil } }
            )) {
                Button("OK", role: .cancel) { session.linkError = nil }
            } message: { Text(session.linkError ?? "") }
    }
}
