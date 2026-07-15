import SwiftUI

/// The home screen — the "digging" screen. Once connected, this is where you
/// live while your worm combs the internet for music made for you. No worm, no
/// greeting: the screen itself is the act of digging (`DiggingView`).
///
/// The developer node-graph still lives behind a Liquid Glass button in the
/// top-left when `DevFlags.showGraphButton` is set.
struct HomeView: View {
    var allowsDiggingHaptics = true
    @State private var showHiddenProfile = false

    var body: some View {
        DiggingView(allowsHaptics: allowsDiggingHaptics)
            .overlay(alignment: .bottom) {
                Text("Combing the internet…\ncome back soon.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.black.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    // A soft paper halo so the copy stays readable over the colors.
                    .background(
                        Color(red: 0.97, green: 0.96, blue: 0.93)
                            .opacity(0.7)
                            .blur(radius: 16)
                    )
                    .padding(.bottom, 40)
            }
            // Graph button hidden for now — uncomment to bring back the dev node-graph.
            // .overlay(alignment: .topLeading) {
            //     if DevFlags.showGraphButton {
            //         NavigationLink(value: NodeRoute.graph) {
            //             Label("graph", systemImage: "point.3.connected.trianglepath.dotted")
            //                 .font(.system(size: 14, weight: .medium))
            //                 .foregroundStyle(.black.opacity(0.72))
            //                 .padding(.horizontal, 14)
            //                 .padding(.vertical, 9)
            //                 .liquidGlass(in: Capsule())
            //         }
            //         .buttonStyle(.plain)
            //         .padding(.horizontal, 20)
            //         .padding(.top, 6)
            //     }
            // }
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .topTrailing) {
                hiddenProfileHotspot
                    .padding(.trailing, 8)
                    .padding(.top, 6)
            }
            .navigationDestination(isPresented: $showHiddenProfile) {
                ProfileView()
            }
    }

    /// Deliberately invisible: two taps in the top-right corner reveal the profile.
    private var hiddenProfileHotspot: some View {
        Color.clear
            .frame(width: 72, height: 72)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                showHiddenProfile = true
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environment(SpotifyMusicNode())
    .environment(AppleMusicNode())
    .environment(YouTubeCultureNode())
    .environment(ContactsNode())
    .environment(PhotosNode())
    .environment(CalendarNode())
    .environment(SelfieNode())
    .environment(TasteProfile())
}
