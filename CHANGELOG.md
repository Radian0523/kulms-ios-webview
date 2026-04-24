# Changelog

## 2.1.1 (2026-04-24)

- 非JSONレスポンスで誤ってログアウト扱いされるバグを修正
- ページ読み込み時にキャッシュ期限切れでもタブ色分け・通知バッジを即座に適用するよう修正

## 2.1.0 (2026-04-24)

- モーダル WKWebView でファイル表示機能を実装
  - `decidePolicyForNavigationAction` で `target="_blank"` および `/access/` URL を検知
  - `presentModalWebView(url:)` で同一 WKWebsiteDataStore（Cookie共有）の新 WKWebView をモーダル表示
  - UINavigationController で閉じるボタン（×）とダウンロードボタン（arrow.down.circle）付き
  - WKWebView は PDF をネイティブにインライン表示可能
- `downloadAndShare(url:from:)` でファイルダウンロード → UIActivityViewController で外部アプリに共有
- ファイル名から UUID プレフィックスを除去（WKDownload パスと downloadAndShare の両方）
- `hasInitiallyLoaded` フラグ追加: モーダルを閉じた後に LMS トップページに戻るバグを修正（`LMSWebView.onAppear` の `loadPortal()` 二重呼び出し防止）

## 2.0.4 (2026-04-20)

- Android版テスター募集バナーを追加（拡張機能スクリプト同期）

## 2.0.3 (2026-04-20)

- App Store 審査用デモモードを追加
  - ログイン画面下部の「Demo Mode」ボタンからアクセス
  - 静的 HTML による LMS 風 UI + KULMS+ パネルのデモ表示
  - 課題・教科書・設定タブの操作、メモ機能、セクション折りたたみ等が体験可能
  - 本番環境への影響なし（独立した WKWebView で動作）

## 2.0.2 (2026-04-20)

- 外部リンク（target="_blank"）が開けない問題を修正
  - バージョンリンク、ホームページリンク等をタップすると Safari で開くよう修正

## 2.0.1 (2026-04-20)

- 拡張機能の画面幅制限を撤廃し、モバイルでも全機能を表示
- 教科書タブの科目順を曜日・時限順にソート
- NOW/NEXT バッジのテキストが科目名に混入するバグを修正

## 2.0.0 (2026-04-19)

- WebView版として再構築
- 拡張機能スクリプト全機能対応

## 1.0.0 (2026-04-19)

- 初回リリース
- WKWebView ベースの LMS 表示
- 拡張機能スクリプト注入 (kulms-shim)
- ECS-ID / SPS-ID ログイン（2FA 対応）
- パスワード暗号化保存
- 課題の締切通知
