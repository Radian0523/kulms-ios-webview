import Foundation
import os.log
import UserNotifications

final class NotificationService {
    private static let log = Logger(subsystem: "com.radian0523.kulms-plus-for-ios", category: "Notification")
    static let shared = NotificationService()
    private static let maxPendingNotifications = 64
    private static let defaultOffsets = [1440, 60] // 24h, 1h (minutes)
    private static let offsetsKey = "notificationOffsets"
    private static let newAssignmentKey = "newAssignmentNotification"
    private static let knownKeysKey = "knownAssignmentKeys"

    /// scheduleFromExtensionData の並行実行を防ぐためのロック
    private let scheduleLock = NSLock()
    private var scheduleTask: Task<Void, Never>?

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

    static func saveNotificationOffsets(_ offsets: [Int]) {
        let data = try? JSONEncoder().encode(offsets)
        UserDefaults.standard.set(data, forKey: offsetsKey)
    }

    // MARK: - New Assignment Notification

    static func loadNewAssignmentNotification() -> Bool {
        UserDefaults.standard.object(forKey: newAssignmentKey) as? Bool ?? true
    }

    static func saveNewAssignmentNotification(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: newAssignmentKey)
    }

    private static func loadKnownAssignmentKeys() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: knownKeysKey),
              let keys = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        return keys
    }

    private static func saveKnownAssignmentKeys(_ keys: Set<String>) {
        let data = try? JSONEncoder().encode(keys)
        UserDefaults.standard.set(data, forKey: knownKeysKey)
    }

    static func formatOffsetLabelBefore(_ minutes: Int) -> String {
        if minutes >= 1440 && minutes % 1440 == 0 {
            return String(format: String(localized: "offsetDaysBefore"), minutes / 1440)
        } else if minutes >= 60 && minutes % 60 == 0 {
            return String(format: String(localized: "offsetHoursBefore"), minutes / 60)
        } else {
            return String(format: String(localized: "offsetMinsBefore"), minutes)
        }
    }

    // MARK: - Schedule from Extension Data

    /// 拡張機能から受け取った課題辞書配列から通知をスケジュールする。
    ///
    /// - Parameters:
    ///   - assignments: 課題辞書の配列（拡張機能の assignments.js が生成）
    ///   - checkedState: kulms-checked-assignments の辞書
    /// 呼び出しをキューイングし、最後の呼び出しだけを実行する。
    func scheduleFromExtensionData(
        assignments: [[String: Any]],
        checkedState: [String: Any]
    ) {
        scheduleLock.lock()
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            await self?.doSchedule(assignments: assignments, checkedState: checkedState)
        }
        scheduleLock.unlock()
    }

    private func doSchedule(
        assignments: [[String: Any]],
        checkedState: [String: Any]
    ) async {
        Self.log.info("doSchedule called: \(assignments.count) assignments, \(checkedState.count) checked")

        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        Self.log.info("authorizationStatus = \(String(describing: settings.authorizationStatus.rawValue))")
        guard settings.authorizationStatus == .authorized else {
            Self.log.warning("notifications not authorized — aborting schedule")
            return
        }

        let offsets = Self.loadNotificationOffsets()
        Self.log.info("offsets = \(offsets)")
        let now = Date.now
        let notifyNew = Self.loadNewAssignmentNotification()
        let knownKeys = Self.loadKnownAssignmentKeys()
        Self.log.info("notifyNew=\(notifyNew), knownKeys count=\(knownKeys.count)")

        struct NotificationCandidate {
            let id: String
            let title: String
            let body: String
            let date: Date
            let url: String
        }

        var candidates: [NotificationCandidate] = []
        var currentKeys = Set<String>()
        var newAssignmentRequests: [UNNotificationRequest] = []

        var skippedNoDeadline = 0, skippedPast = 0, skippedSubmitted = 0, skippedChecked = 0

        for assignment in assignments {
            let name = assignment["name"] as? String ?? ""
            // 締切がない課題はスキップ
            guard let deadlineMs = assignment["deadline"] as? Double,
                  deadlineMs > 0 else {
                skippedNoDeadline += 1
                continue
            }
            let deadline = Date(timeIntervalSince1970: deadlineMs / 1000.0)

            // 過去の締切はスキップ
            guard deadline > now else {
                skippedPast += 1
                continue
            }

            // 提出済の課題はスキップ
            let status = assignment["status"] as? String ?? ""
            if !status.isEmpty {
                skippedSubmitted += 1
                continue
            }

            // compositeKey を生成
            let entityId = assignment["entityId"] as? String ?? ""
            let courseId = assignment["courseId"] as? String ?? ""
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
                    skippedChecked += 1
                    continue
                }
            }

            let courseName = assignment["courseName"] as? String ?? ""
            let url = assignment["url"] as? String
                ?? "https://lms.gakusei.kyoto-u.ac.jp/portal/site/\(courseId)"

            currentKeys.insert(compositeKey)

            // 新着課題の即時通知（後でまとめて登録）
            if notifyNew && !knownKeys.isEmpty && !knownKeys.contains(compositeKey) {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "notifNewAssignmentTitle")
                content.body = String(
                    format: String(localized: "notifNewAssignmentBody"),
                    name, courseName
                )
                content.sound = .default
                content.userInfo = ["targetUrl": url]

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                newAssignmentRequests.append(UNNotificationRequest(
                    identifier: "kulms-new-\(compositeKey)",
                    content: content,
                    trigger: trigger
                ))
            }

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
                    date: date,
                    url: url
                ))
            }
        }

        // キャンセルされていたら中断
        guard !Task.isCancelled else {
            Self.log.info("schedule cancelled (superseded by newer call)")
            return
        }

        Self.log.info("filter results — noDeadline:\(skippedNoDeadline) past:\(skippedPast) submitted:\(skippedSubmitted) checked:\(skippedChecked) → candidates:\(candidates.count)")

        // 既知の課題キーを更新
        if !currentKeys.isEmpty {
            Self.saveKnownAssignmentKeys(currentKeys)
        }

        // 候補が揃ってから一括で削除→登録（通知ゼロの窓を最小化）
        candidates.sort { $0.date < $1.date }
        let scheduled = Array(candidates.prefix(Self.maxPendingNotifications))

        center.removeAllPendingNotificationRequests()

        for request in newAssignmentRequests {
            try? await center.add(request)
        }
        for candidate in scheduled {
            schedule(id: candidate.id, title: candidate.title,
                     body: candidate.body, date: candidate.date, url: candidate.url)
        }

        // スケジュール後のペンディング通知数を確認
        let pending = await center.pendingNotificationRequests()
        Self.log.info("scheduling done — requested:\(scheduled.count), pending in system:\(pending.count)")
        for p in pending.prefix(5) {
            Self.log.info("  pending: \(p.identifier) trigger=\(String(describing: p.trigger))")
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

    private func schedule(id: String, title: String, body: String, date: Date, url: String = "") {
        guard date > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if !url.isEmpty {
            content.userInfo = ["targetUrl": url]
        }

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.log.error("failed to add notification \(id): \(error.localizedDescription)")
            }
        }
    }
}
