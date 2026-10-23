@testable import GlowbarKit
import Foundation
import Testing

// Expected bytes follow the MQTT 3.1.1 specification.
// Expected packets are built from small typed pieces so older compilers type-check them quickly.

/// An MQTT string: 2-byte big-endian length, then UTF-8.
private func mqttString(_ value: String) -> [UInt8] {
    let bytes = Array(value.utf8)
    return [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)] + bytes
}

@Test func connectWithWillAndLogin() {
    let will = MQTTMessage(topic: "t/s", string: "offline", retain: true)
    let packet = MQTTPacket.connect(clientID: "c1", username: "u", password: "p", will: will, keepAlive: 30)
    var variableHeader: [UInt8] = mqttString("MQTT")
    variableHeader += [4, 0b1110_1110, 0, 30]
    var payload: [UInt8] = mqttString("c1")
    payload += mqttString("t/s")
    payload += mqttString("offline")
    payload += mqttString("u")
    payload += mqttString("p")
    var expected: [UInt8] = [0x10, UInt8(variableHeader.count + payload.count)]
    expected += variableHeader
    expected += payload
    #expect(packet == expected)
}

@Test func connectWithoutLoginOrWill() {
    let packet = MQTTPacket.connect(clientID: "c", username: "", password: "secret", will: nil, keepAlive: 60)
    // Clean session only; a password without a username isn't sent.
    #expect(packet[9] == 0x02)
    #expect(packet.count == 2 + 10 + 3)
}

@Test func retainedPublish() {
    let packet = MQTTPacket.publish(MQTTMessage(topic: "a/b", string: "on", retain: true))
    var expected: [UInt8] = [0x31, 7]
    expected += mqttString("a/b")
    expected += Array("on".utf8)
    #expect(packet == expected)
}

@Test func subscribeAtQoS0() {
    let packet = MQTTPacket.subscribe(["x", "yz"], packetID: 0x0102)
    var expected: [UInt8] = [0x82, 11, 0x01, 0x02]
    expected += mqttString("x") + [0]
    expected += mqttString("yz") + [0]
    #expect(packet == expected)
}

@Test func remainingLengthUsesVarint() throws {
    let packet = MQTTPacket.publish(MQTTMessage(topic: "t", payload: Data(count: 200)))
    // 2 + 1 + 200 = 203 = 0xCB 0x01
    #expect(Array(packet[0..<3]) == [0x30, 0xCB, 0x01])
    var buffer = packet
    #expect(try MQTTPacket.decode(&buffer) == [.publish(MQTTMessage(topic: "t", payload: Data(count: 200)), packetID: nil)])
}

@Test func decodesSeveralPacketsAndKeepsPartialTail() throws {
    var buffer: [UInt8] = [0x20, 2, 0, 0, 0xD0, 0, 0x90, 3, 0, 7, 0, 0x30, 9]
    let packets = try MQTTPacket.decode(&buffer)
    #expect(packets == [.connAck(returnCode: 0), .pingResp, .subAck(packetID: 7)])
    #expect(buffer == [0x30, 9])
}

@Test func decodesQoS1PublishWithPacketID() throws {
    var buffer: [UInt8] = [0x32, 8]
    buffer += mqttString("t")
    buffer += [0, 5]
    buffer += Array("{}x".utf8)
    let packets = try MQTTPacket.decode(&buffer)
    #expect(packets == [.publish(MQTTMessage(topic: "t", string: "{}x"), packetID: 5)])
    #expect(buffer.isEmpty)
}

@Test func rejectsMalformedConnAck() {
    var buffer: [UInt8] = [0x20, 1, 0]
    #expect(throws: MQTTPacket.MalformedPacket.self) { try MQTTPacket.decode(&buffer) }
}
