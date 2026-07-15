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

    // MARK: - Daily dig

    static let dailyIdentifier = "worm.daily-dig"

    /// The recurring "he's back with songs" nudge: fires every day at the user's
    /// chosen delivery time. One stable identifier, so re-arming (a new time, a
    /// renamed worm) replaces rather than stacks. `repeats: true` on a calendar
    /// trigger keeps it firing daily with no server or re-scheduling needed.
    func scheduleDailyDig(hour: Int, minute: Int, wormName: String, songCount: Int = 3) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "\(wormName) is done digging"
        content.body = "found you \(songCount) song\(songCount == 1 ? "" : "s"). come check them out."
        content.sound = .default
        content.userInfo = ["route": "daily-dig"]

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: Self.dailyIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    func cancelDailyDig() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyIdentifier])
    }
}
