@testable import GlowbarKit
import Foundation
import Testing

private let device = HomeAssistantDevice(id: "abc123", name: "Glowbar on Test Mac", softwareVersion: "1.1.0")

private func json(_ message: MQTTMessage) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: message.payload) as? [String: Any])
}

private func command(_ string: String, topic: String = device.commandTopic) -> MQTTMessage {
    MQTTMessage(topic: topic, string: string)
}

@Test func lightDiscovery() throws {
    let messages = device.discoveryMessages()
    let light = try #require(messages.first { $0.topic == "homeassistant/light/glowbar_abc123/light/config" })
    #expect(light.retain)
    let config = try json(light)
    #expect(config["schema"] as? String == "json")
    #expect(config["name"] is NSNull)
    #expect(config["unique_id"] as? String == "glowbar_abc123_light")
    #expect(config["command_topic"] as? String == "glowbar/abc123/set")
    #expect(config["state_topic"] as? String == "glowbar/abc123/state")
    #expect(config["brightness_scale"] as? Int == 10)
    #expect(config["supported_color_modes"] as? [String] == ["rgb"])
    let effects = try #require(config["effect_list"] as? [String])
    #expect(effects.count == 15)
    #expect(!effects.contains("Off"))
    #expect(config["availability_mode"] as? String == "all")
    #expect(config["availability"] as? [[String: String]] == [
        ["topic": "glowbar/abc123/status"], ["topic": "glowbar/abc123/monitor"],
    ])
    let deviceInfo = try #require(config["device"] as? [String: Any])
    #expect(deviceInfo["identifiers"] as? [String] == ["glowbar_abc123"])
    #expect(deviceInfo["sw_version"] as? String == "1.1.0")
}

@Test func speedDiscovery() throws {
    let speed = try #require(device.discoveryMessages().first { $0.topic == "homeassistant/number/glowbar_abc123/speed/config" })
    let config = try json(speed)
    #expect(config["command_topic"] as? String == "glowbar/abc123/speed/set")
    #expect(config["min"] as? Int == 1)
    #expect(config["max"] as? Int == 6)
    #expect(config["value_template"] as? String == "{{ value_json.speed }}")
}

@Test func customDiscoveryPrefix() {
    let custom = HomeAssistantDevice(id: "x", name: "n", discoveryPrefix: "ha")
    #expect(custom.discoveryMessages().allSatisfy { $0.topic.hasPrefix("ha/") })
    #expect(custom.homeAssistantStatusTopic == "ha/status")
}

@Test func availabilityAndWillAreRetained() {
    #expect(device.will == MQTTMessage(topic: "glowbar/abc123/status", string: "offline", retain: true))
    #expect(device.macAvailability(online: true) == MQTTMessage(topic: "glowbar/abc123/status", string: "online", retain: true))
    #expect(device.monitorAvailability(connected: false) == MQTTMessage(topic: "glowbar/abc123/monitor", string: "offline", retain: true))
}

@Test func stateWhenOn() throws {
    let settings = LightingSettings(effect: .pulse, color: RGB(red: 1, green: 2, blue: 3), speed: 4, brightness: 7)
    let message = device.stateMessage(settings)
    #expect(message.retain)
    #expect(String(decoding: message.payload, as: UTF8.self)
        == #"{"brightness":7,"color":{"b":3,"g":2,"r":1},"color_mode":"rgb","effect":"Pulse","speed":4,"state":"ON"}"#)
}

@Test func stateWhenOff() {
    let message = device.stateMessage(LightingSettings(effect: .off, speed: 2))
    #expect(String(decoding: message.payload, as: UTF8.self) == #"{"speed":2,"state":"OFF"}"#)
}

@Test func turnOffAndBackOnRestoresLastEffect() throws {
    let lit = LightingSettings(effect: .meteor, speed: 5)
    let off = try #require(device.settings(applying: command(#"{"state":"OFF"}"#), to: lit, lastLitEffect: .meteor))
    #expect(off.effect == .off)
    #expect(off.speed == 5)
    let on = try #require(device.settings(applying: command(#"{"state":"ON"}"#), to: off, lastLitEffect: .meteor))
    #expect(on == lit)
}

@Test func commandSetsEffectBrightnessAndColor() throws {
    let message = command(#"{"state":"ON","effect":"Double Flash","brightness":3,"color":{"r":10,"g":20,"b":30}}"#)
    let settings = try #require(device.settings(applying: message, to: LightingSettings(), lastLitEffect: .staticColor))
    #expect(settings == LightingSettings(effect: .doubleFlash, color: RGB(red: 10, green: 20, blue: 30), brightness: 3))
}

@Test func colorOnFixedColorEffectSwitchesToStatic() throws {
    let wave = LightingSettings(effect: .rainbowWave)
    let message = command(#"{"state":"ON","color":{"r":0,"g":0,"b":255}}"#)
    let settings = try #require(device.settings(applying: message, to: wave, lastLitEffect: .rainbowWave))
    #expect(settings.effect == .staticColor)
    #expect(settings.color == RGB(red: 0, green: 0, blue: 255))
}

@Test func outOfRangeValuesAreClamped() throws {
    let message = command(#"{"state":"ON","brightness":0,"color":{"r":300,"g":-4,"b":12.6}}"#)
    let settings = try #require(device.settings(applying: message, to: LightingSettings(), lastLitEffect: .staticColor))
    #expect(settings.brightness == 1)
    #expect(settings.color == RGB(red: 255, green: 0, blue: 13))
}

@Test func speedCommand() throws {
    let topic = device.speedCommandTopic
    #expect(try #require(device.settings(applying: command("4.0", topic: topic), to: LightingSettings(), lastLitEffect: .staticColor)).speed == 4)
    #expect(try #require(device.settings(applying: command("9", topic: topic), to: LightingSettings(), lastLitEffect: .staticColor)).speed == 6)
    #expect(device.settings(applying: command("fast", topic: topic), to: LightingSettings(), lastLitEffect: .staticColor) == nil)
}

@Test func ignoresInvalidOrUnrelatedMessages() {
    #expect(device.settings(applying: command("not json"), to: LightingSettings(), lastLitEffect: .staticColor) == nil)
    #expect(device.settings(applying: command("{}", topic: "other/topic"), to: LightingSettings(), lastLitEffect: .staticColor) == nil)
}

@Test func unknownEffectNameKeepsCurrentEffect() throws {
    let message = command(#"{"state":"ON","effect":"Disco"}"#)
    let settings = try #require(device.settings(applying: message, to: LightingSettings(effect: .flash), lastLitEffect: .flash))
    #expect(settings.effect == .flash)
}
