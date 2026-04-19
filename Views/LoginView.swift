import SwiftUI
import WebKit

/// ログイン画面のルート。
/// デフォルトでは独自 UI（CredentialLoginView）を表示。
/// 多要素認証が必要な場合は WebView ログイン UI に切り替える。
struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var useWebView = false

    var body: some View {
        Group {
            if useWebView {
                WebViewLoginPanel(onBack: { useWebView = false })
            } else {
                CredentialLoginView(onRequireWebViewLogin: { useWebView = true })
            }
        }
        .onChange(of: appState.isLoggedIn) { _, newValue in
            if newValue == false {
                useWebView = false
            }
        }
    }
}

// MARK: - WebView fallback (for 2FA / passkey)

struct WebViewLoginPanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var isVerifying = false
    @State private var errorText: String?

    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SSOWebView()

            VStack(spacing: 8) {
                if let error = errorText {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    handleLogin()
                } label: {
                    if isVerifying {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                            Text(String(localized: "verifying"))
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text(String(localized: "loginDone"))
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isVerifying)

                Text(String(localized: "tapAfterAuth"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(String(localized: "backToCredentials"), action: onBack)
                    .font(.caption)
                    .disabled(isVerifying)
            }
            .padding()
            .background(.bar)
        }
    }

    private func handleLogin() {
        guard !isVerifying else { return }
        isVerifying = true
        errorText = nil

        Task {
            let valid = await WebViewManager.shared.checkSession()
            if valid {
                appState.isLoggedIn = true
            } else {
                errorText = String(localized: "sessionNotConfirmed")
            }
            isVerifying = false
        }
    }
}

// MARK: - WKWebView Wrapper

struct SSOWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let wv = WebViewManager.shared.webView
        wv.allowsBackForwardNavigationGestures = true
        if wv.url == nil {
            let url = URL(string: "https://lms.gakusei.kyoto-u.ac.jp/portal")!
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
