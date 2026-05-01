import SwiftUI
import WebKit

/// メイン画面: LMS を WKWebView でフルスクリーン表示し、
/// 拡張機能のコンテンツスクリプトが注入された状態で操作できる。
struct LMSWebView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            WebViewContainer()
                .ignoresSafeArea(.container, edges: .bottom)

            // ツールバー
            HStack {
                Button {
                    WebViewManager.shared.webView.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.medium))
                }
                .disabled(!canGoBack)

                Button {
                    WebViewManager.shared.webView.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.medium))
                }
                .disabled(!canGoForward)

                Spacer()

                Button {
                    WebViewManager.shared.webView.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.medium))
                }

                Spacer()

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "bell")
                        .font(.body.weight(.medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onLogout: logout)
        }
        .onAppear {
            startObserving()
            if !hasInitiallyLoaded {
                hasInitiallyLoaded = true
                WebViewManager.shared.loadPortal()
            }
        }
        .onDisappear {
            stopObserving()
        }
    }

    // MARK: - State

    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var showSettings = false
    @State private var hasInitiallyLoaded = false
    @State private var backObserver: NSKeyValueObservation?
    @State private var forwardObserver: NSKeyValueObservation?

    private func startObserving() {
        let wv = WebViewManager.shared.webView
        backObserver = wv.observe(\.canGoBack, options: .new) { _, change in
            DispatchQueue.main.async { canGoBack = change.newValue ?? false }
        }
        forwardObserver = wv.observe(\.canGoForward, options: .new) { _, change in
            DispatchQueue.main.async { canGoForward = change.newValue ?? false }
        }
    }

    private func stopObserving() {
        backObserver?.invalidate()
        forwardObserver?.invalidate()
    }

    private func logout() {
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        Task { await WebViewManager.shared.clearAllData() }
        CredentialStore.clear()
        appState.isLoggedIn = false
    }
}

// MARK: - WebViewContainer

/// UIViewRepresentable で WebViewManager.shared.webView をフルスクリーン表示する。
private struct WebViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let wv = WebViewManager.shared.webView
        wv.allowsBackForwardNavigationGestures = true
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
