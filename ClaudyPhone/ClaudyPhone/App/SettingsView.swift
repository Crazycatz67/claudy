// SettingsView.swift: the settings sheet (open with a two-finger hold): eye colour, voice,
// motion sensitivity, Mac address, and a debug menu that triggers every expression and haptic.
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage("eyeColor") private var eyeHex = Color.defaultEyeHex
    @AppStorage("motionSensitivity") private var sensitivity = 0.5
    @AppStorage("macAddress") private var macAddress = ""
    @AppStorage("followMe") private var followMe = false
    @AppStorage("shareWithMac") private var shareWithMac = false

    private let presets = [Color.defaultEyeHex, "#FFFFFF", "#8AB4FF", "#B98CFF", "#FF8AD8", "#9CFF8A", "#FFD166"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Eyes") {
                    ColorPicker("Eye colour", selection: Binding(
                        get: { Color(hex: eyeHex) ?? .cyan },
                        set: { eyeHex = $0.hex }), supportsOpacity: false)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(presets, id: \.self) { hex in
                                Button { eyeHex = hex } label: {
                                    Circle()
                                        .fill(Color(hex: hex) ?? .white)
                                        .frame(width: 34, height: 34)
                                        .overlay(Circle().stroke(.primary, lineWidth: eyeHex == hex ? 3 : 0))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Colour \(hex)")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Toggle("Follow me", isOn: $followMe)
                    Toggle("Share camera with my Mac", isOn: $shareWithMac)
                    Button(state.mode == .inspect ? "Back to Buddy mode" : "Inspect mode (back camera)") {
                        state.setMode(state.mode == .inspect ? .buddy : .inspect)
                        dismiss()
                    }
                } header: {
                    Text("Camera")
                } footer: {
                    Text("Follow me: the eyes look at you; your face is found on this phone only. Share: about 3 small pictures a second go to your own Mac over Wi-Fi, never anywhere else, and the eyes flash red whenever one goes to Claude. Inspect (or swipe up): the back camera looks at your work. The camera is always off while Claudy sleeps.")
                }

                Section("Voice") {
                    LabeledContent("Voice", value: "Arrives in phase B3")
                }

                Section {
                    Slider(value: $sensitivity, in: 0...1)
                } header: {
                    Text("Motion sensitivity")
                } footer: {
                    Text("Higher means a gentler shake cancels and a smaller lift wakes Claudy.")
                }

                Section {
                    TextField("Mac address, e.g. 192.168.1.20", text: $macAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("Status", value: linkReadout)
                } header: {
                    Text("Mac brain")
                } footer: {
                    Text("Leave the address empty to find the Mac by itself. Type it only if that fails (some campus Wi-Fi blocks finding devices).")
                }

                Section("Debug: expressions") {
                    ForEach(Expression.allCases) { e in
                        Button(e.label) { state.setExpression(e) }
                    }
                }

                Section("Debug: haptics") {
                    ForEach(HapticPattern.allCases) { p in
                        Button { state.haptics.play(p) } label: {
                            LabeledContent(p.rawValue.capitalized, value: p.meaning)
                        }
                    }
                }

                Section("Debug: actions") {
                    Button("Shake (cancel)") { state.shake() }
                    Button("Sleep") { state.sleep(because: "debug") }
                    Button("Wake") { state.wake(because: "debug") }
                    Button("Start a 10-second timer") { state.startTimer(minutes: 10.0 / 60) }
                    LabeledContent("Last event", value: state.lastEvent)
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        LabeledContent("Motion", value: state.motion.readout)
                    }
                    LabeledContent("Follow me", value: followReadout)
                    TimelineView(.periodic(from: .now, by: 2)) { _ in
                        LabeledContent("Phone warmth", value: Self.warmth())
                    }
                }
            }
            .navigationTitle("Claudy settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private var linkReadout: String {
        switch state.link.status {
        case .off: "off"
        case .searching: "looking for the Mac…"
        case .connecting: "connecting…"
        case .connected(let host): "connected to \(host)"
        case .offline: "offline, retrying"
        }
    }

    private var followReadout: String {
        guard state.cameraOn, state.cameraSide == .front else { return "camera off" }
        return "\(state.seesFace ? "sees you" : "looking…"), \(state.faceChecksPerSecond) checks/s"
    }

    private static func warmth() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "normal"
        case .fair: "a bit warm"
        case .serious: "hot"
        case .critical: "very hot"
        @unknown default: "unknown"
        }
    }
}

extension Color {
    static let defaultEyeHex = "#7CF7E4"

    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
