import Foundation
import UIKit

/// Home Screen Quick Actions (3D Touch / Long Press) に課題を登録する。
/// UserDefaults のキャッシュから締切が近い順に最大4件を表示。
enum QuickActionService {
    private static let storageKey = "kulms-extension-storage"

    /// UserDefaults から課題データを読み取り、Quick Actions を更新する。
    static func updateQuickActions() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let store = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assignmentsData = store["kulms-assignments"] as? [String: Any],
              let assignments = assignmentsData["assignments"] as? [[String: Any]] else {
            UIApplication.shared.shortcutItems = []
            return
        }

        let checkedState = store["kulms-checked-assignments"] as? [String: Any] ?? [:]
        let now = Date.now
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"

        struct Candidate {
            let name: String
            let courseName: String
            let deadline: Date
            let url: String
        }

        var candidates: [Candidate] = []

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

            // チェック済の課題はスキップ
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
            let url = assignment["url"] as? String
                ?? "https://lms.gakusei.kyoto-u.ac.jp/portal/site/\(courseId)"

            candidates.append(Candidate(
                name: name,
                courseName: courseName,
                deadline: deadline,
                url: url
            ))
        }

        // 締切が近い順にソートし、最大4件を取得
        candidates.sort { $0.deadline < $1.deadline }
        let top = candidates.prefix(4)

        let shortcutItems: [UIApplicationShortcutItem] = top.map { candidate in
            let title = "締切: \(formatter.string(from: candidate.deadline))"
            let subtitle = "\(candidate.courseName) - \(candidate.name)"
            return UIApplicationShortcutItem(
                type: "com.radian0523.kulms.assignment",
                localizedTitle: title,
                localizedSubtitle: subtitle,
                icon: UIApplicationShortcutIcon(systemImageName: "doc.text"),
                userInfo: ["url": candidate.url as NSString]
            )
        }

        UIApplication.shared.shortcutItems = shortcutItems
    }
}
