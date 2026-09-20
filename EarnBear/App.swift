import SwiftUI
import AppKit
import ServiceManagement

@main struct EarnBearApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        MenuBarExtra { Panel(store: store) } label: {
            Image(nsImage: MenuBarReadout.image(for: store.title))
                .accessibilityLabel(store.title)
        }.menuBarExtraStyle(.window)
        Window("EarnBear 設定", id: "settings") {
            SettingsView(store: store).frame(width: 520)
        }.windowResizability(.contentSize)
    }
}
// MenuBarExtra can discard Text font modifiers when bridging to NSStatusItem.
// A template image preserves the actual monospaced digits without reserving unused space.
enum MenuBarReadout {
    static func image(for title: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        let size = NSSize(width: ceil(text.size().width) + 4, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            text.draw(at: NSPoint(x: 2, y: floor((size.height - text.size().height) / 2)))
            return true
        }
        image.isTemplate = true
        return image
    }
}
struct Panel: View {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ink = Color.primary
    private var working: Bool { store.running != nil && !store.stale }
    private var celebrating: Bool {
        guard working, store.amount >= 1000, store.hourlyRate > 0 else { return false }
        // A short celebration at each ¥1,000, without extra API requests.
        return store.amount.truncatingRemainder(dividingBy: 1000) < store.hourlyRate / 3600 * 3
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.configured ? (store.stale ? "≈" : "") + store.money : "HELLO!")
                        .font(.system(size: 36, weight: .semibold, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(store.running != nil ? store.elapsed : "--:--:--")
                        .font(.system(size: 20, design: .monospaced)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundStyle(ink.opacity(0.65))
                }.frame(maxWidth: .infinity, alignment: .leading)
                TimelineView(.animation(minimumInterval: 0.5, paused: reduceMotion)) { context in
                    PixelBear(working: working, celebrating: celebrating && !reduceMotion,
                              frame: reduceMotion ? 0 : Int(context.date.timeIntervalSince1970 * 2) % 64)
                }.frame(width: 72, height: 72).accessibilityLabel(working ? "働くしろくま" : "休憩するしろくま")
            }
            Rectangle().fill(ink.opacity(0.15)).frame(height: 1)
            HStack(spacing: 8) {
                Circle()
                    .fill(!store.configured || store.lastSync == nil ? Color.gray : store.stale ? Color.orange : working ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                    .help(!store.configured ? "未設定" : store.stale ? "同期を確認できません" : store.lastSync == nil ? "同期中" : working ? "稼働中" : "停止中")
                    .accessibilityLabel(!store.configured ? "未設定" : store.stale ? "同期を確認できません" : store.lastSync == nil ? "同期中" : working ? "稼働中" : "停止中")
                Text(store.configured ? (store.running?.description.flatMap { $0.isEmpty ? nil : $0 } ?? (store.running == nil ? "ひとやすみ中" : "作業中")) : "設定からはじめよう")
                    .font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    Task { await store.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(!store.canRefresh)
                .help(store.busy ? "更新中…" : "今すぐClockifyと同期")
                .accessibilityLabel(store.busy ? "更新中" : "今すぐ更新")
                Menu {
                    Button("設定…") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
                    Link("Clockifyを開く", destination: URL(string: "https://app.clockify.me/tracker")!)
                    if store.running != nil {
                        Text("\(store.usesAutomatic ? "Clockify" : "固定時給・概算") · ¥\(store.hourlyRate.formatted()) / 時間")
                        if store.preferences.billableOnly && store.running?.billable != true { Text("非請求時間：0円で計算") }
                    }
                    if let last = store.lastSync { Text("最終同期 \(last.formatted(date: .omitted, time: .standard))") }
                    Divider()
                    Button("終了") { NSApp.terminate(nil) }
                } label: { Image(systemName: "gearshape").font(.system(size: 12)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("設定とアクション")
            }
            if store.stale {
                Text(store.error ?? "同期が遅れています。金額は推定です。")
                    .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
            }
        }
        // Let MenuBarExtra supply the native translucent window appearance.
        .foregroundStyle(ink).padding(16).frame(width: 274)
    }
}

// Integer-aligned cells keep this tiny native sprite crisp on Retina displays.
struct PixelBear: View {
    let working: Bool
    let celebrating: Bool
    let frame: Int
    var body: some View {
        Canvas { context, _ in
            let outline = Color(red: 0.23, green: 0.31, blue: 0.29)
            let white = Color(red: 0.98, green: 0.98, blue: 0.91)
            let shade = Color(red: 0.72, green: 0.79, blue: 0.73)
            func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Color) {
                context.fill(Path(CGRect(x: x * 2, y: y * 2, width: w * 2, height: h * 2)), with: .color(color))
            }
            let bob = working && frame % 2 == 1 ? 1 : 0
            rect(8, 6 + bob, 5, 5, outline); rect(22, 6 + bob, 5, 5, outline)
            rect(9, 7 + bob, 3, 3, white); rect(23, 7 + bob, 3, 3, white)
            rect(9, 9 + bob, 17, 2, outline); rect(6, 11 + bob, 23, 10, outline)
            rect(8, 10 + bob, 19, 12, white); rect(7, 12 + bob, 21, 7, white)
            rect(9, 21, 17, 10, outline); rect(10, 21, 15, 8, white)
            rect(10, 28, 5, 3, shade); rect(21, 28, 4, 3, shade)
            let moneyEyes = working && (celebrating || (frame >= 48 && frame < 52))
            if moneyEyes {
                for x in [10, 21] {
                    for (y, row) in ["#.#", ".#.", "###", ".#.", "###"].enumerated() {
                        for (dx, pixel) in row.enumerated() where pixel == "#" {
                            rect(x + dx, 12 + bob + y, 1, 1, outline)
                        }
                    }
                }
            } else {
                let eyesClosed = !working || frame % 8 == 6
                rect(11, 14 + bob, 2, eyesClosed ? 1 : 2, outline)
                rect(22, 14 + bob, 2, eyesClosed ? 1 : 2, outline)
            }
            rect(16, 17 + bob, 3, 2, outline); rect(17, 19 + bob, 1, 1, outline)
            if celebrating {
                rect(4, 17, 4, 7, outline); rect(5, 17, 2, 5, white)
                rect(27, 14, 4, 9, outline); rect(28, 14, 2, 7, white)
                rect(26, 5, 7, 7, outline); rect(27, 6, 5, 5, Color(red: 0.85, green: 0.66, blue: 0.27))
                rect(29, 7, 1, 3, white)
            } else {
                rect(8, 23, 6, 3, shade); rect(21, 23 + bob, 6, 3, shade)
                rect(9, 22, 5, 3, white); rect(21, 22 + bob, 5, 3, white)
                if working { rect(25, 20 + bob, 1, 6, outline) }
                else if frame % 8 < 4 {
                    rect(29, 3, 4, 1, outline); rect(31, 4, 1, 1, outline)
                    rect(30, 5, 1, 1, outline); rect(29, 6, 4, 1, outline)
                }
            }
            rect(3, 27, 30, 2, outline); rect(5, 29, 2, 6, outline); rect(29, 29, 2, 6, outline)
            rect(16, 25, 10, 2, white); rect(18, 26, 5, 1, shade)
        }.accessibilityHidden(true)
    }
}
@MainActor final class LoginLaunch: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var changing = false
    @Published var message: String?
    var requested: Bool { status == .enabled || status == .requiresApproval }
    func reload() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) async {
        guard !changing else { return }
        changing = true
        message = nil
        defer { reload(); changing = false }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try await SMAppService.mainApp.unregister() }
        } catch { message = "自動起動の設定を変更できませんでした：" + error.localizedDescription }
    }
}
struct LoginLaunchSettings: View {
    @StateObject private var model = LoginLaunch()
    var body: some View {
        GroupBox("起動") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("ログイン時に起動", isOn: Binding(
                    get: { model.requested },
                    set: { value in Task { await model.setEnabled(value) } }
                )).toggleStyle(.switch).disabled(model.changing)
                Text("切り替えはすぐに反映されます。アプリを「アプリケーション」フォルダに置いてからオンにしてください。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.status == .requiresApproval {
                    Text("自動起動は承認待ちです。macOSのログイン項目で許可してください。")
                        .font(.caption).foregroundStyle(.orange)
                    Button("ログイン項目を開く") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let message = model.message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.reload() }
    }
}
@MainActor final class SettingsForm: ObservableObject {
    @Published var key = ""
    @Published var region = Preferences().region
    @Published var settings = Preferences()
    @Published var message = ""
    @Published var connectionMessage = ""
    @Published var loading = false
    @Published var editingAPI = false
    @Published var connected = false
    @Published var workspaces: [Workspace] = []
    @Published var userID = ""
    @Published var workspaceID = ""
    @Published var verifiedKey = ""
    @Published var verifiedRegion = ""
    var verified: Bool { !verifiedKey.isEmpty && key == verifiedKey && region == verifiedRegion }
    func resetDraft() {
        key = ""; verifiedKey = ""; workspaces = []; workspaceID = ""
        connectionMessage = ""
    }
}
struct SettingsView: View {
    @ObservedObject var store: Store
    @StateObject private var form = SettingsForm()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EarnBear").font(.title.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if form.connected {
                        GroupBox("金額の計算") {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Clockifyに設定した時給を優先する", isOn: $form.settings.automaticRate)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 12) {
                                        Text(form.settings.automaticRate ? "取得できないときの時給" : "計算に使う時給")
                                        Spacer(minLength: 0)
                                        TextField("時給", value: $form.settings.fixedRate, format: .number)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 90)
                                            .accessibilityLabel(form.settings.automaticRate ? "取得できないときの時給（円／時間）" : "計算に使う時給（円／時間）")
                                        Text("円／時間").foregroundStyle(.secondary)
                                    }
                                    Text(form.settings.automaticRate
                                         ? "Clockifyの時給を取得できない場合や、円以外の通貨の場合は、この金額で計算します。"
                                         : "Clockifyの時給設定に関係なく、この金額 × 作業時間で計算します。")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Toggle("請求可能（Billable）な時間のみ計算", isOn: $form.settings.billableOnly)
                            }.padding(10)
                        }
                        GroupBox("同期") {
                            VStack(alignment: .leading, spacing: 6) {
                                Picker("Clockifyの確認間隔", selection: $form.settings.interval) {
                                    Text("3分 · 無料プラン向け").tag(180.0)
                                    Text("30秒 · 有料プラン向け").tag(30.0)
                                    Text("15秒 · 有料プラン向け").tag(15.0)
                                }
                                Text("金額は毎秒更新します。開始・停止の反映は確認間隔分遅れます。無料プランはWorkspace全体で毎時30 APIリクエストまでです。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(10)
                        }
                    }
                    LoginLaunchSettings()
                    GroupBox("API接続") {
                        VStack(alignment: .leading, spacing: 12) {
                            if form.connected {
                                HStack {
                                    Label(form.settings.workspaceName, systemImage: "checkmark.circle.fill")
                                    Spacer()
                                    if !form.editingAPI {
                                        Button("変更…") {
                                            form.resetDraft(); form.region = form.settings.region
                                            form.editingAPI = true
                                        }
                                    }
                                }
                            }
                            if !form.connected || form.editingAPI { connectionEditor }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(2)
            }.frame(maxHeight: form.connected ? 480 : 320)
            if !form.message.isEmpty { Text(form.message).font(.callout).textSelection(.enabled) }
            if form.connected {
                HStack {
                    Button("接続情報を削除", role: .destructive) {
                        store.disconnect()
                        if !store.configured {
                            form.connected = false; form.editingAPI = false
                            form.resetDraft(); form.settings = Preferences()
                            form.message = "接続情報を削除しました。"
                        } else { form.message = store.error ?? "削除できませんでした。" }
                    }.disabled(form.loading)
                    Spacer()
                    Button("設定を保存") {
                        do {
                            try store.savePreferences(form.settings)
                            form.message = "設定を保存しました。"
                        } catch { form.message = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                        .disabled(!form.settings.fixedRate.isFinite || form.settings.fixedRate < 0)
                }
            }
            Text("APIキーはこのMacのKeychainに保存します。Clockifyの記録は変更しません。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).onAppear {
            form.settings = store.preferences
            form.connected = store.configured
            form.region = store.preferences.region
        }
    }
    private var connectionEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("データ地域", selection: $form.region) {
                Text("Global（通常）").tag("https://api.clockify.me/api/v1")
                Text("EU").tag("https://euc1.clockify.me/api/v1")
                Text("US").tag("https://use2.clockify.me/api/v1")
                Text("Australia").tag("https://apse2.clockify.me/api/v1")
            }
            SecureField("Clockify APIキー", text: $form.key)
            HStack {
                Link("APIキーの設定ページ", destination: URL(string: "https://app.clockify.me/user/settings")!)
                Spacer()
                Button(form.loading ? "接続中…" : "接続を確認") { Task { await connect() } }
                    .disabled(form.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if form.verified {
                Picker("Workspace", selection: $form.workspaceID) {
                    Text("選択してください").tag("")
                    ForEach(form.workspaces) { Text($0.name).tag($0.id) }
                }
                Button(form.connected ? "接続先を変更" : "このWorkspaceで開始") { applyConnection() }
                    .buttonStyle(.borderedProminent).disabled(form.workspaceID.isEmpty)
            }
            if !form.connectionMessage.isEmpty { Text(form.connectionMessage).font(.caption) }
            if form.connected {
                Button("キャンセル") { form.editingAPI = false; form.resetDraft() }
            }
        }.disabled(form.loading)
    }
    private func connect() async {
        form.loading = true; form.verifiedKey = ""; form.connectionMessage = ""
        defer { form.loading = false }
        let key = form.key.trimmingCharacters(in: .whitespacesAndNewlines)
        let api = API(key: key, base: form.region)
        do {
            let user: User = try await api.get("/user")
            let list: [Workspace] = try await api.get("/workspaces")
            form.userID = user.id; form.workspaces = list
            form.workspaceID = list.first?.id ?? ""
            form.key = key; form.verifiedKey = key; form.verifiedRegion = form.region
            form.connectionMessage = list.isEmpty ? "Workspaceがありません。" : "接続できました。Workspaceを選んでください。"
        } catch { form.connectionMessage = error.localizedDescription }
    }
    private func applyConnection() {
        guard form.verified, let workspace = form.workspaces.first(where: { $0.id == form.workspaceID }) else { return }
        var settings = form.settings
        settings.workspaceID = workspace.id; settings.workspaceName = workspace.name
        settings.userID = form.userID; settings.region = form.region
        guard settings.fixedRate.isFinite, settings.fixedRate >= 0 else {
            form.connectionMessage = "固定時給には0以上の数値を入力してください。"; return
        }
        do {
            try store.save(settings, key: form.key)
            form.settings = settings; form.connected = true; form.editingAPI = false
            form.resetDraft(); form.message = "接続設定を保存しました。"
        } catch { form.connectionMessage = error.localizedDescription }
    }
}
