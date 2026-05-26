# KULMS+ for iOS (WebView)

京都大学の学習支援システム (KULMS) を拡張する iOS アプリ。
WKWebView ベースで [kulms-extension](https://github.com/Radian0523/kulms-extension) の機能をネイティブアプリとして提供します。

## 機能

- LMS の WKWebView 表示 + 拡張機能スクリプト注入
- ECS-ID / SPS-ID によるログイン（パスキー / 多要素認証対応）
- TOTP 自動入力（シークレットキーを登録すると OTP を自動入力、QR スキャン対応）
- TOTP コード確認（現在の 6 桁コードとシークレットキーを表示）
- 課題の締切通知（タイミングカスタマイズ対応）
- 新着課題の即時通知
- ホーム画面クイックアクション（アイコン長押しで課題表示）
- 設定画面（通知カスタマイズ、セキュリティ説明、アプリ情報）
- TA 採点支援（採点画面での提出一覧取得・ナビゲーション効率化）
- ファイル表示・ダウンロード・共有（PDF インライン表示対応）
- パスワードの暗号化保存（iOS Keychain）
- App Store 審査用デモモード（静的 HTML、本番環境への影響なし）

## 構成

- **Swift** + SwiftUI
- WKWebView + `kulms-shim.js` で chrome.storage API をエミュレート
- 拡張機能のスクリプトを Bundle から注入

## ビルド

```bash
xcodegen generate
open KULMS.xcodeproj
```

## ライセンス

MIT
