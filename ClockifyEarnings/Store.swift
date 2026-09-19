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
        generation += 1
        preferences = settings
        UserDefaults.standard.set(try JSONEncoder().encode(settings), forKey: "preferences")
        running = nil; lastSync = nil; error = nil; nextPoll = .distantPast
        Task { await refresh() }
    }
    func disconnect() {
        do {
            try Keychain.delete()
            generation += 1
            preferences = Preferences()
            UserDefaults.standard.removeObject(forKey: "preferences")
            running = nil; lastSync = nil; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard configured, !busy, Date() >= nextPoll else { return }
        busy = true
        let revision = generation
        let settings = preferences
        defer { busy = false }
        nextPoll = Date().addingTimeInterval(settings.interval)
        do {
            guard let key = try Keychain.read(), !key.isEmpty else { throw Keychain.failure(errSecItemNotFound) }
            let entries: [Entry] = try await API(key: key, base: settings.region).get(
                "/workspaces/\(settings.workspaceID)/user/\(settings.userID)/time-entries",
                query: [.init(name: "in-progress", value: "true"), .init(name: "hydrated", value: "true"), .init(name: "page-size", value: "50")])
            guard revision == generation else { return }
            running = entries.filter { $0.timeInterval.end == nil && $0.type != "BREAK" }.sorted { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }.first
            lastSync = Date(); error = nil
        } catch {
            guard revision == generation else { return }
            self.error = error.localizedDescription
            let delay = (error as? APIError)?.status == 429 ? 3600 : max(settings.interval, 60)
            nextPoll = Date().addingTimeInterval(delay)
        }
    }
}
