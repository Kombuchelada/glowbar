@testable import GlowbarKit
import Testing

// Expected bytes follow docs/PROTOCOL.md:
// report = [0xCC, cmd, effect parameter block (32 bytes, little-endian), zero padding].
// Struct offsets within the report: zoneSel0 2, zoneSel1 6, mode 11, max 12, min 13,
// color0 14, color1 18, time0 22, time1 24, time2 26, time3 28, ctrl0 30, ctrl1 31, oem0 32.

private func header(_ report: [UInt8]) -> [UInt8] { Array(report[0..<10]) }
private func u16(_ report: [UInt8], _ offset: Int) -> UInt16 { UInt16(report[offset]) | UInt16(report[offset + 1]) << 8 }

private let foHeader: [UInt8] = [0xCC, 0x21, 0xFE, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x00, 0x00]

@Test func staticRedFullBrightness() {
    let report = ReportBuilder.effect(LightingSettings(effect: .staticColor, color: RGB(red: 0xFF, green: 0, blue: 0), brightness: 10))
    var expected = [UInt8](repeating: 0, count: 64)
    expected.replaceSubrange(0..<18, with: foHeader + [0x00, 0x01, 100, 0x00, 0x00, 0x00, 0xFF, 0x00])
    #expect(report == expected)
}

@Test func staticBrightnessUsesLevelTable() {
    let report = ReportBuilder.effect(LightingSettings(effect: .staticColor, brightness: 1))
    #expect(report[12] == 15)
}

@Test func pulseSlowestTiming() {
    // Breathing sp0 = (1600, 1600): n2 = 800, n3 = 800, n4 = 580
    let report = ReportBuilder.effect(LightingSettings(effect: .pulse, color: RGB(red: 0, green: 0x80, blue: 0xFF), speed: 1))
    #expect(header(report) == foHeader)
    #expect(report[11] == 2)
    #expect(report[12] == 100)
    #expect(Array(report[14..<18]) == [0xFF, 0x80, 0x00, 0x00])
    #expect(u16(report, 22) == 800)
    #expect(u16(report, 24) == 220)
    #expect(u16(report, 26) == 1090)
    #expect(report[31] == 1)
}

@Test func flashAndDoubleFlashShareModeButDifferInOem() {
    let flash = ReportBuilder.effect(LightingSettings(effect: .flash, speed: 6))
    let double = ReportBuilder.effect(LightingSettings(effect: .doubleFlash, speed: 6))
    #expect(flash[11] == 3 && double[11] == 3)
    #expect(u16(flash, 26) == 1400 && u16(double, 26) == 1600)
    #expect(flash[32] == 1 && double[32] == 2)
}

@Test func colorCycleSlowestTiming() {
    let report = ReportBuilder.effect(LightingSettings(effect: .colorCycle, speed: 1))
    #expect(report[11] == 4)
    #expect(u16(report, 22) == 2500 && u16(report, 24) == 2400)
    #expect(report[30] == 7)
}

@Test func offAndScannerIgnoreColor() {
    let off = ReportBuilder.effect(LightingSettings(effect: .off, color: RGB(red: 1, green: 2, blue: 3)))
    #expect(off[11] == 1 && off[12] == 100)
    #expect(Array(off[14..<18]) == [0, 0, 0, 0])
    let scanner = ReportBuilder.effect(LightingSettings(effect: .scanner, color: RGB(red: 1, green: 2, blue: 3)))
    #expect(scanner[11] == 19)
    #expect(Array(scanner[14..<18]) == [0xFF, 0xFF, 0xFF, 0x00])
}

@Test func stripAnimationsMapToFirmwareModeNumbers() {
    let expected: [(Effect, UInt8)] = [(.starSlide, 5), (.meteor, 11), (.shaking, 12), (.recover, 13), (.doubleMeteor, 14), (.colorStack, 15), (.colorRain, 16)]
    for (effect, mode) in expected {
        #expect(ReportBuilder.effect(LightingSettings(effect: effect))[11] == mode)
    }
    let g = ReportBuilder.effect(LightingSettings(effect: .colorRain, speed: 1))
    #expect(u16(g, 22) == 160 && u16(g, 24) == 64 && g[30] == 7 && g[31] == 1 && g[32] == 1)
}

@Test func controlReports() {
    #expect(Array(ReportBuilder.apply().prefix(3)) == [0xCC, 0x28, 0x03])
    #expect(Array(ReportBuilder.queryInfo().prefix(2)) == [0xCC, 0x60])
    #expect(Array(ReportBuilder.foSeriesReset().prefix(3)) == [0xCC, 0x20, 0x01])
    #expect(Array(ReportBuilder.disableStripStreaming().prefix(3)) == [0xCC, 0x32, 0x00])
    for report in [ReportBuilder.apply(), ReportBuilder.queryInfo(), ReportBuilder.effect(LightingSettings())] {
        #expect(report.count == 64)
    }
}

@Test func outOfRangeLevelsAreClamped() {
    let report = ReportBuilder.effect(LightingSettings(effect: .flash, speed: 99, brightness: -4))
    #expect(u16(report, 26) == 1400)
    #expect(report[12] == 15)
}

@Test func parsesInfoReplyAndDetectsFOFirmware() {
    var reply = [UInt8](repeating: 0, count: 64)
    reply[0] = 0xCC
    reply[1] = 3
    reply.replaceSubrange(4..<8, with: [0x02, 0x00, 0x04, 0x01])
    reply.replaceSubrange(12..<17, with: Array("FO32U".utf8))
    reply.replaceSubrange(56..<60, with: [0x95, 0x82, 0x00, 0x00])
    let info = ControllerInfo(report: reply)
    #expect(info?.isFOSeries == true)
    #expect(info?.productString == "FO32U")
    #expect(info?.firmwareVersion == "1.4.0.2")
    #expect(info?.chipID == 0x8295)

    reply.replaceSubrange(4..<8, with: [0x02, 0x00, 0x03, 0x01])
    #expect(ControllerInfo(report: reply)?.isFOSeries == false)
    #expect(ControllerInfo(report: [0xCC]) == nil)
}

