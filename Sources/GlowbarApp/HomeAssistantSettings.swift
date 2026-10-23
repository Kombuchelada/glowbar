import SwiftUI

/// Settings window: MQTT broker details for the Home Assistant connection.
struct HomeAssistantSettings: View {
    let bridge: HomeAssistantBridge
    let monitorConnected: Bool
    @State private var draft = HomeAssistantBridge.Configuration()
    @State private var password = ""

    private var hasChanges: Bool { draft != bridge.configuration || password != bridge.password }

    var body: some View {
        Form {
            Section {
                Toggle("Connect to Home Assistant", isOn: $draft.enabled)
            } footer: {
                Text("Glowbar adds the light bar to Home Assistant through MQTT discovery. In Home Assistant, set up the MQTT integration (for example with the Mosquitto broker add-on), then enter the broker below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("MQTT broker") {
                TextField("Host", text: $draft.host, prompt: Text("homeassistant.local"))
                TextField("Port", value: $draft.port, format: .number.grouping(.never))
                Toggle("Use TLS", isOn: $draft.useTLS)
                TextField("Username", text: $draft.username, prompt: Text("Optional"))
                SecureField("Password", text: $password, prompt: Text("Optional"))
                TextField("Discovery prefix", text: $draft.discoveryPrefix)
            }
            .disabled(!draft.enabled)

            Section {
                HStack(spacing: 8) {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Apply") { bridge.update(draft, password: password) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!hasChanges)
                }
            }
        }
        .formStyle(.grouped)
        // The password arrives from the keychain after launch, so read both when the window opens.
        .onAppear {
            draft = bridge.configuration
            password = bridge.password
        }
        .onChange(of: bridge.password) { _, stored in password = stored }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var dotColor: Color {
        switch bridge.status {
        case .off: .secondary
        case .connecting: .yellow
        case .connected: .green
        case .retrying: .orange
        }
    }

    private var statusText: String {
        switch bridge.status {
        case .off:
            "Not connected."
        case .connecting:
            "Connecting to \(bridge.configuration.host)…"
        case .connected where monitorConnected:
            "Connected. The light bar is available in Home Assistant."
        case .connected:
            "Connected. Home Assistant shows the light as unavailable until the monitor is plugged in."
        case let .retrying(reason):
            "\(reason). Retrying in the background."
        }
    }
}
