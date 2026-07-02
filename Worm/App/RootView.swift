import SwiftUI

/// Entry surface: the personality node graph. Tapping a node pushes its detail
/// view; the system back button returns to the graph.
struct RootView: View {
    @State private var showSplash = true
    @AppStorage("worm.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            NavigationStack {
                Group {
                    if hasCompletedOnboarding {
                        HomeView()
                    } else {
                        OnboardingView()
                    }
                }
                .navigationDestination(for: NodeRoute.self) { route in
                        switch route {
                        case .profile:
                            ProfileView()
                        case .profileChat:
                            ProfileChatView()
                        case .graph:
                            PersonalityGraphView()
                        case .spotify:
                            MusicNodeView()
                        case .appleMusic:
                            AppleMusicNodeView()
                        case .youtube:
                            YouTubeCultureNodeView()
                        case .contacts:
                            ContactsNodeView()
                        case .photos:
                            PhotosNodeView()
                        case .calendar:
                            CalendarNodeView()
                        }
                    }
            }

            if showSplash {
                WormSplashView(onFinished: { showSplash = false })
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }
}

#Preview {
    RootView()
        .environment(SpotifyMusicNode())
        .environment(AppleMusicNode())
        .environment(YouTubeCultureNode())
        .environment(ContactsNode())
        .environment(PhotosNode())
        .environment(CalendarNode())
        .environment(TasteProfile())
}
