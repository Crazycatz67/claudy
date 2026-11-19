// AppState+Brain.swift: Claudy's camera modes (Buddy and Inspect), Follow me, sharing frames with the
// Mac brain, and what Claudy does with each message from the Mac (docs/PROTOCOL.md).
// Privacy: the camera runs only while Claudy is awake, on screen, and you switched something on.
import AVFoundation
import SwiftUI

/// Buddy: front camera, big face. Inspect: back camera on your work, face in a corner bubble.
enum CameraMode: String { case buddy, inspect }

/// A yes/no card shown before the Mac runs anything.
struct ConfirmCard: Identifiable, Equatable { let id: String; let text: String }

extension AppState {
    func setUpBrain() {
        camera.onFace = { [weak self] point in self?.faceMoved(point) }
        camera.onRate = { [weak self] rate in self?.faceChecksPerSecond = rate }
        camera.onLenses = { [weak self] lenses in
            self?.lenses = lenses
            self?.zoom = lenses.dropFirst().first?.zoom ?? 1   // starts on the main (1x) lens
        }
        camera.onFrame = { [weak self] data, w, h, lens, hands in
            self?.sendFrame(data, w: w, h: h, lens: lens, hands: hands)
        }
        camera.onPhoto = { [weak self] id, data, w, h in self?.sendPhoto(id, data, w: w, h: h) }
        link.helloMode = { [weak self] in self?.mode.rawValue ?? "buddy" }
        link.onMessage = { [weak self] type, json in self?.handle(type, json) }
        link.onStatus = { [weak self] status in self?.linkChanged(status) }
        link.start(manualAddress: UserDefaults.standard.string(forKey: "macAddress") ?? "")
    }

    // MARK: Switches you control

    private func cameraAllowed() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { return true }
        return await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Follow me: the eyes look at you. Returns false if camera permission was refused.
    func setFollow(_ on: Bool) async -> Bool {
        if on, await !cameraAllowed() { note("follow me: camera permission refused"); return false }
        followEnabled = on
        if on { lastFaceSeen = Date() }
        note(on ? "follow me: on" : "follow me: off")
        updateCamera()
        return true
    }

    /// Share the camera with the Mac brain (about 3 small pictures a second, local Wi-Fi only).
    func setShare(_ on: Bool) async -> Bool {
        if on, await !cameraAllowed() { note("share: camera permission refused"); return false }
        shareEnabled = on
        note(on ? "share with Mac: on" : "share with Mac: off")
        updateCamera()
        return true
    }

    func setMode(_ new: CameraMode) {
        guard isAwake, new != mode else { return }
        Task {
            if new == .inspect, await !cameraAllowed() { note("inspect: camera permission refused"); return }
            withAnimation(.spring(duration: 0.45)) {
                mode = new
                measuring = false
                measurement = nil
                pointMark = nil
                widget = .face
            }
            haptics.play(.tap)
            link.event("mode", new.rawValue)
            note("mode: \(new.rawValue)")
            updateCamera()
        }
    }

    func setSceneActive(_ active: Bool) {
        sceneActive = active
        if active {
            link.start(manualAddress: UserDefaults.standard.string(forKey: "macAddress") ?? "")
        } else {
            link.stop()
        }
        updateCamera()
        updateWakeWord()
    }

    /// The one place that decides whether the camera runs, and which one.
    func updateCamera() {
        let connected = link.status.isConnected
        var side: CameraSide?
        if isAwake && sceneActive {
            if mode == .inspect { side = measuring ? .depth : .back }
            else if followEnabled || (shareEnabled && connected) { side = .front }
        }
        if let side {
            camera.run(side: side, findFaces: side == .front && followEnabled,
                       sendFrames: shareEnabled && connected,
                       readHands: gesturesEnabled,
                       readText: side != .front && readTextEnabled,
                       autoTorch: side != .front && autoTorchEnabled,
                       digitalFollow: side == .front && UserDefaults.standard.bool(forKey: "digitalFollow"))
            if !cameraOn { lastFaceSeen = Date() }
            cameraOn = true
            cameraSide = side
        } else if cameraOn {
            camera.stop()
            cameraOn = false
            cameraSide = nil
            seesFace = false
            seenText = []
            torchIsOn = false
            distanceCM = nil
            measurement = nil
        }
    }

    private func linkChanged(_ status: BrainLink.Status) {
        switch status {
        case .connected: note("brain connected")
        case .offline: note("brain offline")
        default: break
        }
        updateCamera()
    }

    // MARK: Follow me

    func faceMoved(_ point: CGPoint?) {
        guard let point, cameraOn, cameraSide == .front else { seesFace = false; return }
        seesFace = true
        lastFaceSeen = Date()
        guard reaction != .dizzy else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            look = CGPoint(x: point.x * 0.9, y: point.y * 0.7)
        }
    }

    // MARK: Inspect: tap to point, zoom, lenses

    /// You tapped a spot on the live picture (0...1). Claude gets a close-up of it.
    func point(at spot: CGPoint) {
        touched()
        withAnimation(.spring(duration: 0.3)) { pointMark = spot }
        haptics.play(.tap)
        guard link.status.isConnected else {
            showCaption("Brain offline, so I can't look closer yet.", quiet: true)
            return
        }
        ask("What is this?", point: spot)
    }

    func pinch(by factor: CGFloat) {
        touched()
        let lowest = lenses.first?.zoom ?? 1
        zoom = min(max(zoom * factor, lowest), 15)
        camera.setZoom(zoom)
    }

    func selectLens(_ lens: CameraService.Lens) {
        touched()
        withAnimation(.easeOut(duration: 0.2)) { zoom = lens.zoom }
        camera.setZoom(lens.zoom)
        haptics.play(.tap)
    }

    // MARK: Pictures out (only to your own Mac)

    private func sendFrame(_ jpeg: Data, w: Int, h: Int, lens: String, hands: [CGRect]) {
        guard shareEnabled, link.status.isConnected else { return }
        link.send(["type": "frame", "t": Date().timeIntervalSince1970, "mode": mode.rawValue,
                   "lens": lens, "w": w, "h": h, "distance_cm": distanceCM.map { $0 as Any } ?? NSNull(),
                   "hands": hands.map { ["x": $0.minX, "y": $0.minY, "w": $0.width, "h": $0.height] },
                   "sharp": NSNull()], jpeg: jpeg)
    }

    private func sendPhoto(_ id: String, _ jpeg: Data, w: Int, h: Int) {
        haptics.play(.click)
        guard link.status.isConnected else { savePhotoLocally(jpeg); return }
        link.send(["type": "photo", "id": id, "w": w, "h": h, "distance_cm": NSNull()], jpeg: jpeg)
    }

    // MARK: Messages from the Mac

    private func handle(_ type: String, _ json: [String: Any]) {
        switch type {
        case "welcome":
            haptics.play(.tap)
        case "face":
            if let name = json["state"] as? String, let mood = Expression(rawValue: name) { setExpression(mood) }
            if let spot = Self.point(json["look"]) {
                withAnimation(.easeOut(duration: 0.4)) { look = CGPoint(x: spot.x * 2 - 1, y: spot.y * 2 - 1) }
            }
        case "say":
            say(json["text"] as? String ?? "", quiet: json["quiet"] as? Bool ?? false)
        case "haptic":
            if let pattern = HapticPattern(rawValue: json["pattern"] as? String ?? "") { haptics.play(pattern) }
        case "sending":
            flashPhotoEyes()
        case "torch":
            camera.setTorch(Self.number(json["level"]) ?? 0)
        case "light":
            if let hex = json["color"] as? String, let color = Color(hex: hex) {
                lightColor = color
                withAnimation { widget = .light }
            } else {
                lightColor = nil
                if widget == .light { withAnimation { widget = .face } }
            }
        case "capture":
            guard cameraOn else { showCaption("My camera is off, so I can't take that photo.", quiet: true); return }
            flashPhotoEyes()
            camera.capturePhoto(id: json["id"] as? String ?? "photo")
        case "widget":
            showWidget(json["name"] as? String ?? "", data: json["data"])
        case "confirm":
            wake(because: "question from the Mac")
            confirmCard = ConfirmCard(id: json["id"] as? String ?? "", text: json["text"] as? String ?? "")
            haptics.play(.attention)
        default:
            break   // unknown messages are ignored, so old and new versions can talk
        }
    }

    func answerConfirm(_ yes: Bool) {
        guard let card = confirmCard else { return }
        link.event("confirm", ["id": card.id, "answer": yes ? "yes" : "no"])
        confirmCard = nil
        haptics.play(yes ? .tap : .stop)
        note("confirm: \(yes ? "yes" : "no")")
    }

    private func showWidget(_ name: String, data: Any?) {
        switch name {
        case "crosshair":
            if let spot = Self.point(data) { crosshair = spot }
            withAnimation { widget = .crosshair }
        case "timer":
            if let seconds = Self.number(data) { startTimer(minutes: seconds / 60) }
            withAnimation { widget = .timer }
        case "radar": withAnimation { widget = .radar }
        case "light": withAnimation { widget = .light }
        default: withAnimation { widget = .face }
        }
    }

    /// Shows what Claudy says as a caption. Speaking it aloud arrives in phase B3.
    func showCaption(_ text: String, quiet: Bool) {
        guard !text.isEmpty else { return }
        captionTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { caption = text }
        if quiet { haptics.play(.tap) }
        let seconds = max(3, Double(text.split(separator: " ").count) * 0.4)
        captionTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) { caption = nil }
        }
    }

    /// Photo eyes: a short red flash every time a picture goes to Claude.
    func flashPhotoEyes() {
        flashTask?.cancel()
        withAnimation(.easeOut(duration: 0.1)) { photoFlash = true }
        flashTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { photoFlash = false }
        }
    }

    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

    private static func point(_ value: Any?) -> CGPoint? {
        guard let dict = value as? [String: Any], let x = number(dict["x"]), let y = number(dict["y"]) else { return nil }
        return CGPoint(x: x, y: y)
    }
}
