import SwiftUI

@main
struct WormApp: App {
    // Each personality node is created once and lives for the lifetime of the
    // app so its in-memory snapshot persists across navigation.
    @State private var spotifyNode = SpotifyMusicNode()
    @State private var appleMusicNode = AppleMusicNode()
    @State private var youTubeNode = YouTubeCultureNode()
    @State private var contactsNode = ContactsNode()
    @State private var photosNode = PhotosNode()
    @State private var calendarNode = CalendarNode()
    @State private var selfieNode = SelfieNode()
    @State private var tasteProfile = TasteProfile()
    @State private var progression = NodeProgression(scheduler: UnlockNotificationScheduler())
    @State private var promptNode = PromptNode()

    @UIApplicationDelegateAdaptor(WormAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(spotifyNode)
                .environment(appleMusicNode)
                .environment(youTubeNode)
                .environment(contactsNode)
                .environment(photosNode)
                .environment(calendarNode)
                .environment(selfieNode)
                .environment(tasteProfile)
                .environment(progression)
                .environment(promptNode)
                .task {
                    if DevFlags.constantTesting {
                        // Replay the FTUE every launch, but keep every node's
                        // persisted setup. Testing onboarding must not force the
                        // user to reconnect data sources.
                        tasteProfile.clear()
                        DevFlags.resetOnboarding()
                        await spotifyNode.restoreSessionIfPossible()
                        await appleMusicNode.restoreSessionIfPossible()
                        await youTubeNode.restoreSessionIfPossible()
                        await contactsNode.restoreSessionIfPossible()
                        await photosNode.restoreSessionIfPossible()
                        await calendarNode.restoreSessionIfPossible()
                        await selfieNode.restoreSessionIfPossible()
                        await promptNode.restoreSessionIfPossible()
                        return
                    }
                    await spotifyNode.restoreSessionIfPossible()
                    await appleMusicNode.restoreSessionIfPossible()
                    await youTubeNode.restoreSessionIfPossible()
                    await contactsNode.restoreSessionIfPossible()
                    await photosNode.restoreSessionIfPossible()
                    await calendarNode.restoreSessionIfPossible()
                    await selfieNode.restoreSessionIfPossible()
                    await promptNode.restoreSessionIfPossible()
                    // The taste profile loads its persisted understanding in its
                    // own init; it re-synthesizes only when a surface asks (first
                    // connect or refresh), never silently on launch.
                }
        }
    }
}
