import SwiftUI
import UIKit

/// Cross-cutting store for the per-node "food" emblem — the image mapped onto
/// the center of the apple the worm eats. A node's emblem resolves as:
/// custom (user-picked, persisted) -> else the node's SF Symbol glyph.
///
/// It's a singleton rather than an @Environment value because the same emblems
/// render from the home morsel, the onboarding morsel, and the profile gallery
/// — including inside the profile's replay-demo `fullScreenCover`, where
/// environment propagation is fussy. Customization is app-wide, not per-tree.
@Observable
final class FoodVisualStore {
    static let shared = FoodVisualStore()

    /// entryID -> filename on disk. Observed: reads in a view body track it, so
    /// picking or clearing an image live-updates every apple on screen.
    private(set) var customFilenames: [String: String]

    @ObservationIgnored private var cache: [String: UIImage] = [:]
    @ObservationIgnored private let indexStore = SnapshotStore<[String: String]>(filename: "food-visuals-index.json")

    init() {
        customFilenames = indexStore.load() ?? [:]
    }

    /// The user-picked emblem for a node, or nil to fall back to its glyph.
    func customImage(for id: String) -> UIImage? {
        guard let name = customFilenames[id] else { return nil }
        if let cached = cache[id] { return cached }
        guard let data = try? Data(contentsOf: Self.fileURL(name)),
              let image = UIImage(data: data) else { return nil }
        cache[id] = image
        return image
    }

    func hasCustomImage(for id: String) -> Bool { customFilenames[id] != nil }

    /// Store a picked image for a node, downscaled so the on-disk emblem stays
    /// small. Best-effort, like SnapshotStore: a failure is never a correctness
    /// problem, the node just keeps its glyph fallback.
    func setImage(_ image: UIImage, for id: String) {
        let scaled = Self.downscaled(image, maxDimension: 512)
        guard let data = scaled.pngData() else { return }
        let name = "food-visual-\(id).png"
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try data.write(to: Self.fileURL(name), options: .atomic)
        } catch { return }
        cache[id] = scaled
        customFilenames[id] = name
        indexStore.save(customFilenames)
    }

    func clearImage(for id: String) {
        if let name = customFilenames[id] {
            try? FileManager.default.removeItem(at: Self.fileURL(name))
        }
        cache[id] = nil
        customFilenames[id] = nil
        indexStore.save(customFilenames)
    }

    // MARK: - Paths / scaling

    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static func fileURL(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// The food: a node's emblem mapped onto a 2D apple. Replaces the old
/// ink-circle+glyph morsel. The base apple is the `FoodApple` image asset
/// (placeholder art — swap the PNG); the emblem is the node's custom image or,
/// failing that, its SF Symbol glyph on a light disc for legibility.
struct FoodAppleView: View {
    let entry: NodeCatalogEntry
    var size: CGFloat = 62
    /// The emblem/logo diameter. Nil scales it with the apple (42%); pass an
    /// explicit value to keep the emblem fixed while the apple grows, so more
    /// of the apple shows around it.
    var emblemSize: CGFloat? = nil
    var ink: Color = Color(red: 0.11, green: 0.10, blue: 0.09)
    var paper: Color = Color(red: 0.97, green: 0.96, blue: 0.93)

    // Read the shared store inside the body so its observable state tracks.
    private var store: FoodVisualStore { .shared }

    private var emblemDimension: CGFloat { emblemSize ?? size * 0.42 }

    var body: some View {
        ZStack {
            Image("FoodApple")
                .resizable()
                .scaledToFit()
            emblem
                .frame(width: emblemDimension, height: emblemDimension)
                // Sit on the apple's belly: its body center is a touch below the
                // asset's geometric center (room for stem + leaf up top).
                .offset(y: size * 0.06)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: size * 0.2, y: size * 0.1)
    }

    @ViewBuilder private var emblem: some View {
        if let image = store.customImage(for: entry.id) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay(Circle().stroke(paper.opacity(0.9), lineWidth: max(1, emblemDimension * 0.07)))
        } else {
            ZStack {
                Circle().fill(paper.opacity(0.94))
                Image(systemName: entry.glyph)
                    .font(.system(size: emblemDimension * 0.48, weight: .bold))
                    .foregroundStyle(ink.opacity(0.85))
            }
        }
    }
}
