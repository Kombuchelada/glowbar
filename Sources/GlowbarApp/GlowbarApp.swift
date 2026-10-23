import SwiftUI

@main
struct GlowbarApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            LightingPanel(model: model)
        } label: {
            Image(systemName: model.isConnected ? "light.strip.2.fill" : "light.strip.2")
        }
        .menuBarExtraStyle(.window)
    }
}
