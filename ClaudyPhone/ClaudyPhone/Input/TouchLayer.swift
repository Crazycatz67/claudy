// TouchLayer.swift: an invisible layer behind the widgets that turns finger movements into
// Claudy gestures: tap, quick swipes, petting (stroking back and forth) and a two-finger hold.
import SwiftUI
import UIKit

enum SwipeDirection { case up, down, left, right }

struct TouchLayer: UIViewRepresentable {
    var onTap: @MainActor (CGPoint) -> Void            // where you tapped, in points
    var onSwipe: @MainActor (SwipeDirection) -> Void
    var onPet: @MainActor () -> Void
    var onTwoFingerHold: @MainActor () -> Void
    var onPinch: @MainActor (CGFloat) -> Void = { _ in } // zoom change since the last call
    var onHold: @MainActor (Bool) -> Void = { _ in }     // one finger held still: true = start, false = let go

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let c = context.coordinator
        let tap = UITapGestureRecognizer(target: c, action: #selector(Coordinator.tap(_:)))
        let pan = UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let hold = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.hold(_:)))
        hold.numberOfTouchesRequired = 2
        hold.minimumPressDuration = 0.6
        let pinch = UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:)))
        let talk = UILongPressGestureRecognizer(target: c, action: #selector(Coordinator.talk(_:)))
        talk.minimumPressDuration = 0.35
        talk.allowableMovement = 20      // moving more than this is petting, not holding
        for recognizer in [tap, pan, hold, pinch, talk] as [UIGestureRecognizer] {
            recognizer.delegate = c
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TouchLayer
        private var startTime = Date()
        private var last = CGPoint.zero
        private var travel: CGFloat = 0
        private var signX: CGFloat = 0
        private var signY: CGFloat = 0
        private var strokeX: CGFloat = 0
        private var strokeY: CGFloat = 0
        private var turns = 0
        private var reportedTurns = 0
        private var petting = false

        init(_ parent: TouchLayer) { self.parent = parent }

        @objc func tap(_ g: UITapGestureRecognizer) { parent.onTap(g.location(in: g.view)) }

        @objc func talk(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began: parent.onHold(true)
            case .ended, .cancelled, .failed: parent.onHold(false)
            default: break
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard g.state == .changed else { return }
            parent.onPinch(g.scale)
            g.scale = 1
        }

        @objc func hold(_ g: UILongPressGestureRecognizer) {
            if g.state == .began { parent.onTwoFingerHold() }
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let point = g.location(in: g.view)
            switch g.state {
            case .began:
                startTime = Date()
                last = point
                travel = 0
                signX = 0
                signY = 0
                strokeX = 0
                strokeY = 0
                turns = 0
                reportedTurns = 0
                petting = false
            case .changed:
                let dx = point.x - last.x, dy = point.y - last.y
                let step = hypot(dx, dy)
                guard step > 3 else { return }
                travel += step
                last = point
                // Petting = the finger keeps changing direction. Count a turn only after a real
                // stroke (25+ points), so a wobbly swipe is not mistaken for petting.
                if abs(dx) > abs(dy) {
                    let s: CGFloat = dx > 0 ? 1 : -1
                    if signX != 0 && s != signX {
                        if strokeX >= 25 { turns += 1 }
                        strokeX = 0
                    }
                    signX = s
                    strokeX += abs(dx)
                } else {
                    let s: CGFloat = dy > 0 ? 1 : -1
                    if signY != 0 && s != signY {
                        if strokeY >= 25 { turns += 1 }
                        strokeY = 0
                    }
                    signY = s
                    strokeY += abs(dy)
                }
                if turns >= 2, travel > 120, turns != reportedTurns {
                    reportedTurns = turns
                    petting = true
                    parent.onPet()
                }
            case .ended:
                guard !petting else { return }
                let t = g.translation(in: g.view)
                let v = g.velocity(in: g.view)
                let quick = Date().timeIntervalSince(startTime) < 0.8
                let far = max(abs(t.x), abs(t.y)) > 60 || max(abs(v.x), abs(v.y)) > 600
                guard quick, far else { return }
                if abs(t.x) > abs(t.y) {
                    parent.onSwipe(t.x < 0 ? .left : .right)
                } else {
                    parent.onSwipe(t.y > 0 ? .down : .up)
                }
            default:
                break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
