// CameraPreview.swift: the live picture from the camera, shown full screen in Inspect mode.
// The whole picture is shown (no cropping), so a tap maps exactly onto what the Mac sees.
import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        /// Keep the picture upright when the screen rotates.
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let connection = previewLayer.connection,
                  let orientation = window?.windowScene?.effectiveGeometry.interfaceOrientation else { return }
            let angle: CGFloat = switch orientation {
            case .landscapeRight: 0
            case .landscapeLeft: 180
            case .portraitUpsideDown: 270
            default: 90
            }
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
    }
}

extension CGSize {
    /// The rectangle a camera picture fills inside this size without cropping
    /// (tall in portrait, wide in landscape; `long` = long side / short side of the picture).
    func cameraPictureRect(aspect long: CGFloat = 16.0 / 9) -> CGRect {
        let aspect: CGFloat = height > width ? 1 / long : long
        var w = width, h = width / aspect
        if h > height { h = height; w = height * aspect }
        return CGRect(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
    }
}
