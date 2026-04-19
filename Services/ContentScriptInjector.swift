import Foundation
import WebKit

/// 拡張機能の CSS / JS を WKWebViewConfiguration に WKUserScript として登録する。
/// 注入順序: CSS → シム → ロケールデータ → 拡張スクリプト（manifest.json順）
enum ContentScriptInjector {

    /// LMS ホストの判定ガード JS。非 LMS ページ（SSO 認証画面等）では実行をスキップする。
    private static let hostGuardOpen =
        "if (window.location.hostname === 'lms.gakusei.kyoto-u.ac.jp') {\n"
    private static let hostGuardClose = "\n}"

    /// WebView 設定にすべてのユーザースクリプトを登録する。
    static func configure(_ configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController

        // 1. CSS を <style> として注入（LMS のみ）
        if let css = loadBundleResource(name: "styles", ext: "css") {
            let escapedCSS = css
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "${", with: "\\${")
            let cssJS = """
                \(hostGuardOpen)
                (function() {
                    var s = document.createElement('style');
                    s.textContent = `\(escapedCSS)`;
                    (document.head || document.documentElement).appendChild(s);
                })();
                \(hostGuardClose)
                """
            addScript(controller, source: cssJS, mainFrameOnly: false)
        }

        // 2. chrome.* シム（全ページで安全に動作するため、ガード不要）
        if let shimJS = loadBundleResource(name: "kulms-shim", ext: "js") {
            addScript(controller, source: shimJS, mainFrameOnly: false)
        }

        // 3. アプリバージョンを埋め込み
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        addScript(controller, source: "window.__kulmsAppVersion = '\(version)';", mainFrameOnly: false)

        // 4. ロケールデータ埋め込み（LMS のみ）
        let localeJS = hostGuardOpen + buildLocaleDataScript() + hostGuardClose
        addScript(controller, source: localeJS, mainFrameOnly: false)

        // 5. 拡張スクリプト（manifest.json の content_scripts 順、LMS のみ）
        let scriptNames = [
            "settings", "assignments", "submit-detect", "tree-view",
            "course-name", "course-click", "tool-visibility", "textbooks",
            "sidebar-resize", "top-favbar"
        ]
        for name in scriptNames {
            if let js = loadBundleResource(name: name, ext: "js") {
                let guarded = hostGuardOpen + js + hostGuardClose
                addScript(controller, source: guarded, mainFrameOnly: false)
            }
        }
    }

    // MARK: - Private

    private static func addScript(
        _ controller: WKUserContentController,
        source: String,
        mainFrameOnly: Bool
    ) {
        let script = WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: mainFrameOnly
        )
        controller.addUserScript(script)
    }

    /// バンドルリソースを文字列として読み込む。
    private static func loadBundleResource(name: String, ext: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("[KULMS] ContentScriptInjector: resource not found: \(name).\(ext)")
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// _locales/ja/messages.json と _locales/en/messages.json を
    /// window.__kulmsResourceData に埋め込む JS を生成する。
    private static func buildLocaleDataScript() -> String {
        var resources: [String: String] = [:]

        if let jaURL = Bundle.main.url(forResource: "messages", withExtension: "json", subdirectory: "_locales/ja"),
           let jaData = try? String(contentsOf: jaURL, encoding: .utf8) {
            resources["_locales/ja/messages.json"] = jaData
        }

        if let enURL = Bundle.main.url(forResource: "messages", withExtension: "json", subdirectory: "_locales/en"),
           let enData = try? String(contentsOf: enURL, encoding: .utf8) {
            resources["_locales/en/messages.json"] = enData
        }

        // JS として埋め込み
        var js = "window.__kulmsResourceData = {};\n"
        for (path, content) in resources {
            let escaped = content
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
            js += "window.__kulmsResourceData['\(path)'] = '\(escaped)';\n"
        }
        return js
    }
}
