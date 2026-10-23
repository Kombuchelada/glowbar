import AppKit
import SwiftUI

@main
struct GlowbarApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // A hidden placeholder: with Settings as the only scene, SwiftUI opens it at launch.
        // The real menu bar item is the NSStatusItem in StatusMenu.
        MenuBarExtra("Glowbar", isInserted: .constant(false)) { EmptyView() }
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
        let menu = NSMenu()
        let panel = PanelHostingView(rootView: LightingPanel(model: model) { [weak menu] in menu?.cancelTracking() })
        panel.frame.size = panel.fittingSize
        let panelItem = NSMenuItem()
        panelItem.view = panel
        menu.addItem(panelItem)
        item.menu = menu
        updateIcon()
    }

    private func updateIcon() {
        withObservationTracking {
            let symbol = model.isConnected ? "light.strip.2.fill" : "light.strip.2"
            item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Glowbar")
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
    }
}

/// The menu window focuses the hex field when it opens, so typing would replace the color.
/// Make the panel itself the window's initial focus instead; the field still focuses when clicked.
private final class PanelHostingView: NSHostingView<LightingPanel> {
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.initialFirstResponder = self
    }
}
