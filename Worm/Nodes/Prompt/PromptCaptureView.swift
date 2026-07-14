import SwiftUI
import PhotosUI
import UIKit

/// What a prompt capture yields back to the caller.
enum PromptCaptureValue {
    case text(String)     // .text and .choice both resolve to a string answer
    case photo(UIImage)   // .photo prompts
}

/// A standalone sheet that collects one self-report answer for a prompt node.
/// Paper-and-ink, terse and lowercase, matching onboarding. The caller presents
/// it and does something with whatever comes back through `onSubmit`.
///
/// The per-kind input lives in `PromptInputSection` (which reports its answer via
/// a binding) so the in-scene base-apple detail can reuse the exact same
/// controls and place its own confirm button wherever it likes.
struct PromptCaptureView: View {
    let entry: NodeCatalogEntry
    let ink: Color
    let paper: Color
    var onCancel: () -> Void
    var onSubmit: (PromptCaptureValue) -> Void

    @State private var answer: PromptCaptureValue?

    var body: some View {
        ZStack {
            background

            VStack(spacing: 24) {
                Spacer(minLength: 8)
                FoodAppleView(entry: entry, size: 80)
                titleBlock
                PromptInputSection(entry: entry, ink: ink, paper: paper, answer: $answer)
                doneButton
                Spacer(minLength: 0)
                waitingWorm
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .padding(.top, 72)
            .padding(.bottom, 20)
        }
        .overlay(alignment: .topLeading) {
            closeButton
                .padding(.leading, 20)
                .padding(.top, 16)
        }
    }

    // MARK: - Background & chrome

    private var background: some View {
        ZStack {
            paper.ignoresSafeArea()
            RadialGradient(
                gradient: Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.9).opacity(0.75), .clear]),
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 20,
                endRadius: 460
            )
            .ignoresSafeArea()
        }
    }

    private var closeButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.opacity(0.5))
                .frame(width: 40, height: 40)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 10) {
            Text(entry.title)
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
            Text(entry.subtitle)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(ink.opacity(0.5))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var doneButton: some View {
        PromptDoneButton(enabled: answer != nil, ink: ink, paper: paper) {
            if let answer { onSubmit(answer) }
        }
    }

    private var waitingWorm: some View {
        VStack(spacing: 8) {
            OnboardingWormGlyph(
                size: OnboardingWormSize(length: 96, thickness: 16),
                color: ink.opacity(0.85),
                eyeColor: paper
            )
            .frame(width: 190, height: 68)
            Text("he's waiting")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(ink.opacity(0.35))
        }
    }
}

/// The per-kind answer controls for a prompt entry (text / choice / photo). It
/// owns the raw input state and reports a valid answer (or nil) through `answer`;
/// the caller owns the confirm button. Reused by the fullscreen
/// `PromptCaptureView` and by the in-scene base-apple detail on home.
struct PromptInputSection: View {
    let entry: NodeCatalogEntry
    let ink: Color
    let paper: Color
    @Binding var answer: PromptCaptureValue?

    // .text / .choice free-text
    @State private var text = ""
    // .choice selection
    @State private var selectedChip: String?
    // .photo
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var loadingPhoto = false

    private var charLimit: Int { entry.prompt?.charLimit ?? 120 }
    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        switch entry.captureKind {
        case .text:   textContent
        case .choice: choiceContent
        case .photo:  photoContent
        case .source: EmptyView()
        }
    }

    // MARK: - .text

    private var textContent: some View {
        TextField("", text: $text, prompt: placeholderText)
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundStyle(ink)
            .tint(ink)
            .multilineTextAlignment(.center)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .onChange(of: text) { _, newValue in
                if newValue.count > charLimit { text = String(newValue.prefix(charLimit)) }
                answer = trimmedText.isEmpty ? nil : .text(trimmedText)
            }
    }

    private var placeholderText: Text {
        Text(entry.prompt?.placeholder ?? "")
            .foregroundColor(ink.opacity(0.3))
    }

    // MARK: - .choice

    private var choiceContent: some View {
        VStack(alignment: .center, spacing: 18) {
            chips

            if entry.prompt?.allowsFreeText == true {
                TextField("", text: $text, prompt: Text("something else").foregroundColor(ink.opacity(0.3)))
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(ink)
                    .tint(ink)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: text) { _, newValue in
                        if !newValue.isEmpty { selectedChip = nil }
                        if newValue.count > charLimit { text = String(newValue.prefix(charLimit)) }
                        updateChoiceAnswer()
                    }
            }
        }
    }

    private func updateChoiceAnswer() {
        if let selectedChip { answer = .text(selectedChip) }
        else { answer = trimmedText.isEmpty ? nil : .text(trimmedText) }
    }

    private var chips: some View {
        FlowChips(options: entry.prompt?.options ?? []) { option in
            Button {
                Haptics.tick()
                selectedChip = option
                text = ""   // picking a chip clears free-text
                updateChoiceAnswer()
            } label: {
                Text(option)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(selectedChip == option ? paper : ink)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(
                        selectedChip == option ? ink : ink.opacity(0.06),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - .photo

    private var photoContent: some View {
        // v1: photo library; camera capture can come later.
        VStack(spacing: 18) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            }

            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Text(image == nil ? "pick a photo" : "pick another")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(ink, in: Capsule())
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                loadingPhoto = true
                Task {
                    let loaded = try? await item.loadTransferable(type: Data.self)
                    await MainActor.run {
                        if let loaded, let picked = UIImage(data: loaded) {
                            Haptics.impact(.light, intensity: 0.6)
                            image = picked
                            answer = .photo(picked)
                        }
                        loadingPhoto = false
                    }
                }
            }
        }
    }
}

/// The shared "done" pill, so the fullscreen sheet and the in-scene detail read
/// identically.
struct PromptDoneButton: View {
    let enabled: Bool
    let ink: Color
    let paper: Color
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.success()
            action()
        } label: {
            Text("done")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(enabled ? ink : ink.opacity(0.25), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// The photo apple's below-the-worm controls. No selection → a primary "pick a
/// photo". Once picked → a primary "done" with a small "pick another" beneath.
/// The picked image is reported up via `answer`; the preview is shown elsewhere
/// (in the detail's mid area).
struct BasePhotoActions: View {
    let ink: Color
    let paper: Color
    @Binding var answer: PromptCaptureValue?
    var onDone: () -> Void

    @State private var pickerItem: PhotosPickerItem?

    private var hasImage: Bool {
        if case .photo = answer { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 10) {
            if hasImage {
                PromptDoneButton(enabled: true, ink: ink, paper: paper, action: onDone)
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Text("pick another")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(ink.opacity(0.5))
                }
                .buttonStyle(.plain)
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Text("pick a photo")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                let loaded = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let loaded, let img = UIImage(data: loaded) {
                        Haptics.impact(.light, intensity: 0.6)
                        answer = .photo(img)
                    }
                }
            }
        }
    }
}

/// A left-aligned wrapping row of chips. Keeps choices tidy without a fixed grid.
private struct FlowChips<Chip: View>: View {
    let options: [String]
    @ViewBuilder let chip: (String) -> Chip

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(options, id: \.self) { chip($0) }
        }
    }
}

/// Minimal flowing layout: places subviews left to right, wrapping to the next
/// line when the current one runs out of width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Previews

private let previewPaper = Color(red: 0.97, green: 0.96, blue: 0.93)

#Preview("text") {
    PromptCaptureView(
        entry: NodeCatalog.entry("ideal-saturday")!,
        ink: .black,
        paper: previewPaper,
        onCancel: {},
        onSubmit: { _ in }
    )
}

#Preview("choice") {
    PromptCaptureView(
        entry: NodeCatalog.entry("comfort-movie")!,
        ink: .black,
        paper: previewPaper,
        onCancel: {},
        onSubmit: { _ in }
    )
}
