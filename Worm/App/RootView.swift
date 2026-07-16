import SwiftUI

/// App root: splash first, then onboarding for a new user or the single home
/// surface (`WormHomeView`) for a returning one.
struct RootView: View {
    @State private var showSplash = true
    @State private var showedOnboardingThisSession = false
    @AppStorage("worm.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.93)

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()

            if !showSplash {
                NavigationStack {
                    Group {
                        if hasCompletedOnboarding {
                            // A fresh home is mounted after either entry path.
                            // Onboarding gets a short handoff delay so its fade
                            // cannot hide the scene's opening layers.
                            WormHomeView(
                                buildsForestOnEntry: true,
                                forestBuildDelay: showedOnboardingThisSession ? 0.65 : 0
                            )
                                .transition(.opacity)
                        } else {
                            OnboardingView()
                                .transition(.opacity)
                                .onAppear { showedOnboardingThisSession = true }
                        }
                    }
                    .animation(.easeInOut(duration: 0.7), value: hasCompletedOnboarding)
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
