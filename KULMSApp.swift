import SwiftUI
import WebKit

// MARK: - AppState

/// アプリ全体の状態管理（簡素化版）。
/// SwiftData は不要。ログイン状態のみ管理。
class AppState: ObservableObject {
    @Published var isLoggedIn = false

    func logout() {
        // Clear cookies
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        // Clear WebView cookies/data
        Task { await WebViewManager.shared.clearAllData() }
        // Clear stored credentials
        CredentialStore.clear()
        isLoggedIn = false
    }
}

// MARK: - App

@main
struct KULMSApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    _ = await NotificationService.shared.requestPermission()
                }
                .onAppear {
                    // セッション切れ検知
                    WebViewManager.shared.onSessionExpired = { [weak appState] in
                        DispatchQueue.main.async {
                            appState?.isLoggedIn = false
                        }
                    }
                }
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isLoggedIn {
                LMSWebView()
            } else {
                LoginView()
            }
        }
    }
}
