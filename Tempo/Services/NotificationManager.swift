import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    static let categoryIdentifier = "TIMER_ENDED"
    static let addFiveMinAction = "ADD_FIVE_MIN"
    static let addFifteenMinAction = "ADD_FIFTEEN_MIN"
    static let completeAction = "COMPLETE_TASK"

    var onTimerExtend: ((String, TimeInterval) -> Void)?
    var onTaskComplete: ((String) -> Void)?

    private override init() {
        super.init()
    }

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        let addFive = UNNotificationAction(
            identifier: Self.addFiveMinAction,
            title: "+5분",
            options: .foreground
        )
        let addFifteen = UNNotificationAction(
            identifier: Self.addFifteenMinAction,
            title: "+15분",
            options: .foreground
        )
        let complete = UNNotificationAction(
            identifier: Self.completeAction,
            title: "완료",
            options: .foreground
        )

        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [addFive, addFifteen, complete],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
    }

    func scheduleTimerNotification(taskId: String, taskTitle: String, fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Tempo"
        content.body = "\"\(taskTitle)\" 시간이 끝났어요"
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["taskId": taskId]

        let interval = fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: "timer-\(taskId)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    func cancelNotification(taskId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["timer-\(taskId)"]
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let taskId = response.notification.request.content.userInfo["taskId"] as? String ?? ""

        switch response.actionIdentifier {
        case Self.addFiveMinAction:
            onTimerExtend?(taskId, 5 * 60)
        case Self.addFifteenMinAction:
            onTimerExtend?(taskId, 15 * 60)
        case Self.completeAction:
            onTaskComplete?(taskId)
        default:
            break
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
