@testable import GlowbarKit
import Foundation
import Testing

// Expected bytes follow the MQTT 3.1.1 specification.

@Test func connectWithWillAndLogin() {
    let will = MQTTMessage(topic: "t/s", string: "offline", retain: true)
    let packet = MQTTPacket.connect(clientID: "c1", username: "u", password: "p", will: will, keepAlive: 30)
    let variableHeader: [UInt8] = [0, 4] + Array("MQTT".utf8) + [4, 0b1110_1110, 0, 30]
    let payload: [UInt8] = [0, 2] + Array("c1".utf8)
        + [0, 3] + Array("t/s".utf8) + [0, 7] + Array("offline".utf8)
        + [0, 1, UInt8(ascii: "u")] + [0, 1, UInt8(ascii: "p")]
    #expect(packet == [0x10, UInt8(variableHeader.count + payload.count)] + variableHeader + payload)
}

@Test func connectWithoutLoginOrWill() {
    let packet = MQTTPacket.connect(clientID: "c", username: "", password: "secret", will: nil, keepAlive: 60)
    // Clean session only; a password without a username isn't sent.
    #expect(packet[9] == 0x02)
    #expect(packet.count == 2 + 10 + 3)
}

@Test func retainedPublish() {
    let packet = MQTTPacket.publish(MQTTMessage(topic: "a/b", string: "on", retain: true))
    #expect(packet == [0x31, 7, 0, 3] + Array("a/b".utf8) + Array("on".utf8))
}

@Test func subscribeAtQoS0() {
    let packet = MQTTPacket.subscribe(["x", "yz"], packetID: 0x0102)
    #expect(packet == [0x82, 11, 0x01, 0x02, 0, 1, UInt8(ascii: "x"), 0, 0, 2] + Array("yz".utf8) + [0])
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
    var buffer: [UInt8] = [0x32, 8, 0, 1, UInt8(ascii: "t"), 0, 5] + Array("{}x".utf8)
    let packets = try MQTTPacket.decode(&buffer)
    #expect(packets == [.publish(MQTTMessage(topic: "t", string: "{}x"), packetID: 5)])
    #expect(buffer.isEmpty)
}

@Test func rejectsMalformedConnAck() {
    var buffer: [UInt8] = [0x20, 1, 0]
    #expect(throws: MQTTPacket.MalformedPacket.self) { try MQTTPacket.decode(&buffer) }
}
