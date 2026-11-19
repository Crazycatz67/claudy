// MotionSensor.swift: reads the phone's motion (Core Motion) to spot a shake, being put
// face down, and being picked up while asleep. Sensitivity comes from settings.
import CoreMotion
import Foundation

@MainActor
final class MotionSensor {
    var sensitivity: Double = 0.5               // 0 = needs big movements, 1 = very sensitive
    var onShake: @MainActor () -> Void = {}
    var onFaceDown: @MainActor () -> Void = {}
    var onPickUp: @MainActor () -> Void = {}
    private(set) var readout = "motion off"     // shown in the debug menu
    private(set) var isFaceDown = false

    private let manager = CMMotionManager()
    private var shakeTimes: [TimeInterval] = []
    private var lastShake: TimeInterval = 0
    private var faceDownFrames = 0
    private var pickUpReference: CMAcceleration?
    private var armedAt: TimeInterval = 0

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated { self?.handle(motion) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        readout = "motion off"
    }

    /// Called when Claudy falls asleep: remember how the phone is lying, so lifting it can wake it.
    func armPickUp() {
        pickUpReference = manager.deviceMotion?.gravity
        armedAt = ProcessInfo.processInfo.systemUptime
    }

    func disarmPickUp() { pickUpReference = nil }

    private func handle(_ m: CMDeviceMotion) {
        let g = m.gravity, a = m.userAcceleration, now = m.timestamp
        let force = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()   // in g, gravity removed
        readout = String(format: "tilt z %.2f   force %.2f g", g.z, force)

        // Shake: three hard jolts within 0.8 seconds.
        let shakeLimit = 2.0 - sensitivity * 1.0
        if force > shakeLimit, now - (shakeTimes.last ?? 0) > 0.08 { shakeTimes.append(now) }
        shakeTimes.removeAll { now - $0 > 0.8 }
        if shakeTimes.count >= 3, now - lastShake > 1.5 {
            lastShake = now
            shakeTimes.removeAll()
            onShake()
        }

        // Face down: the screen points at the table (gravity along +z) for about a quarter second.
        if g.z > 0.85 {
            faceDownFrames += 1
        } else if g.z < 0.6 {
            faceDownFrames = 0
            isFaceDown = false
        }
        if faceDownFrames == 8 {
            isFaceDown = true
            onFaceDown()
        }

        // Pick-up: while asleep, wake when the phone is tilted a lot or lifted.
        if let ref = pickUpReference, !isFaceDown, now - armedAt > 1.0 {
            let dot = max(-1, min(1, ref.x * g.x + ref.y * g.y + ref.z * g.z))
            let angle = acos(dot) * 180 / .pi
            let angleLimit = 45 - sensitivity * 25
            let liftLimit = 0.45 - sensitivity * 0.25
            if angle > angleLimit || force > liftLimit {
                pickUpReference = nil
                onPickUp()
            }
        }
    }
}
