import SwiftUI

/// The worm's spoken greeting, centered as the home screen's hero: a little
/// inchworm above a contextual line ("Enjoying New York, Emilio?"), drawn in the
/// same ink-on-paper palette as the splash so the transition is seamless.
///
/// Tapping it lets the user set the name the worm uses — a one-time in-app
/// field, never a system prompt.
struct WormGreetingView: View {
    @Bindable var greeting: WormGreeting

    @State private var appeared = false
    @State private var showingNamePrompt = false
    @State private var draftName = ""

    private let ink = Color.black
    private let paper = Color(red: 0.97, green: 0.96, blue: 0.93)

    var body: some View {
        VStack(spacing: 24) {
            InchwormLoader(color: ink.opacity(0.9), eyeColor: paper)
                .frame(width: 128, height: 76)

            Text(greeting.message)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 36)
                .contentTransition(.opacity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            draftName = greeting.editableName
            showingNamePrompt = true
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.easeOut(duration: 0.6), value: appeared)
        .animation(.easeInOut(duration: 0.35), value: greeting.message)
        .onAppear { appeared = true }
        .alert("What should I call you?", isPresented: $showingNamePrompt) {
            TextField("Name", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Save") { greeting.setName(draftName) }
            Button("Clear", role: .destructive) { greeting.setName("") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The worm will greet you by this name. Stored on-device only.")
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.97, green: 0.96, blue: 0.93).ignoresSafeArea()
        WormGreetingView(greeting: WormGreeting())
    }
}
