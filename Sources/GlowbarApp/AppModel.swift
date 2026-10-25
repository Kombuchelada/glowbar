import GlowbarKit
import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case searching
        case connected(String)
        case applied(String)
        case failed(String)
    }

    var settings: LightingSettings {
        didSet {
            guard settings != oldValue else { return }
            if settings.effect != .off { lastLitEffect = settings.effect }
            save()
            scheduleApply()
        }
    }

    private(set) var status: Status = .searching
    private(set) var controllerName: String?
    private(set) var firmware: String?

    /// The effect to restore when something turns the light back on (Home Assistant's "on").
    @ObservationIgnored private(set) var lastLitEffect: Effect {
        didSet { UserDefaults.standard.set(lastLitEffect.rawValue, forKey: Self.lastLitKey) }
    }

    @ObservationIgnored let homeAssistant = HomeAssistantBridge()
    @ObservationIgnored private let browser = LightingControllerBrowser()
    @ObservationIgnored private var pendingApply: Task<Void, Never>?
    /// Settings changed while no monitor was connected; send them when one shows up.
    @ObservationIgnored private var applyOnConnect = false
    @ObservationIgnored private static let defaultsKey = "lightingSettings"
    @ObservationIgnored private static let lastLitKey = "lastLitEffect"

    init() {
        let saved = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(LightingSettings.self, from: $0) }
        let initial = saved ?? LightingSettings()
        lastLitEffect = UserDefaults.standard.string(forKey: Self.lastLitKey).flatMap(Effect.init(rawValue:))
            ?? (initial.effect == .off ? .staticColor : initial.effect)
        settings = initial
        browser.onChange = { [weak self] in self?.controllersChanged() }
        browser.start()
        // Over USB-C the controller can enumerate before the display does; rename once it appears.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshControllerName() }
        }
        homeAssistant.model = self
        homeAssistant.start()
    }

    var isConnected: Bool { controllerName != nil }

    private func controllersChanged() {
        guard let controller = browser.controllers.first else {
            controllerName = nil
            firmware = nil
            status = .searching
            homeAssistant.publishMonitorAvailability()
            return
        }
        controllerName = Self.monitorDisplayName ?? controller.productName
        status = .connected(controllerName!)
        homeAssistant.publishMonitorAvailability()
        if applyOnConnect { applyNow() }
    }

    private func refreshControllerName() {
        guard let controller = browser.controllers.first else { return }
        controllerName = Self.monitorDisplayName ?? controller.productName
    }

    /// The controller's USB name is generic ("ITE Device"); prefer the display's own name.
    private static var monitorDisplayName: String? {
        NSScreen.screens.map(\.localizedName).first { $0.localizedCaseInsensitiveContains("AORUS") }
    }

    /// Debounce so dragging a slider or the color wheel doesn't flood the controller.
    private func scheduleApply() {
        pendingApply?.cancel()
        pendingApply = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.applyNow()
            self?.homeAssistant.publishState()
        }
    }

    func applyNow() {
        // Without a monitor, settings are saved and sent once it's connected again.
        guard let controller = browser.controllers.first else {
            applyOnConnect = true
            return
        }
        applyOnConnect = false
        do {
            try controller.apply(settings)
            firmware = controller.info?.firmwareVersion
            status = .applied(settings.effect.displayName)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
