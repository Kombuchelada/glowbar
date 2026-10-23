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
            save()
            scheduleApply()
        }
    }

    private(set) var status: Status = .searching
    private(set) var controllerName: String?
    private(set) var firmware: String?

    @ObservationIgnored private let browser = LightingControllerBrowser()
    @ObservationIgnored private var pendingApply: Task<Void, Never>?
    @ObservationIgnored private static let defaultsKey = "lightingSettings"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(LightingSettings.self, from: data) {
            settings = saved
        } else {
            settings = LightingSettings()
        }
        browser.onChange = { [weak self] in self?.controllersChanged() }
        browser.start()
    }

    var isConnected: Bool { controllerName != nil }

    private func controllersChanged() {
        guard let controller = browser.controllers.first else {
            controllerName = nil
            firmware = nil
            status = .searching
            return
        }
        controllerName = Self.monitorDisplayName ?? controller.productName
        status = .connected(controllerName!)
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
        }
    }

    func applyNow() {
        // Without a monitor, settings are just saved; the header already says what to connect.
        guard let controller = browser.controllers.first else { return }
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
