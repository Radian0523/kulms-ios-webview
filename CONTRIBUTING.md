# Contributing

KULMS+ iOS WebView への貢献を歓迎します。

## 開発環境のセットアップ

1. リポジトリをフォーク & クローン
   ```bash
   git clone https://github.com/<your-username>/kulms-ios-webview.git
   ```
2. 拡張機能リポジトリもクローン（同じ親ディレクトリに配置）
   ```bash
   git clone https://github.com/Radian0523/kulms-extension.git
   ```
3. XcodeGen でプロジェクトを生成
   ```bash
   xcodegen generate
   ```
4. Xcode でプロジェクトを開く
5. 実機またはシミュレータでビルド・実行（iOS 17.0+）
6. 初回起動時に SSO でログインして動作確認

## プロジェクト構成

```
Services/
  WebViewManager.swift         # WKWebView 管理 + ログイン処理
  KulmsStorageHandler.swift    # chrome.storage ↔ UserDefaults ブリッジ
  ContentScriptInjector.swift  # 拡張機能スクリプト注入
  CredentialStore.swift        # iOS Keychain パスワード保存
  NotificationService.swift    # 通知スケジュール管理
Views/
  LoginView.swift              # ログイン画面
  CredentialLoginView.swift    # ID/パスワード入力
  LMSWebView.swift             # LMS表示画面
demo/
  demo.html                    # デモモード用静的HTML
  DemoWebView.swift            # デモ専用WebView画面
```

### アーキテクチャのポイント

- WKWebView で LMS を表示し、`kulms-shim.js` で `chrome.storage` API をエミュレート
- 拡張機能のスクリプト（assignments.js 等）を Bundle からページ完了時に注入
- `KulmsStorageHandler` が UserDefaults に永続化し、JS にコールバック返却
- 課題データ更新時に `NotificationService` が UNUserNotificationCenter で通知をスケジュール

## コーディング規約

- 外部依存は不使用（純正フレームワークのみ）
- Swift + SwiftUI を使用
- async/await で非同期処理

## Pull Request の流れ

1. `main` から作業ブランチを作成
2. 変更を実装し、Xcode でビルドが通ることを確認
3. コミットメッセージは変更内容を日本語で簡潔に記述
4. Pull Request を作成し、変更内容を説明

## Issue

- バグ報告・機能リクエストは [Issue テンプレート](https://github.com/Radian0523/kulms-ios-webview/issues/new/choose) を使用してください
- フィードバックフォーム: [Google Forms](https://docs.google.com/forms/d/e/1FAIpQLScLn4G2IF1w0-QOWPKZ7R1LXjOq7OocYUmGJLoNA6JBuA20EA/viewform)
