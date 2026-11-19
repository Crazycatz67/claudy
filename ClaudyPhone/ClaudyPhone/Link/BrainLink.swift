// BrainLink.swift: the connection to the Mac brain. Finds it on Wi-Fi with Bonjour (_claudy._tcp)
// or uses the address typed in settings, opens a WebSocket to ws://<mac>:8765/ws, sends and receives
// the messages in docs/PROTOCOL.md, and reconnects by itself. Local network only.
import Foundation
import Network
import UIKit

@MainActor
@Observable
final class BrainLink {
    enum Status: Equatable {
        case off, searching, connecting, connected(String), offline
        var isConnected: Bool { if case .connected = self { true } else { false } }
    }

    private(set) var status: Status = .off {
        didSet { if status != oldValue { onStatus(status) } }
    }
    /// Every text message from the Mac, already decoded from JSON. Set by AppState.
    @ObservationIgnored var onMessage: (String, [String: Any]) -> Void = { _, _ in }
    @ObservationIgnored var onStatus: (Status) -> Void = { _ in }
    @ObservationIgnored var helloMode: () -> String = { "buddy" }

    @ObservationIgnored private var manualAddress = ""
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var resolver: NWConnection?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var lastPing = Date()
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var wanted = false

    static let port = 8765
    static let serviceType = "_claudy._tcp"

    // MARK: Start and stop

    func start(manualAddress: String) {
        self.manualAddress = manualAddress.trimmingCharacters(in: .whitespaces)
        guard !wanted else { return }
        wanted = true
        connect()
    }

    func stop() {
        wanted = false
        teardown()
        status = .off
    }

    /// Called when the address in settings changes: reconnect with the new one.
    func restart(manualAddress: String) {
        let address = manualAddress.trimmingCharacters(in: .whitespaces)
        guard address != self.manualAddress else { return }
        self.manualAddress = address
        guard wanted else { return }
        teardown()
        connect()
    }

    private func connect() {
        guard wanted else { return }
        if manualAddress.isEmpty {
            browse()
        } else {
            open(host: manualAddress, port: Self.port)
        }
    }

    private func teardown() {
        browser?.cancel(); browser = nil
        resolver?.cancel(); resolver = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        watchdog?.cancel(); watchdog = nil
        retry?.cancel(); retry = nil
    }

    private func lost() {
        guard wanted else { return }
        teardown()
        status = .offline
        retry = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            connect()
        }
    }

    // MARK: Finding the Mac (Bonjour)

    private func browse() {
        status = .searching
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self, let first = results.first, self.resolver == nil else { return }
                self.resolve(first.endpoint)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed = state { self?.lost() }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        // Nothing found for a while: show offline (the search keeps going).
        retry = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, self.status == .searching else { return }
            self.status = .offline
        }
    }

    /// Bonjour gives a service name; connect briefly over TCP to learn its IPv4 address.
    private func resolve(_ endpoint: NWEndpoint) {
        status = .connecting
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    if case let .hostPort(host, port)? = connection.currentPath?.remoteEndpoint {
                        let address = "\(host)".components(separatedBy: "%").first ?? "\(host)"
                        connection.cancel()
                        self.resolver = nil
                        self.browser?.cancel()
                        self.browser = nil
                        self.open(host: address, port: Int(port.rawValue))
                    }
                case .failed, .waiting:
                    connection.cancel()
                    self.resolver = nil
                    self.lost()
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        resolver = connection
    }

    // MARK: WebSocket

    private func open(host: String, port: Int) {
        guard let url = URL(string: "ws://\(host):\(port)/ws") else { status = .offline; return }
        status = .connecting
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        lastPing = Date()
        send(["type": "hello", "device": UIDevice.current.name,
              "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
              "mode": helloMode()])
        Task { await receiveLoop(task, host: host) }
        watchdog = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Date().timeIntervalSince(self.lastPing) > 15 { self.lost(); return }   // PROTOCOL: 15 s
            }
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask, host: String) async {
        while socket === task {
            do {
                let message = try await task.receive()
                guard case let .string(text) = message,
                      let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String else { continue }   // unknown: ignore
                lastPing = Date()
                if !status.isConnected { status = .connected(host) }
                if type == "ping" {
                    send(["type": "pong", "t": json["t"] ?? 0])
                } else {
                    onMessage(type, json)
                }
            } catch {
                if socket === task { lost() }
                return
            }
        }
    }

    // MARK: Sending

    func send(_ json: [String: Any]) {
        guard let socket, JSONSerialization.isValidJSONObject(json),
              let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { _ in }
    }

    /// A JSON description followed by the JPEG itself, as PROTOCOL.md says.
    func send(_ json: [String: Any], jpeg: Data) {
        guard let socket, status.isConnected else { return }
        send(json)
        socket.send(.data(jpeg)) { _ in }
    }

    func event(_ name: String, _ data: Any? = nil) {
        var json: [String: Any] = ["type": "event", "name": name]
        if let data { json["data"] = data }
        send(json)
    }
}
