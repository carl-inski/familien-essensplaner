import Foundation
import Supabase

/// Dasselbe Supabase-Projekt wie die Web-App. Der Publishable Key ist öffentlich
/// (steckt auch in der Web-App); Zugriffe schützt die Datenbank mit RLS.
enum Backend {
    static let site = URL(string: "https://familien-essensplaner-umber.vercel.app")!
    static let url = URL(string: "https://xamzkxjjiwyrraavlgxw.supabase.co")!
    static let publishableKey = "sb_publishable_o4__9vGXh_rkv-ShEcClfw_ZygaByW8"

    static let client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)

    /// Hält eine Ansicht live: lädt nach, sobald sich eine der Tabellen in der Familie ändert.
    /// Alle Ansichten teilen sich einen privaten Broadcast-Kanal je Familie (`ep:household:<id>`,
    /// Migration 20261119100000_realtime_haushalt.sql). Ohne Verbindung wird alle 8 s per REST gelesen.
    @MainActor
    static func watchChanges(using client: SupabaseClient, household: String, tables: [String],
                             refresh: @escaping @MainActor @Sendable () async -> Void) async {
        let wanted = Set(tables)
        let changes = HouseholdLive.shared.stream(client: client, household: household)
        let (updates, pending) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in updates { await refresh() }
            }
            group.addTask {
                // Leere Tabelle = (wieder) verbunden: einmal alles frisch laden.
                for await table in changes where table.isEmpty || wanted.contains(table) { pending.yield() }
            }
            group.addTask {
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(8)) } catch { return }
                    if client.realtimeV2.status != .connected { pending.yield() }
                }
            }
            await group.next()
            pending.finish()
            group.cancelAll()
        }
    }

    static func bringURL(for publicURL: URL) -> URL? {
        var components = URLComponents(string: "https://api.getbring.com/rest/bringrecipes/deeplink")
        components?.queryItems = [
            URLQueryItem(name: "url", value: publicURL.absoluteString),
            URLQueryItem(name: "source", value: "web")
        ]
        return components?.url
    }
}

/// Ein Kanal je Familie für alle Ansichten. supabase-swift liefert für dasselbe Thema denselben
/// Kanal zurück; darum zählt diese Klasse die Zuhörer und schließt erst beim letzten.
@MainActor
final class HouseholdLive {
    static let shared = HouseholdLive()

    private struct Entry {
        var listeners: [UUID: AsyncStream<String>.Continuation] = [:]
        var task: Task<Void, Never>?
    }

    private var entries: [String: Entry] = [:]

    func stream(client: SupabaseClient, household: String) -> AsyncStream<String> {
        let key = household.lowercased()
        let id = UUID()
        let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(8))
        var entry = entries[key] ?? Entry()
        entry.listeners[id] = continuation
        if entry.task == nil {
            entry.task = Task { await self.run(client: client, household: key) }
        }
        entries[key] = entry
        continuation.onTermination = { _ in
            Task { @MainActor in HouseholdLive.shared.remove(id, household: key) }
        }
        return stream
    }

    private func remove(_ id: UUID, household: String) {
        guard var entry = entries[household] else { return }
        entry.listeners[id] = nil
        if entry.listeners.isEmpty {
            entry.task?.cancel()
            entries[household] = nil
        } else {
            entries[household] = entry
        }
    }

    private func emit(_ table: String, household: String) {
        entries[household]?.listeners.values.forEach { $0.yield(table) }
    }

    private func run(client: SupabaseClient, household: String) async {
        while !Task.isCancelled {
            let channel = client.channel("ep:household:\(household)") { $0.isPrivate = true }
            let messages = channel.broadcastStream(event: "change")
            do {
                try await channel.subscribeWithError()
                emit("", household: household)
                for await message in messages {
                    let table = message["payload"]?.objectValue?["table"]?.stringValue ?? ""
                    emit(table, household: household)
                }
            } catch {
                // Abgelehnt oder getrennt: unten neu verbinden, REST-Abfragen überbrücken.
            }
            await client.removeChannel(channel)
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
        }
    }
}
