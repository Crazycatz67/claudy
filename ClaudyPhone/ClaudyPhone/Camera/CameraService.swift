// CameraService.swift: owns the phone camera. Front camera in Buddy mode, back camera (all lenses,
// smooth zoom) in Inspect mode. Feeds frames to face finding and, when allowed, small JPEGs to the
// Mac brain about 3 times a second. Also takes full-detail photos and drives the torch.
import AVFoundation
import CoreImage
import QuartzCore
import UIKit

enum CameraSide: String, Sendable { case front, back }

final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                           AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    // Callbacks, set once before start(). All are delivered on the main actor.
    var onFace: @MainActor @Sendable (CGPoint?) -> Void = { _ in }
    var onRate: @MainActor @Sendable (Int) -> Void = { _ in }
    var onFrame: @MainActor @Sendable (Data, Int, Int, String, [CGRect]) -> Void = { _, _, _, _, _ in }
    var onHands: @MainActor @Sendable (HandSighting) -> Void = { _ in }
    var onText: @MainActor @Sendable ([String]) -> Void = { _ in }
    var onTorch: @MainActor @Sendable (Bool) -> Void = { _ in }
    var onPhoto: @MainActor @Sendable (String, Data, Int, Int) -> Void = { _, _, _, _ in }
    var onLenses: @MainActor @Sendable ([Lens]) -> Void = { _ in }

    struct Lens: Sendable, Hashable { let name: String; let zoom: CGFloat }

    /// The live session, for the on-screen preview in Inspect mode.
    let session = AVCaptureSession()

    // Everything below is only touched on `queue`.
    private let queue = DispatchQueue(label: "claudy.camera")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let faces = FaceFinder()
    private let hands = HandReader()
    private let texts = TextReader()
    private var readHands = false
    private var readText = false
    private var autoTorch = false
    private var lastHands: CFTimeInterval = 0
    private var lastText: CFTimeInterval = 0
    private var lastLight: CFTimeInterval = 0
    private var darkSince: CFTimeInterval?
    private var torchOn = false
    private var handBoxes: [CGRect] = []
    private let ciContext = CIContext()
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private var side: CameraSide?
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var findFaces = false
    private var sendFrames = false
    private var lastFaceCheck: CFTimeInterval = 0
    private var lastSend: CFTimeInterval = 0
    private var misses = 0
    private var checks = 0
    private var secondStarted: CFTimeInterval = 0
    private var pendingPhotoIDs: [Int64: String] = [:]

    /// Start (or switch) the camera. `findFaces` = Follow me, `sendFrames` = share with the Mac.
    func run(side newSide: CameraSide, findFaces: Bool, sendFrames: Bool,
             readHands: Bool = false, readText: Bool = false, autoTorch: Bool = false) {
        queue.async { [self] in
            self.findFaces = findFaces
            self.sendFrames = sendFrames
            self.readHands = readHands
            self.readText = readText
            if self.autoTorch && !autoTorch && torchOn { setTorchNow(0); reportTorch(false) }
            self.autoTorch = autoTorch
            if side != newSide { configure(newSide) }
            if !session.isRunning { session.startRunning() }
        }
    }

    /// Turns the camera fully off (the iOS green dot goes out).
    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            setTorchNow(0)
            if torchOn { reportTorch(false) }
            darkSince = nil
            misses = 0
            handBoxes = []
            deliverFace(nil)
        }
    }

    func setZoom(_ factor: CGFloat) {
        queue.async { [self] in
            guard let device, (try? device.lockForConfiguration()) != nil else { return }
            let lowest = device.minAvailableVideoZoomFactor
            let highest = min(device.maxAvailableVideoZoomFactor, 15)
            device.videoZoomFactor = min(max(factor, lowest), highest)
            device.unlockForConfiguration()
        }
    }

    func setTorch(_ level: Double) { queue.async { [self] in setTorchNow(level) } }

    /// One full-resolution photo; delivered through onPhoto with the given id.
    func capturePhoto(id: String) {
        queue.async { [self] in
            guard session.isRunning, photoOutput.connection(with: .video) != nil else { return }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality
            pendingPhotoIDs[settings.uniqueID] = id
            if let angle = rotation?.videoRotationAngleForHorizonLevelCapture,
               let connection = photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: Setup

    private func configure(_ newSide: CameraSide) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let input { session.removeInput(input) }
        input = nil
        device = nil
        side = nil

        let found: AVCaptureDevice?
        if newSide == .front {
            found = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        } else {
            // A "virtual" camera that hops between ultra-wide, main and telephoto as you zoom.
            found = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
        guard let found, let newInput = try? AVCaptureDeviceInput(device: found),
              session.canAddInput(newInput) else { return }
        session.addInput(newInput)
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high

        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
        }
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = newSide == .front   // selfie view acts like a mirror
        }
        if (try? found.lockForConfiguration()) != nil {       // 15 fps is plenty, and cooler
            found.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            found.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
            if newSide == .back, found.isVirtualDevice {
                // Start on the main lens, not the ultra-wide.
                let main = found.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1
                found.videoZoomFactor = main
            }
            found.unlockForConfiguration()
        }
        input = newInput
        device = found
        side = newSide
        rotation = AVCaptureDevice.RotationCoordinator(device: found, previewLayer: nil)
        let lenses = Self.lenses(of: found, side: newSide)
        let onLenses = onLenses
        Task { @MainActor in onLenses(lenses) }
    }

    /// Lens buttons, labelled the way the Camera app does (0.5x, 1x, 4x...).
    private static func lenses(of device: AVCaptureDevice, side: CameraSide) -> [Lens] {
        guard side == .back, device.isVirtualDevice else { return [] }
        let switches = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let main = switches.first ?? 1     // zoom factor where the main (1x) lens takes over
        var lenses = [Lens(name: "0.5x", zoom: 1)]
        for factor in switches {
            let shown = factor / main
            lenses.append(Lens(name: shown == shown.rounded() ? "\(Int(shown))x" : String(format: "%.1fx", shown),
                               zoom: factor))
        }
        return lenses
    }

    private func setTorchNow(_ level: Double) {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        if level <= 0.01 {
            device.torchMode = .off
        } else {
            try? device.setTorchModeOn(level: Float(min(level, 1)))
        }
        device.unlockForConfiguration()
    }

    // MARK: Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = CACurrentMediaTime()

        // Keep the picture upright however the phone is turned.
        if let angle = rotation?.videoRotationAngleForHorizonLevelCapture,
           connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }

        if findFaces, now - lastFaceCheck >= 0.1 {
            lastFaceCheck = now
            if let point = faces.centre(in: pixels) {
                misses = 0
                deliverFace(point)
            } else {
                misses += 1
                if misses == 5 { deliverFace(nil) }      // half a second without a face
            }
            checks += 1
            if now - secondStarted >= 1 {
                let rate = checks, onRate = onRate
                checks = 0
                secondStarted = now
                Task { @MainActor in onRate(rate) }
            }
        }

        if readHands, now - lastHands >= 0.2 {      // 5 times a second
            lastHands = now
            let sighting = hands.read(pixels)
            handBoxes = sighting.boxes
            let onHands = onHands
            Task { @MainActor in onHands(sighting) }
        }

        if readText, now - lastText >= 0.5 {
            lastText = now
            let lines = texts.read(pixels)
            let onText = onText
            Task { @MainActor in onText(lines) }
        }

        if autoTorch, side == .back, now - lastLight >= 0.5 {
            lastLight = now
            adjustTorch(brightness: Self.brightness(of: pixels), now: now)
        }

        if sendFrames, now - lastSend >= 0.33, let jpeg = jpeg(from: pixels, longSide: 1280) {
            lastSend = now
            let onFrame = onFrame, lens = side == .front ? "front" : "back", boxes = handBoxes
            Task { @MainActor in onFrame(jpeg.data, jpeg.width, jpeg.height, lens, boxes) }
        }
    }

    private func jpeg(from pixels: CVPixelBuffer, longSide: CGFloat) -> (data: Data, width: Int, height: Int)? {
        var image = CIImage(cvPixelBuffer: pixels)
        let scale = min(1, longSide / max(image.extent.width, image.extent.height))
        if scale < 1 { image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let data = ciContext.jpegRepresentation(of: image, colorSpace: space,
                  options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6])
        else { return nil }
        return (data, Int(image.extent.width), Int(image.extent.height))
    }

    /// Auto flashlight: on after 2 seconds of a dark picture, brighter the darker it is;
    /// off again only when the room is clearly bright (so the torch's own light doesn't flicker it).
    private func adjustTorch(brightness: Double, now: CFTimeInterval) {
        if !torchOn {
            if brightness < 0.18 {
                if let since = darkSince, now - since >= 2 {
                    setTorchNow(max(0.3, min(1, (0.18 - brightness) * 8)))
                    torchOn = true
                    reportTorch(true)
                } else if darkSince == nil {
                    darkSince = now
                }
            } else {
                darkSince = nil
            }
        } else if brightness > 0.8 {
            setTorchNow(0)
            torchOn = false
            darkSince = nil
            reportTorch(false)
        }
    }

    private func reportTorch(_ on: Bool) {
        torchOn = on
        let onTorch = onTorch
        Task { @MainActor in onTorch(on) }
    }

    /// Average brightness 0...1 from a sample of the picture's light (luma) values.
    private static func brightness(of pixels: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard CVPixelBufferIsPlanar(pixels), let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return 0.5 }
        let width = CVPixelBufferGetWidthOfPlane(pixels, 0), height = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var total = 0, count = 0
        for y in Swift.stride(from: 0, to: height, by: 16) {
            for x in Swift.stride(from: 0, to: width, by: 16) {
                total += Int(bytes[y * stride + x])
                count += 1
            }
        }
        return count > 0 ? Double(total) / Double(count) / 255 : 0.5
    }

    private func deliverFace(_ point: CGPoint?) {
        let onFace = onFace
        Task { @MainActor in onFace(point) }
    }

    // MARK: Photos

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let id = pendingPhotoIDs.removeValue(forKey: photo.resolvedSettings.uniqueID) ?? "photo"
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        let size = photo.resolvedSettings.photoDimensions
        let onPhoto = onPhoto
        Task { @MainActor in onPhoto(id, data, Int(size.width), Int(size.height)) }
    }
}
