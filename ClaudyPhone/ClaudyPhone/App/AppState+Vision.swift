// AppState+Vision.swift: what Claudy does with what the phone itself sees: hand gestures
// (thumbs up = photo, open palm = pause watching, pointing = this one), eyes following your hands,
// instant text reading in Inspect mode, the auto flashlight, and saving photos when the Mac is off.
import Photos
import SwiftUI

extension AppState {
    func setUpVision() {
        camera.onHands = { [weak self] sighting in self?.handsSeen(sighting) }
        camera.onText = { [weak self] lines in self?.textSeen(lines) }
        camera.onTorch = { [weak self] on in
            self?.torchIsOn = on
            self?.note(on ? "auto torch: on" : "auto torch: off")
        }
    }

    /// Settings switches (all on unless you turn them off).
    var gesturesEnabled: Bool { UserDefaults.standard.object(forKey: "handGestures") as? Bool ?? true }
    var readTextEnabled: Bool { UserDefaults.standard.object(forKey: "readText") as? Bool ?? true }
    var autoTorchEnabled: Bool { UserDefaults.standard.object(forKey: "autoTorch") as? Bool ?? true }

    // MARK: Hands

    private func handsSeen(_ sighting: HandSighting) {
        // Eyes follow your hands when no face is in view (T1).
        if !seesFace, cameraSide == .front, let hand = sighting.boxes.first, reaction == nil {
            withAnimation(.easeOut(duration: 0.3)) {
                look = CGPoint(x: (hand.midX * 2 - 1) * 0.9, y: (hand.midY * 2 - 1) * 0.7)
            }
        }
        // A gesture counts once it is held for about half a second, then rests for 3 seconds.
        guard let gesture = sighting.gesture else { gestureStreak = 0; return }
        if gesture == gestureCandidate { gestureStreak += 1 } else { gestureCandidate = gesture; gestureStreak = 1 }
        guard gestureStreak == 3, Date().timeIntervalSince(lastGestureAt) > 3 else { return }
        lastGestureAt = Date()
        perform(gesture, fingertip: sighting.fingertip)
    }

    private func perform(_ gesture: String, fingertip: CGPoint?) {
        touched()
        link.event("gesture", gesture)
        note("gesture: \(gesture)")
        switch gesture {
        case "thumbs_up":
            react(.happy, seconds: 1.5)
            flashPhotoEyes()
            camera.capturePhoto(id: "thumbs-\(Int(Date().timeIntervalSince1970))")
        case "open_palm":
            watchPaused.toggle()
            link.event(watchPaused ? "watch_pause" : "watch_resume")
            haptics.play(.attention)
            showCaption(watchPaused ? "Paused watching. Show your palm again to resume." : "Watching again.", quiet: true)
        case "point":
            haptics.play(.tap)
            if mode == .inspect, let tip = fingertip { point(at: tip) }
            else { showCaption("This one?", quiet: true) }
        default:
            break
        }
    }

    // MARK: Text

    private func textSeen(_ lines: [String]) {
        guard lines != seenText else { return }
        withAnimation(.easeOut(duration: 0.2)) { seenText = lines }
        if !lines.isEmpty, link.status.isConnected { link.send(["type": "text_seen", "lines": lines]) }
    }

    // MARK: Photos when the Mac is off

    /// Photos runs this on a background thread, so it must not belong to the main thread.
    private nonisolated static func addPhoto(_ jpeg: Data) -> @Sendable () -> Void {
        { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpeg, options: nil) }
    }

    /// Fail soft: with no brain connected, photos go to the phone's Photos library instead.
    func savePhotoLocally(_ jpeg: Data) {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                showCaption("I need permission to save photos. You can allow it in the Settings app.", quiet: true)
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges(Self.addPhoto(jpeg))
                showCaption("Photo saved to your library.", quiet: true)
            } catch {
                showCaption("I couldn't save that photo.", quiet: true)
            }
        }
    }
}
