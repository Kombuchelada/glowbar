// Home Assistant MQTT discovery for the light bar. Pure; no I/O.
// See docs/HOME_ASSISTANT.md.

import Foundation

/// One Mac's light bar as a Home Assistant device: a JSON-schema light plus a speed number.
///
/// Availability uses two retained topics and `availability_mode: all`, so the light shows as
/// unavailable when either the Mac is gone (asleep, off the network, quit) or the monitor's USB
/// cable is unplugged.
public struct HomeAssistantDevice: Sendable {
    /// Stable per-Mac identifier used in topics and unique IDs.
    public let id: String
    public let name: String
    public let discoveryPrefix: String
    public let softwareVersion: String?

    public init(id: String, name: String, discoveryPrefix: String = "homeassistant", softwareVersion: String? = nil) {
        self.id = id
        self.name = name
        self.discoveryPrefix = discoveryPrefix
        self.softwareVersion = softwareVersion
    }

    public static let onlinePayload = "online"
    public static let offlinePayload = "offline"

    var baseTopic: String { "glowbar/\(id)" }
    public var stateTopic: String { "\(baseTopic)/state" }
    public var commandTopic: String { "\(baseTopic)/set" }
    public var speedCommandTopic: String { "\(baseTopic)/speed/set" }
    /// Whether Glowbar on this Mac is connected to the broker.
    public var macAvailabilityTopic: String { "\(baseTopic)/status" }
    /// Whether the monitor's lighting controller is plugged in to this Mac.
    public var monitorAvailabilityTopic: String { "\(baseTopic)/monitor" }
    /// Home Assistant publishes "online" here when it starts.
    public var homeAssistantStatusTopic: String { "\(discoveryPrefix)/status" }

    public var commandTopics: [String] { [commandTopic, speedCommandTopic, homeAssistantStatusTopic] }

    /// Effects offered in Home Assistant's effect list ("Off" is the light's off state instead).
    public static var effects: [Effect] { Effect.allCases.filter { $0 != .off } }

    // MARK: Outgoing messages

    /// The broker publishes this if the Mac drops off without saying goodbye.
    public var will: MQTTMessage { macAvailability(online: false) }

    public func macAvailability(online: Bool) -> MQTTMessage {
        MQTTMessage(topic: macAvailabilityTopic, string: online ? Self.onlinePayload : Self.offlinePayload, retain: true)
    }

    public func monitorAvailability(connected: Bool) -> MQTTMessage {
        MQTTMessage(topic: monitorAvailabilityTopic, string: connected ? Self.onlinePayload : Self.offlinePayload, retain: true)
    }

    public func discoveryMessages() -> [MQTTMessage] {
        let availability: [String: Any] = [
            "availability": [["topic": macAvailabilityTopic], ["topic": monitorAvailabilityTopic]],
            "availability_mode": "all",
        ]
        let light: [String: Any] = [
            "name": NSNull(),  // the entity takes the device's name
            "unique_id": "glowbar_\(id)_light",
            "icon": "mdi:led-strip-variant",
            "schema": "json",
            "state_topic": stateTopic,
            "command_topic": commandTopic,
            "brightness": true,
            "brightness_scale": LightingSettings.brightnessRange.upperBound,
            "supported_color_modes": ["rgb"],
            "effect": true,
            "effect_list": Self.effects.map(\.displayName),
            "flash": false,
            "transition": false,
        ]
        let speed: [String: Any] = [
            "name": "Speed",
            "unique_id": "glowbar_\(id)_speed",
            "icon": "mdi:speedometer",
            "state_topic": stateTopic,
            "value_template": "{{ value_json.speed }}",
            "command_topic": speedCommandTopic,
            "min": LightingSettings.speedRange.lowerBound,
            "max": LightingSettings.speedRange.upperBound,
            "step": 1,
            "mode": "slider",
            "entity_category": "config",
        ]
        return [
            discovery(component: "light", object: "light", config: light.merging(availability) { a, _ in a }),
            discovery(component: "number", object: "speed", config: speed.merging(availability) { a, _ in a }),
        ]
    }

    private func discovery(component: String, object: String, config: [String: Any]) -> MQTTMessage {
        var device: [String: Any] = [
            "identifiers": ["glowbar_\(id)"],
            "name": name,
            "manufacturer": "Glowbar",
            "model": "Monitor light bar",
        ]
        var origin: [String: Any] = ["name": "Glowbar", "support_url": "https://github.com/Kombuchelada/glowbar"]
        if let softwareVersion {
            device["sw_version"] = softwareVersion
            origin["sw_version"] = softwareVersion
        }
        var config = config
        config["device"] = device
        config["origin"] = origin
        return MQTTMessage(
            topic: "\(discoveryPrefix)/\(component)/glowbar_\(id)/\(object)/config",
            payload: Self.json(config),
            retain: true
        )
    }

    public func stateMessage(_ settings: LightingSettings) -> MQTTMessage {
        var state: [String: Any] = ["speed": settings.speed]
        if settings.effect == .off {
            state["state"] = "OFF"
        } else {
            state["state"] = "ON"
            state["effect"] = settings.effect.displayName
            state["brightness"] = settings.brightness
            state["color_mode"] = "rgb"
            state["color"] = ["r": settings.color.red, "g": settings.color.green, "b": settings.color.blue]
        }
        return MQTTMessage(topic: stateTopic, payload: Self.json(state), retain: true)
    }

    static func json(_ object: [String: Any]) -> Data {
        // Every value above is JSON-safe, so this can't fail.
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    // MARK: Incoming commands

    /// The settings a command asks for, or nil if `message` isn't a valid command for this device.
    ///
    /// Turning on without an effect restores `lastLitEffect`. Picking a color while the current
    /// effect ignores color switches to Static, so the color shows up on the bar.
    public func settings(
        applying message: MQTTMessage, to current: LightingSettings, lastLitEffect: Effect
    ) -> LightingSettings? {
        var settings = current
        switch message.topic {
        case speedCommandTopic:
            guard let value = Double(String(decoding: message.payload, as: UTF8.self).trimmingCharacters(in: .whitespaces))
            else { return nil }
            settings.speed = Int(value.rounded()).clamped(to: LightingSettings.speedRange)
            return settings

        case commandTopic:
            guard let command = (try? JSONSerialization.jsonObject(with: message.payload)) as? [String: Any] else {
                return nil
            }
            if (command["state"] as? String)?.uppercased() == "OFF" {
                settings.effect = .off
                return settings
            }
            let requested = (command["effect"] as? String).flatMap { name in
                Self.effects.first { $0.displayName == name || $0.rawValue == name }
            }
            if let requested {
                settings.effect = requested
            } else if settings.effect == .off {
                settings.effect = lastLitEffect == .off ? .staticColor : lastLitEffect
            }
            if let level = (command["brightness"] as? NSNumber)?.doubleValue {
                settings.brightness = Int(level.rounded()).clamped(to: LightingSettings.brightnessRange)
            }
            if let color = command["color"] as? [String: Any],
               let r = Self.channel(color["r"]), let g = Self.channel(color["g"]), let b = Self.channel(color["b"]) {
                settings.color = RGB(red: r, green: g, blue: b)
                if requested == nil, !settings.effect.usesColor { settings.effect = .staticColor }
            }
            return settings

        default:
            return nil
        }
    }

    private static func channel(_ value: Any?) -> UInt8? {
        guard let number = (value as? NSNumber)?.doubleValue else { return nil }
        return UInt8(number.rounded().clamped(to: 0...255))
    }
}
