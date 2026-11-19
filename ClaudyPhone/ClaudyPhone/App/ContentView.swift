// ContentView.swift: placeholder screen for Phase 0. Phase B1 replaces it with Claudy's face.
import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("Hello, I'm Claudy")
                .font(.title)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    ContentView()
}
