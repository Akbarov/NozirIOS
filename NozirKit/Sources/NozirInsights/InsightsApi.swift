import Foundation
import NozirNetworking

/// `/v1/parent/home`, `/summaries/{daily,weekly}` and `/usage/{daily,apps}`
/// (backend `InsightsController`, `UsageController`).
public struct InsightsApi: InsightsService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static func childPath(_ id: UUID) -> String {
        "/v1/parent/children/\(id.uuidString.lowercased())"
    }

    public func home() async throws -> ParentHome {
        try await client.send(ApiRequest(method: .get, path: "/v1/parent/home"), as: ParentHome.self)
    }

    public func dailySummary(of childId: UUID, on date: LocalDate?) async throws -> InsightSummary {
        var query: [String: String] = [:]
        if let date {
            query["date"] = date.text
        }
        let request = ApiRequest(method: .get, path: Self.childPath(childId) + "/summaries/daily", query: query)
        return try await client.send(request, as: InsightSummary.self)
    }

    public func weeklySummary(of childId: UUID, weekStart: LocalDate) async throws -> InsightSummary {
        let request = ApiRequest(
            method: .get,
            path: Self.childPath(childId) + "/summaries/weekly",
            query: ["weekStart": weekStart.text]
        )
        return try await client.send(request, as: InsightSummary.self)
    }

    public func dailyUsage(of childId: UUID, from: LocalDate, to: LocalDate) async throws -> [DailyUsage] {
        let request = ApiRequest(
            method: .get,
            path: Self.childPath(childId) + "/usage/daily",
            query: ["from": from.text, "to": to.text]
        )
        return try await client.send(request, as: [DailyUsage].self)
    }

    public func appUsage(of childId: UUID, range: UsageRange) async throws -> AppBreakdown {
        let request = ApiRequest(
            method: .get,
            path: Self.childPath(childId) + "/usage/apps",
            query: ["range": range.rawValue]
        )
        return try await client.send(request, as: AppBreakdown.self)
    }
}
