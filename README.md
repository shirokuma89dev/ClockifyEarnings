# Clockify Earnings

macOS 13以降 / Apple Silicon。SwiftUI MenuBarExtraで、Clockifyの実行中の作業の金額と経過時間を毎秒表示します。

## 起動・設定

1. Xcodeで`ClockifyEarnings.xcodeproj`を開き、ClockifyEarningsスキーム / My MacでRunします。
2. メニューバーの「¥ — 設定」を押し「設定…」を開きます。
3. Clockifyのユーザー設定で取得したAPIキーを入力します。「接続を確認」を押し、対象Workspaceを選んで「このWorkspaceで開始」を押します。
4. 固定時給を確認し「設定を保存」を押します。APIキーをチャットに送る必要はありません。
5. Clockifyで普段どおりタイマーを開始・停止します。

APIキーはこのMacのKeychainに保存します。設定ファイルやログには書きません。アプリはClockifyにGETリクエストのみ送信します。Keychainの許可ダイアログが出た場合は、このアプリのアクセスを許可してください。

## 表示

- 現在の作業の金額・経過時間、説明、適用時給、最終同期時刻。
- 時給はhydrated Time EntryのhourlyRateが取得でき、通貨がJPYの場合に利用。Clockifyの整数金額を100で割って円/時間に変換します。取得不可・JPY以外の場合は固定時給で概算します。
- 「請求可能な時間のみ」がオフの場合、非Billableの作業も金額計算します。請求書・給与額を保証する表示ではありません。
- 通信障害中は最後に取得した開始時刻から推定を続け、≈と警告を表示します。
- BREAKは金額計算の対象外です。今日の累計は未実装です。ログイン時自動起動は設定の「起動」から切り替えられます。

## API確認間隔

初期値3分（通常の定期取得で毎時20リクエスト）。無料プランの上限はWorkspace全体で毎時30回で、初期設定や他アプリの利用も共有します。有料プランでは15秒・30秒を選べます。表示自体は常に毎秒更新しますが、開始・停止の検出には確認間隔分の遅れが発生します。HTTP 429時は1時間待って再試行します。

## ビルド

XcodeでClockifyEarnings.xcodeprojを開き、ClockifyEarningsスキーム / My Macを選んでRunしてください。外部パッケージ不要です。ローカル実行用のアドホック署名を使用し、公証や配布用署名は行っていません。

再現用:

```sh
xcodebuild -project ClockifyEarnings.xcodeproj -scheme ClockifyEarnings -configuration Release -derivedDataPath /private/tmp/ClockifyEarningsBuild build
```

Documentsフォルダの同期機能がビルド成果物にFinder情報を付けると署名エラーになる場合があるため、上記コマンドは一時フォルダでビルドします。

## 検証結果

- Xcode 27.0 (27A266a)、macOS SDK 27.0、arm64でRelease BUILD SUCCEEDED。
- CoreChecks.swift: JSON解析、日付形式、経過時間、停止時刻、未来時刻、時給の単位変換、固定時給、JPY以外のフォールバック、Billableフィルタ、通信障害と停止状態の計算を確認。
- 実アカウントでの通信・Keychain保存/読み出しは未検証（APIキー未入力）。画面操作の確認ツールがタイムアウトしたため、画面表示は未確認。

テスト再実行:

```sh
swiftc ClockifyEarnings/Models.swift ClockifyEarnings/Keychain.swift ClockifyEarnings/Store.swift Tests/CoreChecks.swift -o /private/tmp/clockify-checks
/private/tmp/clockify-checks
```

## 参照

- https://docs.clockify.me/
- https://clockify.me/help/getting-started/webhook-and-api-limitations
- https://forum.clockify.me/t/monetary-amounts/1873

## 開発の継続

ソースは `ClockifyEarnings/`、計算テストは `Tests/` にあります。ビルド成果物・Xcode個人設定・APIキーはGitに含めません。変更時は上記のビルドと計算テストを実行してください。

今後の候補: 実アカウントでの同期とKeychainの検証、今日の累計金額。

設定済みの場合は、APIの再接続なしで時給・Billable・同期間隔を保存できます。API接続欄の「変更…」から接続先を変更でき、確定するまでは現在の接続を維持します。

自動起動はmacOS標準のSMAppServiceで登録します。アプリをアプリケーションフォルダに配置してから有効にしてください。切り替えは即時反映され、「設定を保存」は不要です。承認待ちの場合は「ログイン項目を開く」から許可できます。実際のログアウト・再ログインによる起動確認は未実施です。
