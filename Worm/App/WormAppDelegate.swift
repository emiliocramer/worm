import UIKit
import UserNotifications
import AVFoundation

/// Handles local unlock notifications: shows them even in the foreground, and on
/// tap flags that the user came in to see an unlock so the home surface can react.
final class WormAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        configurePreviewAudio()
        return true
    }

    /// Music previews are media, not UI sound effects: `.playback` routes them
    /// through the device's media volume and ignores the ringer/silent switch.
    private func configurePreviewAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("[audio] Could not configure preview playback: \(error.localizedDescription)")
        }
    }

    // Show the banner even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // On tap, broadcast so the home surface can open the waiting unlock.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["route"] as? String == "unlock" {
            await MainActor.run {
                NotificationCenter.default.post(name: .wormUnlockTapped, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let wormUnlockTapped = Notification.Name("worm.unlock.tapped")
    /// Dev-only: force the home to fetch today's server picks and jump straight to
    /// the reveal, bypassing the countdown and the enter-waiting fetch trigger.
    static let wormForceReveal = Notification.Name("worm.force.reveal")
}
