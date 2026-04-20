# KULMS+ for iOS (WebView)

京都大学の学習支援システム (KULMS) を拡張する iOS アプリ。
WKWebView ベースで [kulms-extension](https://github.com/Radian0523/kulms-extension) の機能をネイティブアプリとして提供します。

## 機能

- LMS の WKWebView 表示 + 拡張機能スクリプト注入
- ECS-ID / SPS-ID によるログイン（パスキー / 多要素認証対応）
- 課題の締切通知
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
