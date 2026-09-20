import Foundation

struct Workspace: Codable, Identifiable, Hashable { let id: String; let name: String }
struct User: Decodable { let id: String }
struct Rate: Codable { let amount: Double; let currency: String? }
struct Interval: Codable { let start: String; let end: String? }
struct Entry: Codable, Identifiable {
    let id: String
    let description: String?
    let billable: Bool?
    let type: String?
    let timeInterval: Interval
    let hourlyRate: Rate?
    var start: Date? { Dates.parse(timeInterval.start) }
    var end: Date? { timeInterval.end.flatMap(Dates.parse) }
    func seconds(at now: Date, since floor: Date? = nil) -> Double {
        guard let start else { return 0 }
        return max(0, min(end ?? now, now).timeIntervalSince(max(start, floor ?? start)))
    }
}
enum Dates {
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
struct Preferences: Codable {
    var workspaceID = ""
    var userID = ""
    var workspaceName = ""
    var fixedRate = 1500.0
    var automaticRate = true
    var billableOnly = false
    var interval = 180.0
    var region = "https://api.clockify.me/api/v1"
}
struct APIError: LocalizedError {
    let status: Int
    var errorDescription: String? {
        switch status {
        case 401: return "APIキーが無効です。設定で確認してください。"
        case 403: return "アクセス権がありません。Workspaceとキーの権限を確認してください。"
        case 429: return "API上限に達しました。1時間後に自動再試行します。"
        default: return "Clockifyへの接続に失敗しました（HTTP \(status)）。"
        }
    }
}
struct API {
    let key: String
    let base: String
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(string: base + path)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 25
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError(status: status) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
