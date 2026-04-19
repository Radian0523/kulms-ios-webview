import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private static let maxPendingNotifications = 64
    private static let defaultOffsets = [1440, 60] // 24h, 1h (minutes)
    private static let offsetsKey = "notificationOffsets"

    private init() {}

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    // MARK: - Notification Offsets

    static func loadNotificationOffsets() -> [Int] {
        guard let data = UserDefaults.standard.data(forKey: offsetsKey),
              let offsets = try? JSONDecoder().decode([Int].self, from: data),
              !offsets.isEmpty else {
            return defaultOffsets
        }
        return offsets
    }

    // MARK: - Schedule from Extension Data

    /// 拡張機能から受け取った課題辞書配列から通知をスケジュールする。
    ///
    /// - Parameters:
    ///   - assignments: 課題辞書の配列（拡張機能の assignments.js が生成）
    ///   - checkedState: kulms-checked-assignments の辞書
    func scheduleFromExtensionData(
        assignments: [[String: Any]],
        checkedState: [String: Any]
    ) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let offsets = Self.loadNotificationOffsets()
        let now = Date.now

        struct NotificationCandidate {
            let id: String
            let title: String
            let body: String
            let date: Date
        }

        var candidates: [NotificationCandidate] = []

        for assignment in assignments {
            // 締切がない課題はスキップ
            guard let deadlineMs = assignment["deadline"] as? Double,
                  deadlineMs > 0 else { continue }
            let deadline = Date(timeIntervalSince1970: deadlineMs / 1000.0)

            // 過去の締切はスキップ
            guard deadline > now else { continue }

            // 提出済の課題はスキップ
            let status = assignment["status"] as? String ?? ""
            if !status.isEmpty { continue }

            // compositeKey を生成
            let entityId = assignment["entityId"] as? String ?? ""
            let courseId = assignment["courseId"] as? String ?? ""
            let name = assignment["name"] as? String ?? ""
            let compositeKey = entityId.isEmpty ? "\(courseId):\(name)" : entityId

            // チェック済の課題はスキップ（値が truthy かつ "active" でなければスキップ）
            if let checkedValue = checkedState[compositeKey] {
                let isTruthy: Bool
                if let boolVal = checkedValue as? Bool {
                    isTruthy = boolVal
                } else if let intVal = checkedValue as? Int {
                    isTruthy = intVal != 0
                } else if let strVal = checkedValue as? String {
                    isTruthy = !strVal.isEmpty
                } else {
                    isTruthy = true
                }
                if isTruthy && "\(checkedValue)" != "active" {
                    continue
                }
            }

            let courseName = assignment["courseName"] as? String ?? ""

            for offset in offsets {
                let date = deadline.addingTimeInterval(-Double(offset) * 60)
                guard date > now else { continue }

                let label = Self.formatOffsetLabel(offset)
                let title: String
                if offset <= 60 {
                    title = String(localized: "notifTitleSoon")
                } else {
                    title = String(localized: "notifTitleApproaching")
                }
                let body = String(
                    format: String(localized: "notifBody"),
                    name, courseName, label
                )

                candidates.append(NotificationCandidate(
                    id: "kulms-\(offset)m-\(compositeKey)",
                    title: title,
                    body: body,
                    date: date
                ))
            }
        }

        // 日付順（最も近い順）でソートし、64 件に制限
        candidates.sort { $0.date < $1.date }
        for candidate in candidates.prefix(Self.maxPendingNotifications) {
            schedule(id: candidate.id, title: candidate.title,
                     body: candidate.body, date: candidate.date)
        }
    }

    // MARK: - Helpers

    static func formatOffsetLabel(_ minutes: Int) -> String {
        if minutes >= 1440 && minutes % 1440 == 0 {
            return String(format: String(localized: "offsetDays"), minutes / 1440)
        } else if minutes >= 60 && minutes % 60 == 0 {
            return String(format: String(localized: "offsetHours"), minutes / 60)
        } else {
            return String(format: String(localized: "offsetMins"), minutes)
        }
    }

    private func schedule(id: String, title: String, body: String, date: Date) {
        guard date > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }
}
