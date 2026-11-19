// FaceTracker.swift: "Follow me". Watches the selfie camera at low resolution, finds your face
// on the phone with Apple's Vision framework, and reports where it is so the eyes can look at you.
// Frames are checked in memory and thrown away at once. Nothing leaves the phone.
import AVFoundation
import QuartzCore
import Vision

final class FaceTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Called on the main actor with the face centre (-1...1, +x = your right as you face the
    /// screen, +y = down), or nil when no face has been seen for a moment. Set before start().
    var onFace: @MainActor @Sendable (CGPoint?) -> Void = { _ in }
    /// Called about once a second with how many frames were checked in that second.
    var onRate: @MainActor @Sendable (Int) -> Void = { _ in }

    // Everything below is only touched on `queue`.
    private let queue = DispatchQueue(label: "claudy.facetracker")
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let request = VNDetectFaceRectanglesRequest()
    private var configured = false
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var lastCheck: CFTimeInterval = 0
    private var misses = 0
    private var checksThisSecond = 0
    private var secondStarted: CFTimeInterval = 0

    func start() {
        queue.async { [self] in
            if !configured { configure() }
            if configured, !session.isRunning { session.startRunning() }
        }
    }

    /// Turns the camera fully off (the iOS green dot goes out).
    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            misses = 0
            report(nil)
        }
    }

    private func configure() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }
        session.beginConfiguration()
        session.sessionPreset = .vga640x480          // small frames: cooler phone, longer battery
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true        // like a mirror: you move right, you appear right
        }
        session.commitConfiguration()

        // Run the camera at 15 frames a second; we only check 10 of them anyway.
        if (try? camera.lockForConfiguration()) != nil {
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
            camera.unlockForConfiguration()
        }
        rotation = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        configured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastCheck >= 0.1, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastCheck = now

        // Keep the picture upright however the phone is turned.
        if let angle = rotation?.videoRotationAngleForHorizonLevelCapture,
           connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle {
            connection.videoRotationAngle = angle
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
        try? handler.perform([request])
        let biggest = (request.results ?? []).max { $0.boundingBox.width < $1.boundingBox.width }

        if let face = biggest?.boundingBox {
            misses = 0
            // Vision measures from the bottom-left corner, 0...1. Turn it into -1...1, +y down.
            report(CGPoint(x: face.midX * 2 - 1, y: 1 - face.midY * 2))
        } else {
            misses += 1
            if misses == 5 { report(nil) }           // half a second without a face
        }

        checksThisSecond += 1
        if now - secondStarted >= 1 {
            let rate = checksThisSecond
            checksThisSecond = 0
            secondStarted = now
            let onRate = onRate
            Task { @MainActor in onRate(rate) }
        }
    }

    private func report(_ point: CGPoint?) {
        let onFace = onFace
        Task { @MainActor in onFace(point) }
    }
}
