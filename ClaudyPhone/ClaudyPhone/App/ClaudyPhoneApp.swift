// ClaudyPhoneApp.swift: the app's entry point. Opens straight to Claudy's face.
import SwiftUI

@main
struct ClaudyPhoneApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            FaceView()
                .environment(state)
                .preferredColorScheme(.dark)
        }
    }
}
