import SwiftUI
import AppKit

@main struct ClockifyEarningsApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        MenuBarExtra { Panel(store: store) } label: {
            Text(store.title).monospacedDigit()
        }.menuBarExtraStyle(.window)
        Window("Clockify Earnings 設定", id: "settings") {
            SettingsView(store: store).frame(width: 520)
        }.windowResizability(.contentSize)
    }
}
struct Panel: View {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Clockify Earnings", systemImage: "yensign.circle.fill").font(.headline)
                Spacer()
                Circle().fill(store.stale ? .orange : store.running == nil ? .gray : .green).frame(width: 8, height: 8)
            }
            Text(store.configured ? store.money : "設定してください").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
            if let entry = store.running {
                Text(store.elapsed).font(.title3.monospacedDigit())
                Text(entry.description?.isEmpty == false ? entry.description! : "作業中").lineLimit(2)
                Text(store.usesAutomatic ? "Clockifyの時給 · ¥\(store.hourlyRate.formatted()) / 時間" : "固定時給（概算）· ¥\(store.hourlyRate.formatted()) / 時間").font(.caption).foregroundStyle(.secondary)
                if store.preferences.billableOnly && entry.billable != true { Text("非請求時間のため金額は0円です").font(.caption) }
            } else { Text(store.configured ? "Clockifyでタイマーを開始すると表示します" : "APIキーとWorkspaceを設定してください").foregroundStyle(.secondary) }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if store.stale && store.running != nil { Text("未同期 · 最後に取得した開始時刻からの推定値です").font(.caption).foregroundStyle(.orange) }
            if let last = store.lastSync { Text("最終同期 \(last.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
            Divider()
            HStack {
                Button("設定…") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
                Link("Clockifyを開く", destination: URL(string: "https://app.clockify.me/tracker")!)
                Spacer()
                Button("終了") { NSApp.terminate(nil) }
            }
        }.padding(20).frame(width: 370)
    }
}
@MainActor final class SettingsForm: ObservableObject {
    @Published var key = ""
    @Published var settings = Preferences()
    @Published var workspaces: [Workspace] = []
    @Published var message = ""
    @Published var loading = false
    @Published var validated = false
}
struct SettingsView: View {
    @ObservedObject var store: Store
    @StateObject private var form = SettingsForm()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clockify Earnings").font(.title.bold())
            Text("いつものClockifyに、いまの稼ぎを。").foregroundStyle(.secondary)
            Form {
                Picker("データ地域", selection: $form.settings.region) {
                    Text("Global（通常）").tag("https://api.clockify.me/api/v1")
                    Text("EU").tag("https://euc1.clockify.me/api/v1")
                    Text("US").tag("https://use2.clockify.me/api/v1")
                    Text("Australia").tag("https://apse2.clockify.me/api/v1")
                }.onChange(of: form.settings.region) { _ in form.validated = false; form.workspaces = [] }
                SecureField("Clockify APIキー", text: $form.key).onChange(of: form.key) { _ in form.validated = false }
                HStack {
                    Link("APIキーの設定ページ", destination: URL(string: "https://app.clockify.me/user/settings")!)
                    Spacer()
                    Button(form.loading ? "取得中…" : "接続してWorkspaceを取得") { Task { await connect() } }.disabled(form.loading || form.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Picker("Workspace", selection: $form.settings.workspaceID) {
                    Text("選択してください").tag("")
                    ForEach(form.workspaces) { Text($0.name).tag($0.id) }
                }
                Toggle("取得できたClockifyの円建て時給を使う", isOn: $form.settings.automaticRate)
                TextField("固定時給（円 / 時間）", value: $form.settings.fixedRate, format: .number)
                Text("時給の取得権限がない場合や円以外の場合は固定時給を使用します。通貨換算は行いません。").font(.caption).foregroundStyle(.secondary)
                Toggle("請求可能（Billable）な時間のみ金額を計算", isOn: $form.settings.billableOnly)
                Picker("Clockifyの確認間隔", selection: $form.settings.interval) {
                    Text("3分 · 無料プラン向け").tag(180.0)
                    Text("30秒 · 有料プラン向け").tag(30.0)
                    Text("15秒 · 有料プラン向け").tag(15.0)
                }
                Text("金額は毎秒更新します。開始・停止の反映は確認間隔分遅れます。無料プランはWorkspace全体で毎時30 APIリクエストまで。接続確認や他の連携も枠を使用します。").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).disabled(form.loading).frame(height: 390)
            if !form.message.isEmpty { Text(form.message).font(.callout).textSelection(.enabled) }
            HStack {
                Button("接続情報を削除", role: .destructive) { store.disconnect(); form.key = ""; form.workspaces = []; form.settings = Preferences(); form.validated = false; form.message = store.error ?? "接続情報を削除しました。" }
                Spacer()
                Button("保存して開始") {
                    do {
                        form.settings.workspaceName = form.workspaces.first { $0.id == form.settings.workspaceID }?.name ?? ""
                        try store.save(form.settings, key: form.key.trimmingCharacters(in: .whitespacesAndNewlines))
                        form.key = ""; form.validated = false
                        form.message = "保存しました。メニューバーで確認できます。"
                    } catch { form.message = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(!form.validated || form.settings.workspaceID.isEmpty || !form.settings.fixedRate.isFinite || form.settings.fixedRate < 0)
            }
            Text("APIキーはこのMacのKeychainに保存します。Clockifyの記録は変更しません。").font(.caption).foregroundStyle(.secondary)
        }.padding(24).onAppear {
            form.settings = store.preferences
            if !form.settings.workspaceID.isEmpty { form.workspaces = [Workspace(id: form.settings.workspaceID, name: form.settings.workspaceName)] }
            do { form.key = try Keychain.read() ?? "" } catch { form.message = error.localizedDescription }
        }
    }
    private func connect() async {
        form.loading = true; form.validated = false; form.message = ""
        defer { form.loading = false }
        let api = API(key: form.key.trimmingCharacters(in: .whitespacesAndNewlines), base: form.settings.region)
        do {
            let user: User = try await api.get("/user")
            let list: [Workspace] = try await api.get("/workspaces")
            form.settings.userID = user.id; form.workspaces = list
            if !list.contains(where: { $0.id == form.settings.workspaceID }) { form.settings.workspaceID = list.first?.id ?? "" }
            form.validated = true
            form.message = list.isEmpty ? "Workspaceがありません。" : "接続できました。Workspaceと時給を確認して保存してください。"
        } catch { form.message = error.localizedDescription }
    }
}
