import Foundation
import UIKit
import WebKit

/// ログイン結果。
enum LoginResult {
    case success
    case otpRequired
    case failed(String)
}

/// WKWebView のシングルトン管理。
/// ログイン処理とナビゲーション監視を担当。
@MainActor
class WebViewManager: NSObject {
    static let shared = WebViewManager()

    let webView: WKWebView
    let baseURL = "https://lms.gakusei.kyoto-u.ac.jp"
    let loginPortalURL = "https://lms.gakusei.kyoto-u.ac.jp/portal/login"
    let iimcHost = "auth.iimc.kyoto-u.ac.jp"
    let lmsHost = "lms.gakusei.kyoto-u.ac.jp"

    private var navigationListeners: [(URL) -> Void] = []
    private var storageHandler: KulmsStorageHandler?
    private var pendingDownloadURL: URL?
    private var documentInteractionController: UIDocumentInteractionController?

    /// セッション切れ検知コールバック。
    var onSessionExpired: (() -> Void)?

    /// ポータル到達コールバック（WebView ログイン用自動遷移）。
    var onPortalReached: (() -> Void)?

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        // 拡張スクリプトを登録
        ContentScriptInjector.configure(config)

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        // ストレージブリッジを登録
        storageHandler = KulmsStorageHandler(webView: webView)
        config.userContentController.add(storageHandler!, name: KulmsStorageHandler.messageName)

        webView.navigationDelegate = self

        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
    }

    /// LMS ポータルへナビゲート。
    func loadPortal() {
        if let url = URL(string: baseURL + "/portal") {
            webView.load(URLRequest(url: url))
        }
    }

    /// 指定URLへナビゲート（通知タップ等から使用）。
    func navigate(to urlString: String) {
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - Credential login

    /// ECS-ID/パスワードを使って KULMS にログインする。
    func loginWithCredentials(username: String, password: String) async -> LoginResult {
        await withCheckedContinuation { continuation in
            var credentialsInjected = false
            var hasResumed = false

            let resume: (LoginResult) -> Void = { [weak self] result in
                guard !hasResumed else { return }
                hasResumed = true
                self?.navigationListeners.removeAll()
                continuation.resume(returning: result)
            }

            let listener: (URL) -> Void = { [weak self] url in
                guard let self = self, !hasResumed else { return }
                let urlString = url.absoluteString

                // 成功判定: lms.gakusei の portal 系ページに到達
                let isPortalPage = urlString.hasPrefix(self.baseURL + "/portal")
                    && !urlString.contains("/login")
                    && !urlString.contains("/relogin")
                    && !urlString.contains("/logout")
                if isPortalPage {
                    Task { @MainActor in
                        await self.waitForStableNavigation()
                        guard !hasResumed else { return }
                        resume(.success)
                    }
                    return
                }

                // 2段階認証
                let twoFactorPaths = ["/authselect.php", "/u2flogin.cgi",
                                       "/otplogin.cgi", "/motplogin.cgi"]
                if urlString.contains(self.iimcHost)
                    && twoFactorPaths.contains(where: { urlString.contains($0) }) {
                    resume(.otpRequired)
                    return
                }

                // login.cgi (ID/パスワード入力画面)
                if urlString.contains(self.iimcHost) && urlString.contains("/login.cgi") {
                    if !credentialsInjected {
                        credentialsInjected = true
                        Task { @MainActor in
                            self.injectCredentials(username: username, password: password)
                        }
                    } else {
                        Task { @MainActor in
                            guard !hasResumed else { return }
                            let state = await self.checkLoginCgiState()
                            guard !hasResumed else { return }
                            switch state {
                            case .otp:
                                resume(.otpRequired)
                            case .error(let msg):
                                resume(.failed(msg))
                            case .unknown:
                                break // 次の navigation を待つ
                            }
                        }
                    }
                }
            }

            navigationListeners.append(listener)

            // 全体タイムアウト 30 秒
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                resume(.failed(String(localized: "loginTimeout")))
            }

            if let url = URL(string: loginPortalURL) {
                webView.load(URLRequest(url: url))
            }
        }
    }

    /// IIMC ログイン画面を表示する（WebViewログイン用）。
    func loadLoginPortal() {
        if let url = URL(string: loginPortalURL) {
            webView.load(URLRequest(url: url))
        }
    }

    /// login.cgi のフォームに認証情報を注入して送信する。
    private func injectCredentials(username: String, password: String) {
        let u = username
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let p = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let js = """
            (function() {
                try {
                    var u = document.getElementById('username_input');
                    var p = document.getElementById('password_input');
                    var f = document.getElementById('login');
                    if (u && p && f) {
                        u.value = '\(u)';
                        p.value = '\(p)';
                        u.dispatchEvent(new Event('input', {bubbles: true}));
                        p.dispatchEvent(new Event('input', {bubbles: true}));
                        f.submit();
                    }
                } catch (e) {}
            })();
            """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private enum CgiState {
        case unknown
        case error(String)
        case otp
    }

    private func checkLoginCgiState() async -> CgiState {
        let js = """
            (function() {
                try {
                    var otpSend = document.getElementById('otp_send_button');
                    var dusername = document.getElementById('dusername_area');
                    var commentEl = document.getElementById('comment');
                    var otpVisible = false;
                    if (otpSend && otpSend.style.display !== 'none') otpVisible = true;
                    if (dusername && dusername.children.length > 0) otpVisible = true;
                    if (otpVisible) return JSON.stringify({type: 'otp'});
                    var msg = '';
                    if (commentEl) {
                        var t = (commentEl.innerText || commentEl.textContent || '').trim();
                        if (t && t.length > 1) msg = t;
                    }
                    if (msg) return JSON.stringify({type: 'error', message: msg});
                    return JSON.stringify({type: 'unknown'});
                } catch (e) {
                    return JSON.stringify({type: 'unknown'});
                }
            })();
            """
        return await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(js) { result, _ in
                guard let str = result as? String else {
                    continuation.resume(returning: .unknown)
                    return
                }
                if str.contains("\"type\":\"otp\"") {
                    continuation.resume(returning: .otp)
                } else if str.contains("\"type\":\"error\"") {
                    let regex = try? NSRegularExpression(pattern: "\"message\":\"([^\"]*)\"")
                    let range = NSRange(str.startIndex..<str.endIndex, in: str)
                    if let match = regex?.firstMatch(in: str, range: range),
                       let r = Range(match.range(at: 1), in: str) {
                        continuation.resume(returning: .error(String(str[r])))
                    } else {
                        continuation.resume(returning: .error("ログインに失敗しました"))
                    }
                } else {
                    continuation.resume(returning: .unknown)
                }
            }
        }
    }

    /// ナビゲーションが安定するまで待機する。
    func waitForStableNavigation(maxSeconds: Double = 10) async {
        let stepNs: UInt64 = 100_000_000
        let quietRequired = 5
        let maxSteps = Int(maxSeconds * 10)

        var quietCount = 0
        var totalSteps = 0
        while totalSteps < maxSteps {
            try? await Task.sleep(nanoseconds: stepNs)
            totalSteps += 1
            if webView.isLoading {
                quietCount = 0
            } else {
                quietCount += 1
                if quietCount >= quietRequired { return }
            }
        }
    }

    /// セッション有効性を簡易チェック。
    func checkSession() async -> Bool {
        let js = """
            try {
                const r = await fetch('/direct/site.json?_limit=1', {credentials:'include', cache:'no-store'});
                return await r.text();
            } catch (e) { return ''; }
            """
        do {
            let result = try await webView.callAsyncJavaScript(js, contentWorld: .page)
            let text = result as? String ?? ""
            return text.contains("site_collection") && text.count > 60
        } catch {
            return false
        }
    }

    /// 全 cookie とキャッシュをクリアする（ログアウト時用）。
    func clearAllData() async {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
    }
}

// MARK: - WKNavigationDelegate

extension WebViewManager: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }

        // ナビゲーションリスナー通知（ログイン処理用）
        let listeners = navigationListeners
        for l in listeners { l(url) }

        // ポータル到達自動検知（credential login 中以外）
        if navigationListeners.isEmpty, let callback = onPortalReached {
            let urlString = url.absoluteString
            let isPortalPage = urlString.hasPrefix(baseURL + "/portal")
                && !urlString.contains("/login")
                && !urlString.contains("/relogin")
                && !urlString.contains("/logout")
            if isPortalPage {
                callback()
            }
        }

        // セッション切れ検知: LMS → IIMC へリダイレクトされた場合
        if url.host == iimcHost {
            onSessionExpired?()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // target="_blank" のリンク（targetFrame == nil）の処理
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url {
            if url.host == lmsHost && url.path.hasPrefix("/access/") {
                // /access/... のファイルリンク: モーダル WebView で開く。
                // 同じ WKWebsiteDataStore を共有するため JS 認証が自動で通る。
                // メインの WebView の履歴を一切変えないため戻るボタンが維持される。
                presentModalWebView(url: url)
            } else {
                // それ以外（ツールページ等・外部リンク）は Safari で開く
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        // それ以外は全ナビゲーションを許可（SSO フロー対応）
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if disposition.lowercased().hasPrefix("attachment") {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    // navigationAction からダウンロードに切り替わった場合
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    // navigationResponse からダウンロードに切り替わった場合
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

// MARK: - WKDownloadDelegate

extension WebViewManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let tempDir = FileManager.default.temporaryDirectory
        let destURL = tempDir.appendingPathComponent(suggestedFilename)
        try? FileManager.default.removeItem(at: destURL)
        pendingDownloadURL = destURL
        completionHandler(destURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = pendingDownloadURL else { return }
        pendingDownloadURL = nil
        presentPreview(for: url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        pendingDownloadURL = nil
    }
}

// MARK: - File Presentation

extension WebViewManager {
    /// target="_blank" のファイルリンクをモーダル WebView で開く。
    /// 同じ WKWebsiteDataStore を共有するため JS 認証が自動で通る。
    /// メインの WebView の履歴を変えないため戻るボタンが維持される。
    private func presentModalWebView(url: URL) {
        guard let rootVC = rootViewController() else { return }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = webView.configuration.websiteDataStore
        let modalWebView = WKWebView(frame: .zero, configuration: config)

        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        modalWebView.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(modalWebView)
        NSLayoutConstraint.activate([
            modalWebView.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor),
            modalWebView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            modalWebView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            modalWebView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
        ])

        let navVC = UINavigationController(rootViewController: vc)
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak navVC] _ in navVC?.dismiss(animated: true) }
        )
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.down.circle"),
            primaryAction: UIAction { [weak self, weak modalWebView, weak vc] _ in
                guard let self, let currentURL = modalWebView?.url, let vc else { return }
                Task { await self.downloadAndShare(url: currentURL, from: vc) }
            }
        )

        rootVC.present(navVC, animated: true)
        modalWebView.load(URLRequest(url: url))
    }

    /// モーダル内のファイルをダウンロードして UIActivityViewController で共有する。
    /// モーダル WebView 経由で認証済みのため、同じ Cookie で URLSession が通る。
    private func downloadAndShare(url: URL, from vc: UIViewController) async {
        var request = URLRequest(url: url)
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        do {
            let (tempURL, response) = try await URLSession.shared.download(for: request)
            var filename = response.suggestedFilename
                ?? (url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent)
            if let mimeType = response.mimeType,
               let ext = Self.extensionForMimeType(mimeType),
               !filename.lowercased().hasSuffix(".\(ext)") {
                filename += ".\(ext)"
            }
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.moveItem(at: tempURL, to: destURL)
            let activityVC = UIActivityViewController(activityItems: [destURL], applicationActivities: nil)
            if let popover = activityVC.popoverPresentationController {
                popover.barButtonItem = vc.navigationItem.rightBarButtonItem
            }
            vc.present(activityVC, animated: true)
        } catch {
            print("[KULMS] Download for share failed: \(error)")
        }
    }

    private static func extensionForMimeType(_ mimeType: String) -> String? {
        switch mimeType.lowercased() {
        case "application/pdf": return "pdf"
        case "application/msword": return "doc"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "docx"
        case "application/vnd.ms-powerpoint": return "ppt"
        case "application/vnd.openxmlformats-officedocument.presentationml.presentation": return "pptx"
        case "application/vnd.ms-excel": return "xls"
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": return "xlsx"
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        default: return nil
        }
    }

    /// WKDownload 経由でダウンロードしたファイルを UIDocumentInteractionController で開く。
    private func presentPreview(for url: URL) {
        guard let rootVC = rootViewController() else { return }
        let dic = UIDocumentInteractionController(url: url)
        documentInteractionController = dic
        dic.delegate = self
        dic.presentOptionsMenu(from: rootVC.view.bounds, in: rootVC.view, animated: true)
    }

    private func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController
    }
}

// MARK: - UIDocumentInteractionControllerDelegate

extension WebViewManager: UIDocumentInteractionControllerDelegate {
    func documentInteractionControllerViewControllerForPreview(
        _ controller: UIDocumentInteractionController
    ) -> UIViewController {
        rootViewController() ?? UIViewController()
    }
}

