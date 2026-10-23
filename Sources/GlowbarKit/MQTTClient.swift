import Foundation
import Network

/// A small MQTT 3.1.1 client that keeps one broker connection alive.
///
/// Built for a laptop: it never gives up and never treats an unreachable broker as an error
/// worth surfacing loudly. It retries with backoff (immediately when the network changes)
/// until `stop()` is called.
@MainActor
public final class MQTTClient {
    public struct Configuration: Equatable, Sendable {
        public var host: String
        public var port: UInt16
        public var useTLS: Bool
        public var username: String?
        public var password: String?
        public var clientID: String
        /// Published by the broker if this client disappears without saying goodbye.
        public var will: MQTTMessage?
        public var keepAlive: UInt16

        public init(
            host: String, port: UInt16, useTLS: Bool = false, username: String? = nil, password: String? = nil,
            clientID: String, will: MQTTMessage? = nil, keepAlive: UInt16 = 30
        ) {
            self.host = host
            self.port = port
            self.useTLS = useTLS
            self.username = username
            self.password = password
            self.clientID = clientID
            self.will = will
            self.keepAlive = keepAlive
        }
    }

    public enum State: Equatable, Sendable {
        case stopped
        case connecting
        case connected
        /// Waiting to retry after `reason`.
        case retrying(reason: String)
    }

    public private(set) var state: State = .stopped {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    public var onStateChange: ((State) -> Void)?
    /// Called after each successful (re)connection; subscribe and publish initial state here.
    public var onConnect: (() -> Void)?
    public var onMessage: ((MQTTMessage) -> Void)?

    private let configuration: Configuration
    private var connection: NWConnection?
    private var buffer: [UInt8] = []
    private var retryDelay: Duration = .seconds(2)
    private var retryTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var awaitingPong = false
    private var nextPacketID: UInt16 = 1
    private var pathMonitor: NWPathMonitor?
    private var lastPathStatus: NWPath.Status?

    private static let maxRetryDelay: Duration = .seconds(60)
    private static let connectTimeout: Duration = .seconds(10)

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public func start() {
        guard state == .stopped else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            DispatchQueue.main.async { self?.pathChanged(status) }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
        lastPathStatus = nil
        connect()
    }

    /// Closes the connection. Sends `farewell` first if connected (best effort), then disconnects
    /// without a DISCONNECT packet so the broker also publishes the last will.
    public func stop(farewell: MQTTMessage? = nil) {
        pathMonitor?.cancel()
        pathMonitor = nil
        retryTask?.cancel()
        if let connection, state == .connected, let farewell {
            connection.send(content: Data(MQTTPacket.publish(farewell)), completion: .contentProcessed { _ in
                connection.cancel()
            })
        } else {
            connection?.cancel()
        }
        tearDown()
        state = .stopped
    }

    public func publish(_ message: MQTTMessage) {
        guard state == .connected else { return }
        send(MQTTPacket.publish(message))
    }

    public func subscribe(_ topics: [String]) {
        guard state == .connected, !topics.isEmpty else { return }
        send(MQTTPacket.subscribe(topics, packetID: nextPacketID))
        nextPacketID = nextPacketID == .max ? 1 : nextPacketID + 1
    }

    // MARK: - Connection lifecycle

    private func connect() {
        retryTask?.cancel()
        tearDown()
        state = .connecting

        let parameters: NWParameters = configuration.useTLS ? .tls : .tcp
        let port = NWEndpoint.Port(rawValue: configuration.port) ?? 1883
        let connection = NWConnection(host: NWEndpoint.Host(configuration.host), port: port, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] newState in
            DispatchQueue.main.async { self?.connectionStateChanged(newState, for: connection) }
        }
        connection.start(queue: .main)

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.connectTimeout)
            guard !Task.isCancelled, let self, self.state == .connecting else { return }
            self.retry("Timed out connecting to \(self.configuration.host)")
        }
    }

    private func connectionStateChanged(_ newState: NWConnection.State, for connection: NWConnection) {
        guard connection === self.connection else { return }
        switch newState {
        case .ready:
            let c = configuration
            send(MQTTPacket.connect(
                clientID: c.clientID, username: c.username, password: c.password, will: c.will, keepAlive: c.keepAlive
            ))
            receive(on: connection)
        case let .waiting(error), let .failed(error):
            retry(Self.describe(error))
        case .cancelled:
            if state == .connected || state == .connecting { retry("Connection closed") }
        default:
            break
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            DispatchQueue.main.async {
                guard let self, connection === self.connection else { return }
                if let data { self.received(data) }
                if let error {
                    self.retry(Self.describe(error))
                } else if isComplete {
                    self.retry("The broker closed the connection")
                } else if connection === self.connection {
                    self.receive(on: connection)
                }
            }
        }
    }

    private func received(_ data: Data) {
        buffer += data
        let packets: [MQTTPacket]
        do {
            packets = try MQTTPacket.decode(&buffer)
        } catch {
            retry("The broker sent an invalid packet")
            return
        }
        for packet in packets {
            switch packet {
            case let .connAck(code):
                guard code == 0 else {
                    retry(Self.describe(connAck: code))
                    return
                }
                timeoutTask?.cancel()
                retryDelay = .seconds(2)
                state = .connected
                startKeepAlive()
                onConnect?()
            case let .publish(message, packetID):
                if let packetID { send(MQTTPacket.pubAck(packetID: packetID)) }
                onMessage?(message)
            case .pingResp:
                awaitingPong = false
            case .subAck, .other:
                break
            }
        }
    }

    private func startKeepAlive() {
        let interval = Duration.seconds(Int(configuration.keepAlive) * 2 / 3)
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                if self.awaitingPong {
                    self.retry("The broker stopped responding")
                    return
                }
                self.awaitingPong = true
                self.send(MQTTPacket.pingReq)
            }
        }
    }

    private func send(_ bytes: [UInt8]) {
        connection?.send(content: Data(bytes), completion: .contentProcessed { _ in })
    }

    /// Drops the current connection and tries again later, backing off up to a minute.
    private func retry(_ reason: String) {
        guard state != .stopped else { return }
        connection?.cancel()
        tearDown()
        state = .retrying(reason: reason)
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, Self.maxRetryDelay)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    private func tearDown() {
        connection?.stateUpdateHandler = nil
        connection = nil
        buffer = []
        awaitingPong = false
        timeoutTask?.cancel()
        keepAliveTask?.cancel()
    }

    /// A laptop joining a network is the best moment to retry; don't wait out the backoff.
    private func pathChanged(_ status: NWPath.Status) {
        defer { lastPathStatus = status }
        guard status == .satisfied, lastPathStatus != nil, lastPathStatus != status else { return }
        if case .retrying = state {
            retryDelay = .seconds(2)
            connect()
        }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case let .posix(code) where code == .ECONNREFUSED: "The broker refused the connection"
        case let .posix(code) where code == .ENETUNREACH || code == .EHOSTUNREACH: "Broker not reachable from this network"
        case let .dns(code): "Can't find the broker's address (DNS error \(code))"
        case let .tls(status): "TLS error \(status)"
        default: error.localizedDescription
        }
    }

    private static func describe(connAck code: UInt8) -> String {
        switch code {
        case 1: "The broker doesn't support MQTT 3.1.1"
        case 2: "The broker rejected the client ID"
        case 3: "The broker is unavailable"
        case 4, 5: "The broker rejected the username or password"
        default: "The broker refused the connection (code \(code))"
        }
    }
}
