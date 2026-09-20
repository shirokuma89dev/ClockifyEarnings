import Foundation

@main struct CoreChecks {
    @MainActor static func main() throws {
        let credential = SessionCredential()
        var reads = 0
        let loader: () throws -> String? = { reads += 1; return "test-only-key" }
        _ = try credential.read(using: loader)
        _ = try credential.read(using: loader)
        precondition(reads == 1)
        credential.replace(with: "replacement")
        let replacement = try credential.read(using: loader)
        precondition(replacement == "replacement" && reads == 1)
        credential.clear()
        _ = try credential.read(using: loader)
        precondition(reads == 2)
        print("PASS: credentials are read once, replaced after save, cleared on disconnect")
        let data = Data("""
        {"id":"sample","description":"Test","billable":true,"type":"REGULAR",
         "timeInterval":{"start":"2026-09-19T00:00:00Z","end":null},
         "hourlyRate":{"amount":150000,"currency":"JPY"}}
        """.utf8)
        let entry = try JSONDecoder().decode(Entry.self, from: data)
        let now = Dates.parse("2026-09-19T01:00:00.000Z")!
        precondition(entry.seconds(at: now) == 3600)
        precondition(entry.seconds(at: Dates.parse("2026-09-18T23:00:00Z")!) == 0)
        let store = Store()
        store.preferences = Preferences()
        store.running = entry
        store.now = now
        precondition(store.usesAutomatic && store.hourlyRate == 1500 && store.amount == 1500)
        precondition(store.elapsed == "01:00:00")
        store.preferences.automaticRate = false
        store.preferences.fixedRate = 2400
        precondition(store.amount == 2400)
        let stopped = Entry(id: "end", description: nil, billable: false, type: nil,
            timeInterval: Interval(start: "2026-09-19T00:00:00Z", end: "2026-09-19T00:30:00Z"), hourlyRate: nil)
        precondition(stopped.seconds(at: now) == 1800)
        store.running = stopped
        store.preferences.billableOnly = true
        precondition(store.amount == 0)
        store.preferences.billableOnly = false
        precondition(store.amount == 1200)
        store.running = Entry(id: "usd", description: nil, billable: true, type: nil,
            timeInterval: entry.timeInterval, hourlyRate: Rate(amount: 10000, currency: "USD"))
        store.preferences.automaticRate = true
        precondition(!store.usesAutomatic && store.hourlyRate == 2400)
        store.error = "offline"
        precondition(store.stale)
        store.running = nil
        precondition(store.seconds == 0 && store.amount == 0)
        print("PASS: API decode, ISO dates, elapsed time, stop/future times, JPY rate conversion, fixed fallback, non-JPY fallback, billable filter, stale state, idle state")
    }
}
