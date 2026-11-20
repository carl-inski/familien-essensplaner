import SwiftUI

struct AssistantSettingsView: View {
    @Environment(AssistantStore.self) private var assistant
    @Environment(HouseholdStore.self) private var household
    @State private var loading = false
    @State private var testing = false
    @State private var statusError: String?
    @State private var testMessage: String?
    @State private var testFailed = false
    @State private var provider = DemoAI.Provider.gemini
    @State private var model = DemoAI.Provider.gemini.defaultModel
    @State private var key = ""
    @State private var saved = false
    @State private var settingsMessage: String?

    var body: some View {
        List {
            if household.isDemo {
                demoSettings
            } else if let status = assistant.status {
                Section {
                    Label(status.enabled ? "KI ist eingerichtet" : "KI noch nicht eingerichtet", systemImage: "sparkles")
                    if status.enabled {
                        if let model = status.models?.text { LabeledContent("Modell", value: model) }
                        if status.provider == "mock" { Text("Testmodus").foregroundStyle(.secondary) }
                        Button("Verbindung testen", systemImage: "waveform.path") { Task { await test() } }
                            .disabled(testing)
                        if testing { ProgressView("Verbindung wird geprüft") }
                        if let testMessage {
                            Label(testMessage, systemImage: testFailed ? "exclamationmark.circle" : "checkmark.circle")
                                .foregroundStyle(testFailed ? Color.primary : Color.secondary)
                        }
                    } else if let reason = status.reason {
                        Text(reason).foregroundStyle(.secondary)
                    }
                }
                if status.enabled { usage(status) }
            } else if statusError == nil {
                ProgressView("KI-Status wird geladen")
            }
            if let statusError {
                Section {
                    Text(statusError)
                    Button("Erneut laden", systemImage: "arrow.clockwise") { Task { await reload() } }
                        .disabled(loading)
                }
            }
        }
        .navigationTitle("KI und Nutzung")
        .gnScreen()
        .task {
            if household.isDemo { loadDemoSettings() }
            else { await reload() }
        }
        .refreshable { if !household.isDemo { await reload() } }
    }

    private var demoSettings: some View {
        Group {
            Section {
                Picker("Anbieter", selection: $provider) {
                    ForEach(DemoAI.Provider.allCases) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: provider) { _, selected in
                    let current = DemoAI.configuration
                    model = current?.provider == selected ? (current?.model ?? selected.defaultModel) : selected.defaultModel
                    key = ""
                    settingsMessage = nil
                }
                TextField("Modell", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(saved ? "API-Schlüssel ersetzen" : "API-Schlüssel", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                Button("Speichern") { saveDemoSettings() }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                              !(DemoAI.configuration?.provider == provider && DemoAI.configuration?.model != model))
                if let settingsMessage { Text(settingsMessage).foregroundStyle(.secondary) }
            } header: {
                Text("API im Demo-Modus")
            } footer: {
                Text("Der Schlüssel bleibt im iOS-Schlüsselbund. Anfragen und angehängte Fotos gehen direkt an den Anbieter und werden über dein API-Konto abgerechnet.")
            }
            Section {
                Label(saved ? "Eigener API-Schlüssel aktiv" : "Demo mit Beispielantworten",
                      systemImage: saved ? "checkmark.circle" : "sparkles")
                Button("Verbindung testen", systemImage: "waveform.path") { Task { await test() } }
                    .disabled(!saved || testing)
                if testing { ProgressView("Verbindung wird geprüft") }
                if let testMessage {
                    Label(testMessage, systemImage: testFailed ? "exclamationmark.circle" : "checkmark.circle")
                }
                if saved {
                    Button("API-Schlüssel entfernen", role: .destructive) {
                        do {
                            try DemoAI.remove()
                            key = ""
                            testMessage = nil
                            loadDemoSettings()
                        } catch {
                            settingsMessage = error.localizedDescription
                        }
                    }
                    .disabled(testing)
                }
            }
        }
        .disabled(testing)
    }

    private func loadDemoSettings() {
        let current = DemoAI.configuration
        if let current {
            provider = current.provider
            model = current.model
        }
        saved = current != nil
        settingsMessage = nil
    }

    private func saveDemoSettings() {
        let entered = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = DemoAI.configuration
        let credential = entered.isEmpty && existing?.provider == provider ? (existing?.key ?? "") : entered
        do {
            try DemoAI.save(.init(provider: provider, model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                                  key: credential))
            key = ""
            testMessage = nil
            loadDemoSettings()
            settingsMessage = "API-Einstellungen gespeichert."
        } catch {
            settingsMessage = error.localizedDescription
        }
    }

    private func usage(_ status: AssistantStatus) -> some View {
        Section("Nutzung") {
            LabeledContent("Deine Anfragen heute", value: "\(status.usage.myCallsToday) von \(status.limits.dailyCallsPerMember.formatted(.number.locale(german)))")
            LabeledContent("Anfragen im Monat", value: status.usage.monthCalls.formatted(.number.locale(german)))
            LabeledContent("Aus dem Cache", value: status.usage.monthCacheHits.formatted(.number.locale(german)))
            ProgressView(value: status.budgetShare) {
                Text("Monatsbudget der Familie")
            } currentValueLabel: {
                Text("\(euro(status.usage.monthCostEur)) von \(euro(status.limits.monthlyBudgetEur))").monospacedDigit()
            }
            .tint(status.budgetShare > 0.8 ? Color.red : Color.accentColor)
        }
    }

    private var german: Locale { Locale(identifier: "de_DE") }

    private func euro(_ value: Double) -> String {
        value.formatted(.currency(code: "EUR").locale(german).precision(.fractionLength(2...(value > 0 && value < 0.01 ? 4 : 2))))
    }

    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            try await assistant.refreshStatus(demo: household.isDemo)
            statusError = nil
        } catch {
            if !Task.isCancelled { statusError = "Der KI-Status konnte nicht geladen werden." }
        }
    }

    private func test() async {
        guard !testing else { return }
        testing = true
        testMessage = nil
        defer { testing = false }
        do {
            let result: AssistantConnectionTest
            if household.isDemo, let config = DemoAI.configuration {
                result = try await DemoAI.test(config)
            } else {
                result = try await AssistantTransport.testConnection()
            }
            let seconds = (result.ms / 1_000).formatted(.number.locale(german).precision(.fractionLength(1)))
            testFailed = false
            testMessage = "\(result.text) (\(seconds) s)"
        } catch {
            testFailed = true
            testMessage = (error as? AssistantFailure)?.errorDescription ?? "Der Verbindungstest ist fehlgeschlagen."
        }
        if !household.isDemo { await reload() }
    }
}
