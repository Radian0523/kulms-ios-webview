import Foundation
import WebKit

/// chrome.storage.local ↔ UserDefaults ブリッジ。
/// JS から webkit.messageHandlers.kulmsStorage.postMessage() で呼び出され、
/// UserDefaults に永続化した結果を evaluateJavaScript でコールバック返却する。
final class KulmsStorageHandler: NSObject, WKScriptMessageHandler {
    static let messageName = "kulmsStorage"
    private let storageKey = "kulms-extension-storage"

    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let callbackId = body["callbackId"] as? String else { return }

        switch action {
        case "get":
            handleGet(keys: body["keys"] as? [String], callbackId: callbackId)
        case "set":
            handleSet(items: body["items"] as? [String: Any] ?? [:], callbackId: callbackId)
        case "remove":
            handleRemove(keys: body["keys"] as? [String] ?? [], callbackId: callbackId)
        case "clear":
            handleClear(callbackId: callbackId)
        default:
            sendCallback(callbackId: callbackId, data: [:])
        }
    }

    // MARK: - Handlers

    private func handleGet(keys: [String]?, callbackId: String) {
        let store = loadStore()
        if let keys = keys {
            var result: [String: Any] = [:]
            for key in keys {
                if let value = store[key] {
                    result[key] = value
                }
            }
            sendCallback(callbackId: callbackId, data: result)
        } else {
            // null keys → return all
            sendCallback(callbackId: callbackId, data: store)
        }
    }

    private func handleSet(items: [String: Any], callbackId: String) {
        var store = loadStore()
        for (key, value) in items {
            store[key] = value
        }
        saveStore(store)
        sendCallback(callbackId: callbackId, data: [:])

        // 課題データ更新時に通知をスケジュール
        if items["kulms-assignments"] != nil || items["kulms-checked-assignments"] != nil {
            if let data = store["kulms-assignments"] as? [String: Any],
               let assignments = data["assignments"] as? [[String: Any]] {
                let checked = store["kulms-checked-assignments"] as? [String: Any] ?? [:]
                Task {
                    await NotificationService.shared.scheduleFromExtensionData(
                        assignments: assignments,
                        checkedState: checked
                    )
                }
            }
        }
    }

    private func handleRemove(keys: [String], callbackId: String) {
        var store = loadStore()
        for key in keys {
            store.removeValue(forKey: key)
        }
        saveStore(store)
        sendCallback(callbackId: callbackId, data: [:])
    }

    private func handleClear(callbackId: String) {
        saveStore([:])
        sendCallback(callbackId: callbackId, data: [:])
    }

    // MARK: - Storage

    private func loadStore() -> [String: Any] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func saveStore(_ store: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: store) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Callback

    private func sendCallback(callbackId: String, data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            callJS("window.__kulmsStorageCallback('\(callbackId)', {})")
            return
        }
        let escaped = jsonString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        callJS("window.__kulmsStorageCallback('\(callbackId)', JSON.parse('\(escaped)'))")
    }

    private func callJS(_ js: String) {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
