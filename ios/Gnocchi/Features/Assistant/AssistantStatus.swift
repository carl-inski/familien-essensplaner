import Foundation

struct AssistantStatus: Decodable, Sendable {
    struct Models: Decodable, Sendable { let text: String }

    struct Limits: Decodable, Sendable {
        let dailyCallsPerMember: Double
        let monthlyBudgetEur: Double
    }

    struct Usage: Decodable, Sendable {
        let monthCalls: Int
        let monthCacheHits: Int
        let monthCostEur: Double
        let myCallsToday: Int

        enum CodingKeys: String, CodingKey {
            case monthCalls = "month_calls"
            case monthCacheHits = "month_cache_hits"
            case monthCostEur = "month_cost_eur"
            case myCallsToday = "my_calls_today"
        }
    }

    let enabled: Bool
    let reason: String?
    let provider: String
    let models: Models?
    let limits: Limits
    let usage: Usage

    var budgetShare: Double {
        min(1, max(0, usage.monthCostEur / max(limits.monthlyBudgetEur, 0.0001)))
    }

    static let demo = Self(enabled: true, reason: nil, provider: "mock", models: Models(text: "Gnocchi-Demo"),
                           limits: Limits(dailyCallsPerMember: 50, monthlyBudgetEur: 5),
                           usage: Usage(monthCalls: 14, monthCacheHits: 2, monthCostEur: 0.24, myCallsToday: 3))
}

struct AssistantConnectionTest: Decodable, Sendable {
    let text: String
    let ms: Double
}

extension AssistantTransport {
    static func fetchStatus() async throws -> AssistantStatus {
        try await fetch(path: "api/ai/status", method: "GET")
    }

    static func testConnection() async throws -> AssistantConnectionTest {
        try await fetch(path: "api/ai/test", method: "POST")
    }

    private static func fetch<Response: Decodable & Sendable>(path: String, method: String) async throws -> Response {
        var request = try await authorizedRequest(path: path, timeout: 25)
        request.httpMethod = method
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let body = try? JSONDecoder().decode([String: String].self, from: data)
            throw AssistantFailure.message(body?["error"] ?? "Der KI-Dienst konnte nicht erreicht werden.")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
