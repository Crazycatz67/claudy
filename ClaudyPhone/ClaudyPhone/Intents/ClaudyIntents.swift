// ClaudyIntents.swift: actions for Siri, Shortcuts and the Action button: talk to Claudy, wake,
// sleep, take a photo, and set the task. Each one opens the app, because the face is the app.
import AppIntents

/// Lets intents reach the running app.
@MainActor
enum IntentBridge {
    static weak var state: AppState?
    static var pending: (@MainActor (AppState) -> Void)?

    /// Runs now if the app is ready, otherwise as soon as it starts.
    static func run(_ action: @escaping @MainActor (AppState) -> Void) {
        if let state { action(state) } else { pending = action }
    }

    static func attach(_ state: AppState) {
        self.state = state
        pending?(state)
        pending = nil
    }
}

struct TalkToClaudyIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Claudy"
    static let description = IntentDescription("Opens Claudy listening. Speak, then tap the face to send.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentBridge.run { $0.startTalking(fromButton: true) }
        return .result()
    }
}

struct WakeClaudyIntent: AppIntent {
    static let title: LocalizedStringResource = "Wake Claudy"
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentBridge.run { $0.wake(because: "Shortcuts") }
        return .result()
    }
}

struct SleepClaudyIntent: AppIntent {
    static let title: LocalizedStringResource = "Claudy sleep"
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentBridge.run { $0.sleep(because: "Shortcuts") }
        return .result()
    }
}

struct ClaudyPhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Claudy take a photo"
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentBridge.run { $0.takePhotoForMac() }
        return .result()
    }
}

struct SetClaudyTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Claudy's task"
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Task", description: "What you're doing, e.g. building a PC")
    var task: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let text = task
        IntentBridge.run { $0.setTask(text) }
        return .result()
    }
}

/// Ready-made phrases so these show up in Shortcuts and Siri without any setup.
struct ClaudyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TalkToClaudyIntent(), phrases: ["Talk to \(.applicationName)"],
                    shortTitle: "Talk", systemImageName: "mic")
        AppShortcut(intent: WakeClaudyIntent(), phrases: ["Wake \(.applicationName)"],
                    shortTitle: "Wake", systemImageName: "sun.max")
        AppShortcut(intent: SleepClaudyIntent(), phrases: ["\(.applicationName) sleep"],
                    shortTitle: "Sleep", systemImageName: "moon")
        AppShortcut(intent: ClaudyPhotoIntent(), phrases: ["\(.applicationName) take a photo"],
                    shortTitle: "Photo", systemImageName: "camera")
    }
}
