// USB HID protocol for the RGB lighting controller in GIGABYTE AORUS FO-series monitors.
// See docs/PROTOCOL.md.

import Foundation

/// USB identity of the monitor's lighting controller.
public enum ControllerIdentity {
    public static let vendorID = 0x048D   // ITE Tech
    public static let productID = 0x8295
    public static let usagePage = 0xFF89  // vendor-defined
    public static let reportID: UInt8 = 0xCC
    public static let reportLength = 64
}

/// Lighting effects built into FO-series monitor firmware.
public enum Effect: String, CaseIterable, Codable, Sendable, Identifiable {
    case staticColor, pulse, flash, doubleFlash, colorCycle
    case scanner, expand, rainbowWave
    case starSlide, meteor, shaking, recover, doubleMeteor, colorStack, colorRain
    case off

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .staticColor: "Static"
        case .pulse: "Pulse"
        case .flash: "Flash"
        case .doubleFlash: "Double Flash"
        case .colorCycle: "Color Cycle"
        case .scanner: "Scanner"
        case .expand: "Expand"
        case .rainbowWave: "Wave"
        case .starSlide: "Star Slide"
        case .meteor: "Meteor"
        case .shaking: "Shaking"
        case .recover: "Recover"
        case .doubleMeteor: "Double Meteor"
        case .colorStack: "Color Stack"
        case .colorRain: "Color Rain"
        case .off: "Off"
        }
    }

    /// What the effect looks like.
    public var summary: String {
        switch self {
        case .staticColor: "Solid color."
        case .pulse: "Fades in and out."
        case .flash: "Blinks once per cycle."
        case .doubleFlash: "Blinks twice per cycle."
        case .colorCycle: "Steps through the rainbow."
        case .scanner: "A block slides back and forth over a solid bar; colors change each pass."
        case .expand: "A block grows from the center to fill the bar, then shrinks; colors change."
        case .rainbowWave: "Rainbow colors flow left and right while the brightness rises and falls."
        case .starSlide: "A single light runs along the strip."
        case .meteor: "A light with a fading tail sweeps along the strip."
        case .shaking: "A block of light bounces back and forth."
        case .recover: "Rainbow colors wipe across and fill the strip."
        case .doubleMeteor: "Two meteors start at the ends and cross in the middle."
        case .colorStack: "Rainbow lights drop in and pile up."
        case .colorRain: "Rainbow dots scroll along the strip."
        case .off: "Lights off."
        }
    }

    /// Whether the firmware uses the chosen color, speed and brightness for this effect.
    public var usesColor: Bool {
        switch self {
        case .staticColor, .pulse, .flash, .doubleFlash, .starSlide, .meteor, .shaking, .doubleMeteor: true
        default: false
        }
    }

    public var usesSpeed: Bool {
        switch self {
        case .staticColor, .scanner, .expand, .rainbowWave, .off: false
        default: true
        }
    }

    public var usesBrightness: Bool {
        switch self {
        case .pulse, .scanner, .expand, .rainbowWave, .off: false
        default: true
        }
    }
}

/// 24-bit RGB color.
public struct RGB: Equatable, Codable, Sendable {
    public var red: UInt8, green: UInt8, blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red; self.green = green; self.blue = blue
    }

    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    var packed: UInt32 { UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue) }
    public var hex: String { String(format: "%06X", packed) }

    /// Default accent color (0xFF4200).
    public static let orange = RGB(red: 0xFF, green: 0x42, blue: 0x00)
}

public struct LightingSettings: Equatable, Codable, Sendable {
    public static let speedRange = 1...6
    public static let brightnessRange = 1...10

    public var effect: Effect
    public var color: RGB
    /// 1 (slowest) ... 6 (fastest)
    public var speed: Int
    /// 1 (15%) ... 10 (100%)
    public var brightness: Int

    public init(effect: Effect = .staticColor, color: RGB = .orange, speed: Int = 3, brightness: Int = 10) {
        self.effect = effect
        self.color = color
        self.speed = speed
        self.brightness = brightness
    }
}

/// Builds the 64-byte feature reports the controller accepts. Pure; no I/O.
public enum ReportBuilder {
    // Command bytes (report[1]).
    static let cmdEffectZone0: UInt8 = 0x20
    static let cmdEffectZone1: UInt8 = 0x21
    static let cmdApply: UInt8 = 0x28
    static let cmdStripControl: UInt8 = 0x32
    static let cmdQueryInfo: UInt8 = 0x60

    // Brightness levels 1...10, in percent
    static let brightnessPercent: [UInt8] = [15, 20, 30, 40, 50, 60, 70, 80, 90, 100]

    // Timings in ms for speed levels 1...6 (slowest to fastest)
    static let breathing: [(UInt16, UInt16)] = [(1600, 1600), (1400, 1400), (1200, 1200), (1000, 1000), (900, 900), (800, 800)]
    static let flashGap: [UInt16] = [2400, 2200, 2000, 1800, 1600, 1400]
    static let doubleFlashGap: [UInt16] = [2600, 2400, 2200, 2000, 1800, 1600]
    static let cycle: [(UInt16, UInt16)] = [(2500, 2400), (1200, 1100), (1100, 1000), (1000, 900), (900, 800), (800, 700)]

    // Timings for the strip animations, speed levels 1...6
    static let starSlideTiming: [UInt16] = [240, 176, 150, 128, 101, 64]
    static let meteorTiming: [(UInt16, UInt16)] = [(204, 704), (172, 544), (188, 380), (108, 348), (76, 256), (44, 128)]
    static let shakingTiming: [(UInt16, UInt16)] = [(160, 150), (120, 150), (80, 150), (60, 150), (40, 150), (20, 150)]
    static let recoverTiming: [(UInt16, UInt16)] = [(288, 150), (130, 150), (100, 150), (80, 150), (60, 150), (40, 150)]
    static let doubleMeteorTiming: [(UInt16, UInt16)] = [(192, 492), (160, 460), (128, 300), (96, 256), (64, 192), (48, 96)]
    static let colorStackTiming: [UInt16] = [112, 96, 80, 64, 48, 32]
    static let colorRainTiming: [UInt16] = [160, 144, 128, 112, 96, 80]

    /// The 32-byte effect parameter block (little-endian).
    struct EffectData {
        var zoneSel0: UInt32 = 0
        var zoneSel1: UInt32 = 0
        var modeSel: UInt8 = 0
        var maxBrightness: UInt8 = 0
        var minBrightness: UInt8 = 0
        var color0: UInt32 = 0
        var color1: UInt32 = 0
        var time0: UInt16 = 0, time1: UInt16 = 0, time2: UInt16 = 0, time3: UInt16 = 0
        var ctrl0: UInt8 = 0, ctrl1: UInt8 = 0, oem0: UInt8 = 0, oem1: UInt8 = 0

        var bytes: [UInt8] {
            var out = [UInt8]()
            out.reserveCapacity(32)
            out += zoneSel0.littleEndianBytes
            out += zoneSel1.littleEndianBytes
            out += [0, modeSel, maxBrightness, minBrightness]
            out += color0.littleEndianBytes
            out += color1.littleEndianBytes
            for t in [time0, time1, time2, time3] { out += t.littleEndianBytes }
            out += [ctrl0, ctrl1, oem0, oem1]
            return out
        }
    }

    static func blankReport(_ command: UInt8) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: ControllerIdentity.reportLength)
        report[0] = ControllerIdentity.reportID
        report[1] = command
        return report
    }

    public static func queryInfo() -> [UInt8] { blankReport(cmdQueryInfo) }

    /// Apply latched settings (zone bit mask 3).
    public static func apply() -> [UInt8] {
        var report = blankReport(cmdApply)
        report[2] = 3
        return report
    }

    /// Disable host-streamed strip control (sent once per session).
    public static func disableStripStreaming() -> [UInt8] { blankReport(cmdStripControl) }

    /// Zero effect for zone 0, sent once per session to FO-series firmware.
    public static func foSeriesReset() -> [UInt8] {
        var report = blankReport(cmdEffectZone0)
        report[2] = 1
        return report
    }

    /// The effect report for FO-series monitors.
    public static func effect(_ settings: LightingSettings) -> [UInt8] {
        let sp = settings.speed.clamped(to: LightingSettings.speedRange) - 1
        let level = brightnessPercent[settings.brightness.clamped(to: LightingSettings.brightnessRange) - 1]
        var d = EffectData()
        var applyColor = true

        switch settings.effect {
        case .staticColor:
            d.modeSel = 1
            d.maxBrightness = level
        case .pulse:
            let (w0, w1) = breathing[sp]
            let n2 = w0 - w0 / 2
            let n3 = w1 - w0 / 2
            let n4 = n2 - 220
            d.modeSel = 2
            d.time0 = n2
            d.time1 = n3 - n4
            d.time2 = n2 + n4 / 2
            d.maxBrightness = 100
            d.ctrl1 = 1
        case .flash:
            d.modeSel = 3
            (d.time0, d.time1, d.time2) = (100, 100, flashGap[sp])
            d.maxBrightness = level
            d.ctrl1 = 1
            d.oem0 = 1
        case .doubleFlash:
            d.modeSel = 3
            (d.time0, d.time1, d.time2) = (100, 100, doubleFlashGap[sp])
            d.maxBrightness = level
            d.ctrl1 = 1
            d.oem0 = 2
        case .colorCycle:
            d.modeSel = 4
            (d.time0, d.time1) = cycle[sp]
            d.maxBrightness = level
            d.ctrl0 = 7
        case .scanner:
            d.modeSel = 19
            d.maxBrightness = 100
            d.color0 = 0xFFFFFF
            d.time0 = 48
            applyColor = false
        case .expand:
            d.modeSel = 18
            d.maxBrightness = 100
            d.color0 = 0xFFFFFF
            (d.time0, d.time2, d.time3) = (64, 384, 300)
        case .rainbowWave:
            d.modeSel = 6
            d.maxBrightness = 100
            d.color0 = 0xE0
            d.color1 = 0xF000
            (d.time0, d.time1, d.time2, d.time3) = (123, 1600, 3200, 512)
            d.ctrl0 = 7
            d.ctrl1 = 1
        case .starSlide:
            d.modeSel = 5
            d.maxBrightness = level
            d.time0 = starSlideTiming[sp]
            d.ctrl1 = 1
        case .meteor:
            d.modeSel = 11
            d.maxBrightness = level
            (d.time0, d.time1) = meteorTiming[sp]
            (d.time2, d.time3) = (20, 512)
            d.ctrl1 = 1
        case .shaking:
            d.modeSel = 12
            d.maxBrightness = level
            (d.time0, d.time1) = shakingTiming[sp]
            (d.time2, d.time3) = (100, 100)
            d.ctrl1 = 1
            d.oem0 = 1
        case .recover:
            d.modeSel = 13
            d.maxBrightness = level
            (d.time0, d.time1) = recoverTiming[sp]
            (d.time2, d.time3) = (100, 100)
            d.ctrl1 = 1
            d.oem0 = 1
        case .doubleMeteor:
            d.modeSel = 14
            d.maxBrightness = level
            (d.time0, d.time3) = doubleMeteorTiming[sp]
            d.ctrl1 = 1
        case .colorStack:
            d.modeSel = 15
            d.maxBrightness = level
            d.time0 = colorStackTiming[sp]
            d.ctrl1 = 1
            d.oem0 = 2
        case .colorRain:
            d.modeSel = 16
            d.maxBrightness = level
            d.time0 = colorRainTiming[sp]
            d.time1 = 64
            d.ctrl0 = 7
            d.ctrl1 = 1
            d.oem0 = 1
        case .off:
            d.modeSel = 1
            d.maxBrightness = 100
            applyColor = false
        }

        // The chosen color goes with every effect except Off and Scanner.
        if applyColor { d.color0 = settings.color.packed }
        d.zoneSel0 = 0xFFFF_FFFE
        d.zoneSel1 = 0x1FF

        var report = blankReport(cmdEffectZone1)
        report.replaceSubrange(2..<34, with: d.bytes)
        return report
    }
}

/// Parsed reply to the 0x60 info query.
public struct ControllerInfo: Equatable, Sendable {
    public let product: UInt8
    public let deviceNumber: UInt8
    public let firmwareBytes: [UInt8]
    public let productString: String
    public let chipID: UInt32

    public init?(report: [UInt8]) {
        guard report.count >= 64 else { return nil }
        product = report[1]
        deviceNumber = report[2]
        firmwareBytes = Array(report[4..<8])
        let raw = report[12..<40].prefix { $0 != 0 }
        productString = String(decoding: raw, as: UTF8.self)
        chipID = UInt32(report[56]) | UInt32(report[57]) << 8 | UInt32(report[58]) << 16 | UInt32(report[59]) << 24
    }

    /// Firmware that takes the FO-series command set.
    public var isFOSeries: Bool { firmwareBytes[2] == 4 || firmwareBytes[0] == 1 }

    public var firmwareVersion: String { firmwareBytes.reversed().map { String($0) }.joined(separator: ".") }
}

extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] { withUnsafeBytes(of: littleEndian) { Array($0) } }
}

public extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
