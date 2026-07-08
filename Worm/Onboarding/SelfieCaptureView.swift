import SwiftUI
import UIKit
import AVFoundation

/// The first ask: a selfie, snapped straight into the worm. Paper-and-ink like
/// the rest of onboarding — a slightly crooked polaroid viewfinder, one fat
/// shutter, and the payoff: the photo shrinks down into the worm, he gulps it,
/// grows longer, does a little hop. Now he knows your face.
struct SelfieCaptureView: View {
    let ink: Color
    let paper: Color
    var onDone: () -> Void

    @State private var camera = SelfieCameraController()
    @State private var cameraReady = false
    @State private var denied = false
    @State private var photo: UIImage?
    @State private var flash = false
    /// True once the photo starts travelling into the worm.
    @State private var fed = false
    /// Wall-clock moment of the swallow; drives the worm's pop-and-hop.
    @State private var gulpStart: Double?
    @State private var showGulp = false
    @State private var eaten = false

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            // Everything is placed by hand off one column of math, so the feed
            // provably lands on the worm at any screen size.
            let polaroidWidth = min(W * 0.74, 340, H * 0.40)
            let polaroidHeight = (polaroidWidth - 20) * 4 / 3 + 62
            let polaroidCenter = CGPoint(x: W / 2, y: H * 0.42)
            let headlineY = polaroidCenter.y - polaroidHeight / 2 - 36
            let shutterY = polaroidCenter.y + polaroidHeight / 2 + 56
            let wormCenter = CGPoint(x: W / 2, y: max(shutterY + 90, H * 0.89))

            ZStack {
                SnackingWorm(
                    restCenter: wormCenter,
                    gulpStart: gulpStart,
                    color: ink,
                    eyeColor: paper
                )
                .allowsHitTesting(false)

                if denied {
                    deniedView
                } else {
                    Text(headline)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(ink.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .id(headline)
                        .transition(.opacity)
                        .position(x: W / 2, y: headlineY)

                    polaroid(width: polaroidWidth)
                        .rotationEffect(.degrees(fed ? 16 : -2.4))
                        .scaleEffect(fed ? 0.02 : 1)
                        .position(fed ? wormCenter : polaroidCenter)
                        .opacity(showGulp || eaten ? 0 : 1)

                    shutter
                        .opacity(photo == nil ? 1 : 0)
                        .position(x: W / 2, y: shutterY)
                }

                if showGulp {
                    Text("mm.")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink.opacity(0.6))
                        .position(x: wormCenter.x, y: wormCenter.y - 52)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(width: W, height: H)
        }
        .animation(.easeInOut(duration: 0.35), value: headline)
        .task { await setUp() }
        .onDisappear { camera.stop() }
    }

    private var headline: String {
        if eaten { return "got it. that's you saved." }
        if photo != nil { return "there you are." }
        return "say cheese."
    }

    // MARK: - Pieces

    /// A white polaroid, worn at a slight angle: the live camera (or the frozen
    /// snap) up top, a chin below for the caption.
    private func polaroid(width: CGFloat) -> some View {
        let inner = width - 20
        return VStack(spacing: 0) {
            ZStack {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else if camera.isAvailable {
                    CameraPreviewView(session: camera.session)
                        .opacity(cameraReady ? 1 : 0)
                } else {
                    SimulatorFacePlaceholder(ink: ink)
                }
                if flash { Color.white }
            }
            .frame(width: inner, height: inner * 4 / 3)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            Text(photo == nil ? " " : "you.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(ink.opacity(0.5))
                .frame(height: 42)
        }
        .padding(10)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: ink.opacity(0.16), radius: 14, y: 8)
    }

    private var shutter: some View {
        Button(action: snap) {
            ZStack {
                Circle().fill(ink).frame(width: 72, height: 72)
                Circle().stroke(paper.opacity(0.9), lineWidth: 2.5).frame(width: 58, height: 58)
            }
        }
        .buttonStyle(ShutterButtonStyle())
        .disabled(!cameraReady || photo != nil)
    }

    private var deniedView: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 180)
            Text("no camera, then.")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(ink.opacity(0.88))
            Text("that's alright, I'll manage.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(ink.opacity(0.5))
                .padding(.top, 10)
            Spacer()
            Button(action: { Haptics.impact(.medium); onDone() }) {
                Text("carry on")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(ink, in: Capsule())
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 36)
    }

    // MARK: - Flow

    private func setUp() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCamera()
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                startCamera()
            } else {
                withAnimation(.easeInOut(duration: 0.4)) { denied = true }
            }
        default:
            withAnimation(.easeInOut(duration: 0.4)) { denied = true }
        }
    }

    private func startCamera() {
        camera.start {
            withAnimation(.easeIn(duration: 0.5)) { cameraReady = true }
        }
    }

    private func snap() {
        guard photo == nil, cameraReady else { return }
        Haptics.impact(.rigid)
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { flash = true }
        withAnimation(.easeOut(duration: 0.55).delay(0.08)) { flash = false }

        camera.capture { image in
            let snapped = image ?? SelfieCameraController.doodleSelfie(ink: UIColor.black)
            SelfieStore.save(snapped)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { photo = snapped }
            Task { await feedTheWorm() }
        }
    }

    /// The payoff: a beat to admire the snap, then it dives into the worm.
    private func feedTheWorm() async {
        try? await Task.sleep(for: .seconds(1.25))
        Haptics.impact(.light, intensity: 0.6)
        withAnimation(.easeIn(duration: 0.75)) { fed = true }

        try? await Task.sleep(for: .seconds(0.75))
        gulpStart = Date().timeIntervalSinceReferenceDate
        Haptics.impact(.heavy)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { showGulp = true }

        try? await Task.sleep(for: .seconds(1.0))
        withAnimation(.easeInOut(duration: 0.4)) {
            showGulp = false
            eaten = true
        }
        Haptics.success()

        try? await Task.sleep(for: .seconds(1.9))
        onDone()
    }
}

/// A hard press-in on the shutter, like a real camera button.
private struct ShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - The worm, waiting for his snack

/// The onboarding dot worm, drawn full-screen so he's never clipped. When
/// `gulpStart` lands he pops fat for a beat, hops, and settles back to his
/// normal girth but about twice as long — he DID just eat your face.
private struct SnackingWorm: View {
    var restCenter: CGPoint
    var gulpStart: Double?
    var color: Color
    var eyeColor: Color

    private static let worm = Worm(
        wobbleRatio: 0.06,
        gaitHeightRatio: 0.3,
        gaitSpeed: 2.4,
        gaitStepiness: 0.06,
        gaitDrift: 0.02
    )

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, _ in
                var w = Self.worm
                w.color = color
                w.eyeColor = eyeColor

                var length: CGFloat = 15
                var thickness: CGFloat = 16
                var center = restCenter

                if let g = gulpStart {
                    let dt = max(0, t - g)
                    // A fast fat pop that fully deflates, and a permanent stretch:
                    // eating doesn't fatten him, it grows him to about twice as long.
                    let pop = dt < 0.16 ? dt / 0.16 : exp(-(dt - 0.16) * 2.4)
                    let settled = min(1, dt / 0.8)
                    thickness *= 1 + CGFloat(pop) * 1.0
                    length *= 1 + CGFloat(pop) * 0.3 + CGFloat(settled) * 1.0
                    // Happy hop once it's down.
                    let hop = dt - 0.22
                    if hop > 0, hop < 0.55 {
                        center.y -= CGFloat(sin(hop / 0.55 * .pi)) * 16
                    }
                }

                w.thickness = thickness
                let x0 = center.x - length / 2
                let centerline = (0...10).map {
                    CGPoint(x: x0 + length * CGFloat($0) / 10, y: center.y)
                }
                w.draw(in: context, centerline: centerline, time: t)
            }
        }
    }
}

// MARK: - Camera plumbing

/// Front-camera session + single-shot capture. On the simulator (no camera)
/// every path still works: the preview shows a doodle stand-in and `capture`
/// returns a rendered version of it, so the whole flow is testable.
final class SelfieCameraController: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "worm.selfie.session")
    private var onCapture: ((UIImage?) -> Void)?

    var isAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    func start(onReady: @escaping () -> Void) {
        #if targetEnvironment(simulator)
        DispatchQueue.main.async(execute: onReady)
        #else
        queue.async {
            if self.session.inputs.isEmpty {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    if self.session.canAddOutput(self.output) {
                        self.session.addOutput(self.output)
                    }
                }
                self.session.commitConfiguration()
            }
            if !self.session.inputs.isEmpty {
                self.session.startRunning()
            }
            DispatchQueue.main.async(execute: onReady)
        }
        #endif
    }

    func stop() {
        #if !targetEnvironment(simulator)
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
        #endif
    }

    func capture(_ completion: @escaping (UIImage?) -> Void) {
        #if targetEnvironment(simulator)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            completion(Self.doodleSelfie(ink: .black))
        }
        #else
        onCapture = completion
        queue.async {
            guard self.session.isRunning else {
                DispatchQueue.main.async { self.onCapture?(nil); self.onCapture = nil }
                return
            }
            self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
        #endif
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation()
            .flatMap(UIImage.init(data:))?
            .selfieMirrored
        DispatchQueue.main.async {
            self.onCapture?(image)
            self.onCapture = nil
        }
    }

    /// The simulator's "selfie": the same doodle face the placeholder preview
    /// shows, rendered to an image so the feed animation has something to eat.
    static func doodleSelfie(ink: UIColor) -> UIImage {
        let size = CGSize(width: 600, height: 800)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ink.withAlphaComponent(0.85).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 210, y: 320, width: 34, height: 34))
            ctx.cgContext.fillEllipse(in: CGRect(x: 356, y: 320, width: 34, height: 34))
            ink.withAlphaComponent(0.85).setStroke()
            ctx.cgContext.setLineWidth(10)
            ctx.cgContext.setLineCap(.round)
            ctx.cgContext.addArc(
                center: CGPoint(x: 300, y: 420), radius: 70,
                startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false
            )
            ctx.cgContext.strokePath()
        }
    }
}

/// Live front-camera preview, filling its frame.
private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// What the polaroid shows in the simulator: a doodle face waiting where yours
/// would be.
private struct SimulatorFacePlaceholder: View {
    let ink: Color

    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.93, blue: 0.90)
            Canvas { context, size in
                let cx = size.width / 2
                let eyeY = size.height * 0.42
                let r: CGFloat = 9
                for dx in [-38.0, 38.0] {
                    context.fill(
                        Path(ellipseIn: CGRect(x: cx + dx - r, y: eyeY - r, width: r * 2, height: r * 2)),
                        with: .color(ink.opacity(0.85))
                    )
                }
                var smile = Path()
                smile.addArc(
                    center: CGPoint(x: cx, y: size.height * 0.52), radius: 36,
                    startAngle: .degrees(30), endAngle: .degrees(150), clockwise: false
                )
                context.stroke(smile, with: .color(ink.opacity(0.85)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            VStack {
                Spacer()
                Text("(simulator you)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.35))
                    .padding(.bottom, 14)
            }
        }
    }
}

/// Front-camera snaps read backwards to the person in them — mirror the image
/// so the keeper matches what the preview showed.
private extension UIImage {
    var selfieMirrored: UIImage {
        guard let cg = cgImage else { return self }
        let mirrored: UIImage.Orientation
        switch imageOrientation {
        case .up: mirrored = .upMirrored
        case .down: mirrored = .downMirrored
        case .left: mirrored = .rightMirrored
        case .right: mirrored = .leftMirrored
        default: return self
        }
        return UIImage(cgImage: cg, scale: scale, orientation: mirrored)
    }
}

// MARK: - Storage

/// Where the worm keeps your face. One file, overwritten on re-snap — profile
/// features can read it from here later.
enum SelfieStore {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("worm-selfie.jpg")
    }

    static func save(_ image: UIImage) {
        try? image.jpegData(compressionQuality: 0.9)?.write(to: url, options: .atomic)
    }
}

#Preview {
    ZStack {
        Color(red: 0.97, green: 0.96, blue: 0.93).ignoresSafeArea()
        SelfieCaptureView(
            ink: .black,
            paper: Color(red: 0.97, green: 0.96, blue: 0.93),
            onDone: {}
        )
    }
}
