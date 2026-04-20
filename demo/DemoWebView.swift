import SwiftUI
import WebKit

/// デモモード専用画面。本番の WebViewManager は使用しない。
/// Bundle 内の demo.html を独立した WKWebView で表示する。
struct DemoWebView: View {
    @EnvironmentObject private var appState: AppState

    @State private var webView = WKWebView()
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var backObserver: NSKeyValueObservation?
    @State private var forwardObserver: NSKeyValueObservation?

    var body: some View {
        VStack(spacing: 0) {
            DemoWebViewContainer(webView: webView)
                .ignoresSafeArea(.container, edges: .bottom)

            // ツールバー
            HStack {
                Button {
                    webView.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.medium))
                }
                .disabled(!canGoBack)

                Button {
                    webView.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.medium))
                }
                .disabled(!canGoForward)

                Spacer()

                Button {
                    webView.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.medium))
                }

                Spacer()

                Button {
                    appState.isDemoMode = false
                } label: {
                    Text("Exit Demo")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .onAppear {
            loadDemoPage()
            startObserving()
        }
        .onDisappear {
            stopObserving()
        }
    }

    private func loadDemoPage() {
        guard let url = Bundle.main.url(forResource: "demo", withExtension: "html") else { return }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func startObserving() {
        backObserver = webView.observe(\.canGoBack, options: .new) { _, change in
            DispatchQueue.main.async { canGoBack = change.newValue ?? false }
        }
        forwardObserver = webView.observe(\.canGoForward, options: .new) { _, change in
            DispatchQueue.main.async { canGoForward = change.newValue ?? false }
        }
    }

    private func stopObserving() {
        backObserver?.invalidate()
        forwardObserver?.invalidate()
    }
}

// MARK: - UIViewRepresentable

private struct DemoWebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
