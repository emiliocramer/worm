import Foundation
import UserNotifications

/// Schedules the single local "a new node unlocked" notification. On-device only;
/// the fire time is known when we arm, so no server/push is needed. Uses one
/// stable identifier so re-arming replaces rather than stacks.
final class UnlockNotificationScheduler: UnlockScheduling {
    static let identifier = "worm.unlock"
    private let center = UNUserNotificationCenter.current()

    /// Ask once, contextually. Only prompts when status is not yet determined;
    /// a prior grant or denial is respected silently.
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func schedule(at date: Date, title: String, body: String) {
        // Never schedule in the past; guard against a zero/elapsed interval.
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { cancel(); return }

        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["route": "unlock"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
        center.add(request)
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
}
