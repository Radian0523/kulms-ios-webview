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

        // 候補をソートし上限を適用
        candidates.sort { $0.date < $1.date }
        let scheduled = Array(candidates.prefix(Self.maxPendingNotifications))

        // --- 通知登録（removeAll を使わず、add → stale 削除の順で行う） ---
        // removeAllPendingNotificationRequests() は非同期で secondary thread で実行されるため、
        // 直後の add() とレースが発生し、追加した通知が削除される可能性がある。
        // 代わりに：
        //   1. 新しい通知を先に add（同一 ID は自動で上書き）
        //   2. 不要になった古い通知だけを ID 指定で削除

        // Step 1: 新着課題の即時通知
        for request in newAssignmentRequests {
            do {
                try await center.add(request)
            } catch {
                Self.log.error("failed to add new-assignment notification: \(error.localizedDescription)")
            }
        }

        // Step 2: 締切通知を UNTimeIntervalNotificationTrigger で登録
        // UNCalendarNotificationTrigger は秒を含まないため、同一分内のタイミングで
        // トリガー時刻が過去になるケースがあった。TimeInterval なら確実。
        var addedIds = Set<String>()
        for candidate in scheduled {
            let interval = candidate.date.timeIntervalSinceNow
            guard interval > 0 else {
                Self.log.info("skipping \(candidate.id): interval \(interval)s <= 0")
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = candidate.title
            content.body = candidate.body
            content.sound = .default
            if !candidate.url.isEmpty {
                content.userInfo = ["targetUrl": candidate.url]
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: candidate.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
                addedIds.insert(candidate.id)
            } catch {
                Self.log.error("failed to add \(candidate.id): \(error.localizedDescription)")
            }
        }

        Self.log.info("added \(addedIds.count) deadline notifications")

        // Step 3: 古い kulms- 通知で今回のバッチに含まれないものを削除
        let pending = await center.pendingNotificationRequests()
        let newAssignmentIds = Set(newAssignmentRequests.map { $0.identifier })
        let staleIds = pending
            .map { $0.identifier }
            .filter { id in
                id.hasPrefix("kulms-")
                    && !addedIds.contains(id)
                    && !newAssignmentIds.contains(id)
            }
        if !staleIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIds)
            Self.log.info("removed \(staleIds.count) stale notifications")
        }

        let finalPending = await center.pendingNotificationRequests()
        Self.log.info("scheduling done — added:\(addedIds.count), stale removed:\(staleIds.count), pending in system:\(finalPending.count)")
        for p in finalPending.prefix(5) {
            if let trigger = p.trigger as? UNTimeIntervalNotificationTrigger {
                let fireDate = trigger.nextTriggerDate()
                Self.log.info("  pending: \(p.identifier) fires=\(String(describing: fireDate))")
            } else {
                Self.log.info("  pending: \(p.identifier) trigger=\(String(describing: p.trigger))")
            }
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
}
