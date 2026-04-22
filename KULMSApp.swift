import SwiftUI
import UserNotifications
import WebKit

// MARK: - AppState

/// アプリ全体の状態管理（簡素化版）。
/// SwiftData は不要。ログイン状態のみ管理。
class AppState: ObservableObject {
    @Published var isLoggedIn = false
    @Published var isDemoMode = false

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
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    _ = await NotificationService.shared.requestPermission()
                }
                .onAppear {
                    appDelegate.appState = appState
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

// MARK: - AppDelegate (通知タップハンドラ)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // 通知タップ時
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let url = userInfo["targetUrl"] as? String, !url.isEmpty {
            DispatchQueue.main.async {
                WebViewManager.shared.navigate(to: url)
            }
        }
        completionHandler()
    }
}

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isDemoMode {
                DemoWebView()
            } else if appState.isLoggedIn {
                LMSWebView()
            } else {
                LoginView()
            }
        }
    }
}
