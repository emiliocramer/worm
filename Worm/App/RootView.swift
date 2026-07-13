import SwiftUI

/// Entry surface: the personality node graph. Tapping a node pushes its detail
/// view; the system back button returns to the graph.
struct RootView: View {
    @State private var showSplash = true
    @AppStorage("worm.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.93)

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()

            if !showSplash {
                NavigationStack {
                    Group {
                        if hasCompletedOnboarding {
                            // Home's entrance starts on appear; keep it unmounted
                            // until the splash is fully gone so the first crawl
                            // becomes the transition into home, not background work.
                            WormHomeView()
                                .transition(.opacity)
                        } else {
                            OnboardingView()
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.7), value: hasCompletedOnboarding)
                    .navigationDestination(for: NodeRoute.self) { route in
                            switch route {
                            case .profile:
                                ProfileView()
                            case .digging:
                                HomeView(allowsDiggingHaptics: true)
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
                            case .selfie:
                                SelfieNodeView()
                            }
                        }
                }
            }

            if showSplash {
                WormSplashView(onFinished: {
                    showSplash = false
                })
                    .zIndex(1)
            }
        }
        .dismissKeyboardOnOutsideTap()
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
        .environment(SelfieNode())
        .environment(TasteProfile())
}
