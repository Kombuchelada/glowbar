import AppKit
import SwiftUI

@main
struct GlowbarApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Settings {
            HomeAssistantSettings(bridge: delegate.model.homeAssistant, monitorConnected: delegate.model.isConnected)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenu(model: model)
    }
}

/// The menu bar item. Its menu is a real NSMenu, so macOS draws the background, corners and
/// animations exactly like its own menus; the panel is hosted inside a single menu item.
@MainActor
final class StatusMenu {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(model: AppModel) {
        self.model = model
        let panel = NSHostingView(rootView: LightingPanel(model: model))
        panel.frame.size = panel.fittingSize
        let panelItem = NSMenuItem()
        panelItem.view = panel
        let menu = NSMenu()
        menu.addItem(panelItem)
        item.menu = menu
        updateIcon()
    }

    private func updateIcon() {
        withObservationTracking {
            let symbol = model.isConnected ? "light.strip.2.fill" : "light.strip.2"
            item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Glowbar")
        } onChange: {
            Task { @MainActor [weak self] in self?.updateIcon() }
        }
    }
}
