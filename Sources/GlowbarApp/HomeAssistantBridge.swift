import GlowbarKit
import AppKit
import Observation
import Security
import SystemConfiguration

/// Publishes the light bar to Home Assistant over MQTT and applies commands from it.
///
/// Laptops come and go, so nothing here is an error: an unreachable broker is retried quietly,
/// sleep announces the Mac as offline, and an unplugged monitor marks the light unavailable
/// while commands still update the saved settings for the next time it's connected.
@MainActor
@Observable
final class HomeAssistantBridge {
    struct Configuration: Codable, Equatable {
        var enabled = false
        var host = ""
        var port = 1883
        var useTLS = false
        var username = ""
        var discoveryPrefix = "homeassistant"
    }

    enum Status: Equatable {
        case off
        case connecting
        case connected
        case retrying(String)
    }

    private(set) var configuration: Configuration
    private(set) var status: Status = .off
    /// Loaded from the keychain in `start()`.
    private(set) var password = ""

    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var client: MQTTClient?
    @ObservationIgnored private var device: HomeAssistantDevice
    @ObservationIgnored private var isAsleep = false

    @ObservationIgnored private static let configurationKey = "homeAssistant"
    @ObservationIgnored private static let deviceIDKey = "homeAssistantDeviceID"

    init() {
        let configuration = UserDefaults.standard.data(forKey: Self.configurationKey)
            .flatMap { try? JSONDecoder().decode(Configuration.self, from: $0) } ?? Configuration()
        self.configuration = configuration
        device = Self.makeDevice(prefix: configuration.discoveryPrefix)

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleep() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }
    }

    func start() {
        // Only touch the keychain if a login was set up.
        guard !configuration.username.isEmpty else { return reconnect() }
        Task {
            // Reading can wait on a keychain access prompt (after every update of an ad-hoc
            // signed app); keep the menu bar panel responsive meanwhile.
            password = await Task.detached { BrokerPassword.read() ?? "" }.value
            reconnect()
        }
    }

    func update(_ configuration: Configuration, password: String) {
        if password != self.password { BrokerPassword.write(password) }
        self.password = password
        self.configuration = configuration
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: Self.configurationKey)
        }
        device = Self.makeDevice(prefix: configuration.discoveryPrefix)
        reconnect()
    }

    // MARK: - Publishing

    func publishState() {
        guard let model else { return }
        client?.publish(device.stateMessage(model.settings))
    }

    func publishMonitorAvailability() {
        guard let model else { return }
        client?.publish(device.monitorAvailability(connected: model.isConnected))
    }

    /// Everything Home Assistant needs after it (or we) (re)connect: discovery, availability, state.
    private func announce() {
        guard let client else { return }
        client.subscribe(device.commandTopics)
        device.discoveryMessages().forEach(client.publish)
        client.publish(device.macAvailability(online: true))
        publishMonitorAvailability()
        publishState()
    }

    private func handle(_ message: MQTTMessage) {
        if message.topic == device.homeAssistantStatusTopic {
            if String(decoding: message.payload, as: UTF8.self) == HomeAssistantDevice.onlinePayload { announce() }
            return
        }
        guard let model,
              let settings = device.settings(applying: message, to: model.settings, lastLitEffect: model.lastLitEffect)
        else { return }
        model.settings = settings
        // Echo right away, even if nothing changed, so Home Assistant's UI settles.
        publishState()
    }

    // MARK: - Connection

    private func reconnect() {
        client?.stop(farewell: device.macAvailability(online: false))
        client = nil
        let c = configuration
        guard c.enabled, !c.host.trimmingCharacters(in: .whitespaces).isEmpty, !isAsleep else {
            status = .off
            return
        }
        let client = MQTTClient(configuration: .init(
            host: c.host.trimmingCharacters(in: .whitespaces),
            port: UInt16(clamping: c.port),
            useTLS: c.useTLS,
            username: c.username,
            password: password,
            clientID: "glowbar-\(device.id)",
            will: device.will
        ))
        client.onStateChange = { [weak self] state in self?.clientStateChanged(state) }
        client.onConnect = { [weak self] in self?.announce() }
        client.onMessage = { [weak self] message in self?.handle(message) }
        self.client = client
        client.start()
    }

    private func clientStateChanged(_ state: MQTTClient.State) {
        switch state {
        case .stopped: status = .off
        case .connecting: if case .retrying = status {} else { status = .connecting }
        case .connected: status = .connected
        case let .retrying(reason): status = .retrying(reason)
        }
    }

    /// Say goodbye before sleeping so Home Assistant marks the light unavailable right away.
    private func sleep() {
        isAsleep = true
        client?.stop(farewell: device.macAvailability(online: false))
    }

    private func wake() {
        isAsleep = false
        if let client { client.start() } else { reconnect() }
    }

    // MARK: - Identity

    private static func makeDevice(prefix: String) -> HomeAssistantDevice {
        let id: String
        if let saved = UserDefaults.standard.string(forKey: deviceIDKey) {
            id = saved
        } else {
            id = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
            UserDefaults.standard.set(id, forKey: deviceIDKey)
        }
        let computer = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
        let trimmedPrefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return HomeAssistantDevice(
            id: id,
            name: "Glowbar on \(computer)",
            discoveryPrefix: trimmedPrefix.isEmpty ? "homeassistant" : trimmedPrefix,
            softwareVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
    }
}

/// The broker password, kept in the login keychain.
private enum BrokerPassword {
    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "io.github.kombuchelada.glowbar.mqtt",
        kSecAttrAccount as String: "broker",
    ] }

    static func read() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(_ password: String) {
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrLabel as String] = "Glowbar MQTT broker"
        SecItemAdd(item as CFDictionary, nil)
    }
}
