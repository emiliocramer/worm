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
struct PromptCaptureView: View {
    let entry: NodeCatalogEntry
    let ink: Color
    let paper: Color
    var onCancel: () -> Void
    var onSubmit: (PromptCaptureValue) -> Void

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
        ZStack(alignment: .topLeading) {
            paper.ignoresSafeArea()

            closeButton
                .padding(.leading, 20)
                .padding(.top, 16)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 32)
                .padding(.top, 96)
        }
    }

    // MARK: - Chrome

    private var closeButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.opacity(0.5))
                .frame(width: 40, height: 40)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.captureKind {
        case .text:   textContent
        case .choice: choiceContent
        case .photo:  photoContent
        case .source: sourceGuard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
            Text(entry.subtitle)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - .text

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            header

            TextField("", text: $text, prompt: placeholderText)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(ink)
                .tint(ink)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .onChange(of: text) { _, newValue in
                    if newValue.count > charLimit {
                        text = String(newValue.prefix(charLimit))
                    }
                }

            doneButton(enabled: !trimmedText.isEmpty) {
                onSubmit(.text(trimmedText))
            }
        }
    }

    private var placeholderText: Text {
        Text(entry.prompt?.placeholder ?? "")
            .foregroundColor(ink.opacity(0.3))
    }

    // MARK: - .choice

    private var choiceContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            header

            chips

            if entry.prompt?.allowsFreeText == true {
                TextField("", text: $text, prompt: Text("something else").foregroundColor(ink.opacity(0.3)))
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(ink)
                    .tint(ink)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: text) { _, newValue in
                        if !newValue.isEmpty { selectedChip = nil }
                        if newValue.count > charLimit {
                            text = String(newValue.prefix(charLimit))
                        }
                    }
            }

            doneButton(enabled: choiceAnswer != nil) {
                if let answer = choiceAnswer { onSubmit(.text(answer)) }
            }
        }
    }

    /// Selected chip wins; otherwise the free-text answer if present.
    private var choiceAnswer: String? {
        if let selectedChip { return selectedChip }
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private var chips: some View {
        FlowChips(options: entry.prompt?.options ?? []) { option in
            Button {
                Haptics.tick()
                selectedChip = option
                text = ""   // picking a chip clears free-text
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
        VStack(alignment: .leading, spacing: 28) {
            header

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
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
                        }
                        loadingPhoto = false
                    }
                }
            }

            if image != nil {
                doneButton(enabled: true) {
                    if let image { onSubmit(.photo(image)) }
                }
            }
        }
    }

    // MARK: - .source guard

    private var sourceGuard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("nothing to answer here.")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
            Button(action: onCancel) {
                Text("close")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(ink, in: Capsule())
            }
        }
    }

    // MARK: - shared

    private func doneButton(enabled: Bool, action: @escaping () -> Void) -> some View {
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
        .disabled(!enabled)
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
        entry: NodeCatalog.entry("latest-book")!,
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

#Preview("photo") {
    PromptCaptureView(
        entry: NodeCatalog.entry("fit-photo")!,
        ink: .black,
        paper: previewPaper,
        onCancel: {},
        onSubmit: { _ in }
    )
}
