import SwiftUI
import Security

import Combine

@MainActor final class Store: ObservableObject {
    @Published var preferences: Preferences
    @Published var running: Entry?
    @Published var now = Date()
    @Published var lastSync: Date?
    @Published var error: String?
    @Published var busy = false
    private var timer: AnyCancellable?
    private var nextPoll = Date.distantPast
    private var generation = 0
    private let credential = SessionCredential()
    private var rateLimitedUntil = Date.distantPast
    var canRefresh: Bool { configured && !busy && now >= rateLimitedUntil }
    init() {
        preferences = UserDefaults.standard.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in
            guard let self else { return }
            self.now = date
            if date >= self.nextPoll { Task { await self.refresh() } }
        }
    }
    var configured: Bool { !preferences.workspaceID.isEmpty }
    var stale: Bool { error != nil || lastSync.map { now.timeIntervalSince($0) > preferences.interval + 30 } == true }
    var seconds: Double { running?.seconds(at: now) ?? 0 }
    var elapsed: String {
        let s = Int(seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
    var usesAutomatic: Bool {
        preferences.automaticRate && running?.hourlyRate?.currency == "JPY" && (running?.hourlyRate?.amount ?? -1) >= 0
    }
    var hourlyRate: Double { usesAutomatic ? running!.hourlyRate!.amount / 100 : preferences.fixedRate }
    var amount: Double { preferences.billableOnly && running?.billable != true ? 0 : seconds * hourlyRate / 3600 }
    var money: String { amount.formatted(.currency(code: "JPY").precision(.fractionLength(0))) }
    var title: String {
        if !configured { return "¥ — 設定" }
        if running != nil { return "\(stale ? "≈" : "")\(money)  \(elapsed)" }
        return stale ? "Clockify ⚠︎" : "¥0  停止中"
    }
    func save(_ settings: Preferences, key: String) throws {
        try Keychain.save(key)
        credential.replace(with: key)
        generation += 1
        preferences = settings
        UserDefaults.standard.set(try JSONEncoder().encode(settings), forKey: "preferences")
        running = nil; lastSync = nil; error = nil; nextPoll = .distantPast
        Task { await refresh() }
    }
    func savePreferences(_ settings: Preferences) throws {
        // Display preferences do not change credentials or trigger another API call.
        var updated = preferences
        updated.fixedRate = settings.fixedRate
        updated.automaticRate = settings.automaticRate
        updated.billableOnly = settings.billableOnly
        updated.interval = settings.interval
        let data = try JSONEncoder().encode(updated)
        preferences = updated
        UserDefaults.standard.set(data, forKey: "preferences")
    }
    func disconnect() {
        do {
            try Keychain.delete()
            credential.clear()
            generation += 1
            preferences = Preferences()
            UserDefaults.standard.removeObject(forKey: "preferences")
            running = nil; lastSync = nil; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func refresh(force: Bool = false) async {
        guard configured, !busy, Date() >= rateLimitedUntil, force || Date() >= nextPoll else { return }
        busy = true
        let revision = generation
        let settings = preferences
        defer { busy = false }
        nextPoll = Date().addingTimeInterval(settings.interval)
        do {
            let key = try credential.read(using: Keychain.read)
            let entries: [Entry] = try await API(key: key, base: settings.region).get(
                "/workspaces/\(settings.workspaceID)/user/\(settings.userID)/time-entries",
                query: [.init(name: "in-progress", value: "true"), .init(name: "hydrated", value: "true"), .init(name: "page-size", value: "50")])
            guard revision == generation else { return }
            running = entries.filter { $0.timeInterval.end == nil && $0.type != "BREAK" }.sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }.first
            lastSync = Date(); error = nil
        } catch {
            guard revision == generation else { return }
            self.error = error.localizedDescription
            if (error as NSError).domain == "Keychain" {
                // Retry only after the user presses refresh or updates credentials.
                self.error = error.localizedDescription + " 再試行するには更新ボタンを押してください。"
                nextPoll = .distantFuture
                return
            }
            let delay = (error as? APIError)?.status == 429 ? 3600 : max(settings.interval, 60)
            nextPoll = Date().addingTimeInterval(delay)
            if (error as? APIError)?.status == 429 { rateLimitedUntil = nextPoll }
        }
    }
}
