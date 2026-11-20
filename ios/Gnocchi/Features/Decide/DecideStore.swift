import Foundation
import GnocchiCore
import Observation
import Supabase

struct GameSession: Decodable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case lobby, playing, done, cancelled }

    let id: String
    let created_by: String?
    var updated_at: Date
    var date: String?
    var meal: Meal?
    let suggested_date: String?
    let suggested_meal: Meal?
    let game: DecideGame
    var status: Status
    var round: Int
    var seed: Int
    var candidates: [String]
    var state: DecideState
    var winner_recipe_id: String?
}

struct GamePlayer: Decodable, Identifiable, Sendable {
    let member_id: String
    var round_done: Int
    var data: [String: DecideValue]
    var id: String { member_id }
}

@MainActor
@Observable
final class DecideStore {
    private let db = Backend.client
    private(set) var session: GameSession?
    private var lobby: GameSession?
    private var dismissedSessionID: String?
    private(set) var players: [GamePlayer] = []
    private(set) var busy = false
    private(set) var shuffling = false
    private(set) var checking = false
    var error: String?
    private var revision = UUID()

    func follow(family: Membership, demo: Bool) async {
        guard !demo else { return }
        let channel = db.channel("ep-ios-decide-\(family.id)-\(UUID())")
        let games = channel.postgresChange(AnyAction.self, table: "ep_decide_sessions")
        let participants = channel.postgresChange(AnyAction.self, table: "ep_decide_players")
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.poll(family: family) }
            group.addTask {
                do {
                    try await channel.subscribeWithError()
                    await self.refresh(family: family)
                    await withTaskGroup(of: Void.self) { updates in
                        updates.addTask { for await _ in games { await self.refresh(family: family) } }
                        updates.addTask { for await _ in participants { await self.refresh(family: family) } }
                    }
                } catch {
                    // Polling recovers missed events while the connection reconnects.
                }
            }
        }
        await db.removeChannel(channel)
    }

    private func poll(family: Membership) async {
        while !Task.isCancelled {
            await refresh(family: family)
            let playing = session?.status == .playing || lobby != nil
            try? await Task.sleep(for: .seconds(playing ? 3 : 12))
        }
    }

    private func refresh(family: Membership) async {
        guard !busy, !checking, !Task.isCancelled else { return }
        checking = true
        defer { checking = false }
        let request = UUID()
        revision = request
        do {
            let current: GameSession?
            if let id = session?.id, session?.status != .cancelled {
                current = try await fetchSession(family: family, id: id)
            } else {
                current = try await fetchOpenSession(family: family)
            }
            let shown = current.flatMap { $0.id == dismissedSessionID ? nil : $0 }
            let participants: [GamePlayer]
            if let shown {
                participants = try await db.from("ep_decide_players").select("member_id,round_done,data")
                    .eq("session_id", value: shown.id).order("joined_at").execute().value
            } else {
                participants = []
            }
            let invitation: GameSession?
            if current?.status == .done {
                let open = try? await fetchOpenSession(family: family)
                invitation = open?.status == .lobby ? open : nil
            } else {
                invitation = current?.status == .lobby ? current : nil
            }
            guard request == revision, !Task.isCancelled else { return }
            session = shown
            lobby = invitation
            players = participants
            if error == "Die Familienrunde konnte nicht geladen werden." { error = nil }
            try await advanceIfReady(family: family, demo: false)
        } catch {
            guard !Task.isCancelled, request == revision else { return }
            if session == nil && self.error == nil { self.error = "Die Familienrunde konnte nicht geladen werden." }
        }
    }

    private func fetchOpenSession(family: Membership) async throws -> GameSession? {
        let cutoff = Date.now.addingTimeInterval(-7200).ISO8601Format()
        return try await db.from("ep_decide_sessions").select()
            .eq("household_id", value: family.id).in("status", values: ["lobby", "playing"])
            .gte("updated_at", value: cutoff).limit(1).maybeSingle().execute().value
    }

    func invitation(for memberID: String) -> GameSession? {
        guard let lobby, lobby.created_by != memberID,
              Date.now.timeIntervalSince(lobby.updated_at) < 7_200 else { return nil }
        if session?.id == lobby.id, players.contains(where: { $0.id == memberID }) { return nil }
        return lobby
    }

    func openInvitation(_ id: String) {
        guard let lobby, lobby.id == id, session?.id != id, !busy else { return }
        revision = UUID()
        dismissedSessionID = nil
        session = lobby
        players = []
    }

    private func fetchSession(family: Membership, id: String) async throws -> GameSession? {
        try await db.from("ep_decide_sessions").select()
            .eq("household_id", value: family.id).eq("id", value: id).maybeSingle().execute().value
    }

    func create(game: DecideGame, family: Membership, recipes: [Recipe], folder: String?, slot: MealSlot?, demo: Bool) async {
        await mutate(family: family, demo: demo) {
            let seed = Int.random(in: 0..<2_147_483_647)
            let candidates = try await drawCandidates(game: game, family: family, recipes: recipes,
                                                      folder: folder, slot: slot, seed: seed, demo: demo)
            if demo {
                dismissedSessionID = nil
                session = GameSession(id: UUID().uuidString, created_by: family.memberID, updated_at: .now,
                                      date: nil, meal: nil, suggested_date: slot?.date, suggested_meal: slot?.meal, game: game,
                                      status: .lobby, round: 0, seed: seed, candidates: candidates,
                                      state: Decide.initial(game: game, candidates: candidates), winner_recipe_id: nil)
                players = [GamePlayer(member_id: family.memberID, round_done: -1, data: [:])]
                if let id = session?.id { UserDefaults.standard.set(folder, forKey: lobbyFolderKey(id)) }
            } else {
                struct Created: Decodable {
                    let id: String
                    let already_open: Bool
                }
                let args: [String: DecideValue] = [
                    "p_game": .string(game.rawValue), "p_seed": .number(Double(seed)),
                    "p_candidates": .array(candidates.map(DecideValue.string)),
                    "p_suggested_date": slot.map { .string($0.date) } ?? .null,
                    "p_suggested_meal": slot.map { .string($0.meal.rawValue) } ?? .null
                ]
                let rows: [Created] = try await db.rpc("ep_decide_create", params: args).execute().value
                guard let row = rows.first else { throw GameFailure("Die Runde konnte nicht eröffnet werden.") }
                if !row.already_open { UserDefaults.standard.set(folder, forKey: lobbyFolderKey(row.id)) }
                let opened = try await fetchSession(family: family, id: row.id)
                dismissedSessionID = nil
                session = opened
            }
        }
    }

    func reshuffle(family: Membership, recipes: [Recipe], demo: Bool) async {
        guard !busy, !shuffling, let session, session.status == .lobby, session.created_by == family.memberID else { return }
        shuffling = true
        defer { shuffling = false }
        await mutate(family: family, demo: demo) {
            let slot: MealSlot? = if let date = session.suggested_date, let meal = session.suggested_meal {
                MealSlot(date: date, meal: meal)
            } else {
                nil
            }
            let folder = UserDefaults.standard.string(forKey: lobbyFolderKey(session.id))
            var seed = Int.random(in: 0..<2_147_483_647)
            if seed == session.seed { seed = (seed + 1) % 2_147_483_647 }
            let candidates = try await drawCandidates(game: session.game, family: family, recipes: recipes,
                                                      folder: folder, slot: slot, seed: seed, demo: demo)
            if demo {
                self.session?.seed = seed
                self.session?.candidates = candidates
                self.session?.state = Decide.initial(game: session.game, candidates: candidates)
            } else {
                struct Patch: Encodable {
                    let seed: Int
                    let candidates: [String]
                }
                let rows: [GameSession] = try await db.from("ep_decide_sessions").update(Patch(seed: seed, candidates: candidates))
                    .eq("id", value: session.id).eq("household_id", value: family.id)
                    .eq("created_by", value: family.memberID).eq("status", value: "lobby").eq("seed", value: session.seed)
                    .select().execute().value
                guard let updated = rows.first else { throw GameFailure("Die Runde hat sich inzwischen geändert.") }
                self.session = updated
                lobby = updated
            }
        }
    }

    private func drawCandidates(game: DecideGame, family: Membership, recipes: [Recipe], folder: String?,
                                slot: MealSlot?, seed: Int, demo: Bool) async throws -> [String] {
        let today = BerlinDay.today()
        let pool = recipes.map {
            DecideCandidate(id: $0.id, cookbookID: $0.cookbookID,
                            tags: $0.tags ?? [], categories: $0.categories ?? [], folderID: $0.folderID)
        }
        let recent: [CookingDate]
        let plan: [MealPlanEntry]
        if demo {
            recent = []
            plan = []
        } else {
            async let history: [CookingDate] = db.from("ep_cooking_history").select("recipe_id,cooked_on")
                .eq("household_id", value: family.id)
                .order("cooked_on", ascending: false).execute().value
            async let entries: [MealPlanEntry] = db.from("ep_meal_plan").select()
                .eq("household_id", value: family.id).gte("date", value: BerlinDay.adding(-3, to: today))
                .lte("date", value: BerlinDay.adding(14, to: today)).order("date").order("meal", ascending: false)
                .execute().value
            (recent, plan) = try await (history, entries)
        }
        let stats = Dictionary(recent.map { ($0.recipe_id, $0.cooked_on) }, uniquingKeysWith: max)
        let candidates = DecideCandidates.pick(pool, latest: stats, plan: plan.filter { $0.slot != slot }, today: today,
                                              seed: seed, count: game.candidateCount, folderID: folder)
        guard candidates.count >= 2 else { throw GameFailure("Zum Spielen braucht ihr mindestens zwei passende Rezepte.") }
        return candidates
    }

    private func lobbyFolderKey(_ id: String) -> String { "gnocchi.decide.folder.\(id)" }

    func start(family: Membership, demo: Bool) async {
        guard let session, session.status == .lobby,
              players.contains(where: { $0.id == family.memberID }) else { return }
        await mutate(family: family, demo: demo) {
            let state = Decide.initial(game: session.game, candidates: session.candidates)
            if demo {
                self.session?.status = .playing
                self.session?.updated_at = .now
                self.session?.state = state
            } else {
                struct Patch: Encodable { let status = "playing"; let round = 0; let state: DecideState }
                let rows: [GameSession] = try await db.from("ep_decide_sessions").update(Patch(state: state))
                    .eq("id", value: session.id).eq("household_id", value: family.id)
                    .eq("status", value: "lobby").eq("seed", value: session.seed).select().execute().value
                guard let updated = rows.first else { throw GameFailure("Die Runde hat sich inzwischen geändert.") }
                self.session = updated
            }
        }
    }

    func setJoined(_ joined: Bool, family: Membership, demo: Bool) async {
        guard let session, session.status == .lobby else { return }
        await mutate(family: family, demo: demo) {
            if demo {
                players.removeAll { $0.id == family.memberID }
                if joined { players.append(GamePlayer(member_id: family.memberID, round_done: -1, data: [:])) }
            } else if joined {
                do {
                    try await db.from("ep_decide_players").insert(["session_id": session.id, "member_id": family.memberID]).execute()
                } catch let error as PostgrestError where error.code == "23505" {
                    // Joining the same room from another device already succeeded.
                }
            } else {
                try await db.from("ep_decide_players").delete().eq("session_id", value: session.id)
                    .eq("member_id", value: family.memberID).execute()
            }
        }
    }

    func exit(_ expected: GameSession, family: Membership, demo: Bool) async {
        guard let session, session.id == expected.id, session.status == expected.status,
              session.status == .lobby || session.status == .playing else { return }
        await mutate(family: family, demo: demo) {
            let host = session.created_by == family.memberID
            if !demo {
                if host {
                    let rows: [GameSession] = try await db.from("ep_decide_sessions").update(["status": "cancelled"])
                        .eq("household_id", value: family.id).eq("id", value: session.id)
                        .eq("created_by", value: family.memberID).eq("status", value: session.status.rawValue)
                        .select().execute().value
                    guard !rows.isEmpty else { throw GameFailure("Die Runde hat sich inzwischen geändert.") }
                } else {
                    try await db.from("ep_decide_players").delete().eq("session_id", value: session.id)
                        .eq("member_id", value: family.memberID).execute()
                }
            }
            if host { UserDefaults.standard.removeObject(forKey: lobbyFolderKey(session.id)) }
            dismissedSessionID = session.id
            self.session = nil
            players = []
        }
    }

    func removePlayer(_ id: String, family: Membership, demo: Bool) async {
        guard let session, id != family.memberID, session.status == .playing,
              (players.first(where: { $0.id == id })?.round_done ?? session.round) < session.round else { return }
        await mutate(family: family, demo: demo) {
            if !demo {
                try await db.from("ep_decide_players").delete().eq("session_id", value: session.id)
                    .eq("member_id", value: id).lt("round_done", value: session.round).execute()
            } else {
                players.removeAll { $0.id == id }
            }
        }
    }

    func submit(_ submission: DecideValue, for round: Int, family: Membership, demo: Bool) async {
        guard let session, session.status == .playing, session.round == round,
              let index = players.firstIndex(where: { $0.id == family.memberID }),
              players[index].round_done < round else { return }
        await mutate(family: family, demo: demo) {
            var data = players[index].data
            data[String(round)] = submission
            if demo {
                players[index].data = data
                players[index].round_done = round
            } else {
                struct Vote: Encodable { let round_done: Int; let data: [String: DecideValue] }
                try await db.from("ep_decide_players").update(Vote(round_done: round, data: data))
                    .eq("session_id", value: session.id).eq("member_id", value: family.memberID)
                    .lt("round_done", value: round).execute()
            }
        }
    }

    func schedule(_ slot: MealSlot, expected: MealPlanEntry?, family: Membership, household: HouseholdStore) async -> Bool {
        guard let session, session.status == .done, let winner = session.winner_recipe_id, session.date == nil else {
            error = "Die Runde kann nicht mehr eingeplant werden."
            return false
        }
        let expectedSlot = expected?.schedulingSnapshot ?? .null
        var saved = false
        await mutate(family: family, demo: household.isDemo) {
            if household.isDemo {
                let current = household.plan.first { $0.slot == slot }
                guard (current?.schedulingSnapshot ?? .null) == expectedSlot else {
                    throw GameFailure("Der Termin wurde inzwischen geändert. Prüfe ihn erneut.")
                }
                guard await household.scheduleRecipe(winner, at: slot, expected: expected) else {
                    throw GameFailure("Das Gericht konnte nicht eingeplant werden.")
                }
                self.session?.date = slot.date
                self.session?.meal = slot.meal
            } else {
                let parameters: JSONObject = [
                    "p_session": .string(session.id), "p_date": .string(slot.date),
                    "p_meal": .string(slot.meal.rawValue), "p_expected_slot": expectedSlot
                ]
                do {
                    try await db.rpc("ep_decide_schedule_checked", params: parameters).execute()
                } catch let error as PostgrestError where error.code == "PT409" {
                    throw GameFailure("Der Termin wurde inzwischen geändert. Prüfe ihn erneut.")
                }
                if let start = household.weekStart { await household.loadWeek(from: start) }
            }
            saved = true
        }
        return saved
    }

    func closeResult() {
        guard session?.status == .done || session?.status == .cancelled else { return }
        revision = UUID()
        if let id = session?.id { UserDefaults.standard.removeObject(forKey: lobbyFolderKey(id)) }
        session = nil
        players = []
    }

    private func mutate(family: Membership, demo: Bool, action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        revision = UUID()
        do {
            try await action()
            if demo { try await advanceIfReady(family: family, demo: true) }
        } catch let failure as GameFailure {
            error = failure.message
        } catch {
            self.error = "Die Änderung konnte nicht gespeichert werden. Versuche es erneut."
        }
        busy = false
        if !demo { await refresh(family: family) }
    }

    private func advanceIfReady(family: Membership, demo: Bool) async throws {
        guard let snapshot = session, snapshot.status == .playing, !players.isEmpty,
              players.contains(where: { $0.id == family.memberID }),
              players.allSatisfy({ $0.round_done >= snapshot.round }),
              let next = Decide.advance(game: snapshot.game, state: snapshot.state,
                                        submissions: players.map { $0.data[String(snapshot.round)] ?? .null },
                                        candidates: snapshot.candidates, seed: snapshot.seed, round: snapshot.round) else { return }
        if demo {
            session?.updated_at = .now
            session?.state = next.state
            if let winner = next.winner {
                session?.winner_recipe_id = winner
                session?.status = .done
            } else {
                session?.round += 1
            }
        } else if let winner = next.winner {
            struct Finish: Encodable {
                let p_session: String
                let p_round: Int
                let p_recipe: String
                let p_state: DecideState
            }
            try await db.rpc("ep_decide_finish", params: Finish(p_session: snapshot.id, p_round: snapshot.round,
                                                               p_recipe: winner, p_state: next.state)).execute()
        } else {
            struct Patch: Encodable { let round: Int; let state: DecideState }
            try await db.from("ep_decide_sessions").update(Patch(round: snapshot.round + 1, state: next.state))
                .eq("household_id", value: family.id).eq("id", value: snapshot.id)
                .eq("status", value: "playing").eq("round", value: snapshot.round).execute()
        }
    }

    static func clockOffset() async -> TimeInterval {
        var best: (duration: TimeInterval, offset: TimeInterval)?
        for _ in 0..<3 {
            guard !Task.isCancelled else { break }
            let start = Date.now.timeIntervalSince1970
            guard let server: Double = try? await Backend.client.rpc("ep_server_now").execute().value else { break }
            let end = Date.now.timeIntervalSince1970
            let rtt = end - start
            if best == nil || rtt < (best?.duration ?? .infinity) {
                best = (rtt, server / 1000 - (start + end) / 2)
            }
        }
        return best?.offset ?? 0
    }
}

private struct CookingDate: Decodable, Sendable { let recipe_id: String; let cooked_on: String }

private struct GameFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
