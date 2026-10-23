// Minimal MQTT 3.1.1 packet encoding and decoding: just what a Home Assistant bridge needs
// (connect with a last will, QoS 0 publish and subscribe, keep-alive). Pure; no I/O.

import Foundation

public struct MQTTMessage: Equatable, Sendable {
    public var topic: String
    public var payload: Data
    public var retain: Bool

    public init(topic: String, payload: Data, retain: Bool = false) {
        self.topic = topic
        self.payload = payload
        self.retain = retain
    }

    public init(topic: String, string: String, retain: Bool = false) {
        self.init(topic: topic, payload: Data(string.utf8), retain: retain)
    }
}

public enum MQTTPacket: Equatable, Sendable {
    /// Return code 0 means accepted.
    case connAck(returnCode: UInt8)
    case publish(MQTTMessage, packetID: UInt16?)
    case subAck(packetID: UInt16)
    case pingResp
    /// Any other packet type; ignored by the client.
    case other(type: UInt8)

    static let typeConnect: UInt8 = 1
    static let typeConnAck: UInt8 = 2
    static let typePublish: UInt8 = 3
    static let typePubAck: UInt8 = 4
    static let typeSubscribe: UInt8 = 8
    static let typeSubAck: UInt8 = 9
    static let typePingReq: UInt8 = 12
    static let typePingResp: UInt8 = 13
    static let typeDisconnect: UInt8 = 14

    // MARK: Encoding

    public static func connect(
        clientID: String, username: String?, password: String?, will: MQTTMessage?, keepAlive: UInt16
    ) -> [UInt8] {
        var flags: UInt8 = 0x02  // clean session
        var payload = string(clientID)
        if let will {
            // Will QoS 1 so the broker reliably delivers "offline" to Home Assistant.
            flags |= 0x04 | 0x08 | (will.retain ? 0x20 : 0)
            payload += string(will.topic) + binary(will.payload)
        }
        if let username, !username.isEmpty {
            flags |= 0x80
            payload += string(username)
            if let password, !password.isEmpty {
                flags |= 0x40
                payload += binary(Data(password.utf8))
            }
        }
        let variableHeader = string("MQTT") + [4, flags] + keepAlive.bigEndianBytes
        return packet(typeConnect << 4, variableHeader + payload)
    }

    /// QoS 0 publish.
    public static func publish(_ message: MQTTMessage) -> [UInt8] {
        packet(typePublish << 4 | (message.retain ? 1 : 0), string(message.topic) + Array(message.payload))
    }

    /// Subscribes at QoS 0.
    public static func subscribe(_ topics: [String], packetID: UInt16) -> [UInt8] {
        packet(typeSubscribe << 4 | 0x02, packetID.bigEndianBytes + topics.flatMap { string($0) + [0] })
    }

    static func pubAck(packetID: UInt16) -> [UInt8] { packet(typePubAck << 4, packetID.bigEndianBytes) }
    public static let pingReq: [UInt8] = [typePingReq << 4, 0]
    public static let disconnect: [UInt8] = [typeDisconnect << 4, 0]

    static func packet(_ header: UInt8, _ body: [UInt8]) -> [UInt8] {
        var out = [header]
        var length = body.count
        repeat {
            var byte = UInt8(length % 128)
            length /= 128
            if length > 0 { byte |= 0x80 }
            out.append(byte)
        } while length > 0
        return out + body
    }

    static func string(_ value: String) -> [UInt8] { binary(Data(value.utf8)) }
    static func binary(_ value: Data) -> [UInt8] { UInt16(value.count).bigEndianBytes + Array(value) }

    // MARK: Decoding

    /// Removes and returns every complete packet at the front of `buffer`; a partial packet stays.
    /// Throws if the stream is malformed.
    public static func decode(_ buffer: inout [UInt8]) throws -> [MQTTPacket] {
        var packets: [MQTTPacket] = []
        while let (packet, consumed) = try decodeOne(buffer[...]) {
            packets.append(packet)
            buffer.removeFirst(consumed)
        }
        return packets
    }

    public struct MalformedPacket: Error {}

    private static func decodeOne(_ bytes: ArraySlice<UInt8>) throws -> (MQTTPacket, Int)? {
        guard let header = bytes.first else { return nil }
        var length = 0, multiplier = 1, index = bytes.startIndex + 1
        while true {
            guard index < bytes.endIndex else { return nil }
            let byte = bytes[index]
            length += Int(byte & 0x7F) * multiplier
            index += 1
            if byte & 0x80 == 0 { break }
            multiplier *= 128
            guard multiplier <= 128 * 128 * 128 else { throw MalformedPacket() }
        }
        guard bytes.endIndex - index >= length else { return nil }
        let body = Array(bytes[index..<index + length])
        let consumed = index + length - bytes.startIndex

        switch header >> 4 {
        case typeConnAck:
            guard body.count == 2 else { throw MalformedPacket() }
            return (.connAck(returnCode: body[1]), consumed)
        case typePublish:
            let qos = (header >> 1) & 0x03
            guard body.count >= 2 else { throw MalformedPacket() }
            let topicLength = Int(body[0]) << 8 | Int(body[1])
            var offset = 2 + topicLength
            guard body.count >= offset else { throw MalformedPacket() }
            let topic = String(decoding: body[2..<offset], as: UTF8.self)
            var packetID: UInt16?
            if qos > 0 {
                guard body.count >= offset + 2 else { throw MalformedPacket() }
                packetID = UInt16(body[offset]) << 8 | UInt16(body[offset + 1])
                offset += 2
            }
            let message = MQTTMessage(topic: topic, payload: Data(body[offset...]), retain: header & 1 == 1)
            return (.publish(message, packetID: packetID), consumed)
        case typeSubAck:
            guard body.count >= 2 else { throw MalformedPacket() }
            return (.subAck(packetID: UInt16(body[0]) << 8 | UInt16(body[1])), consumed)
        case typePingResp:
            return (.pingResp, consumed)
        default:
            return (.other(type: header >> 4), consumed)
        }
    }
}

extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] { withUnsafeBytes(of: bigEndian) { Array($0) } }
}
