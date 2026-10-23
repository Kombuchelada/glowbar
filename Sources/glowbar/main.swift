import GlowbarKit
import Foundation

let usage = """
Usage:
  glowbar list                        Find lighting controllers (no USB traffic)
  glowbar info                        Query controller identity (read-only)
  glowbar set <effect> [options]      Apply an effect
      --color RRGGBB   --speed 1-6   --brightness 1-10
  glowbar effects                     List effect names
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func value(after flag: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
    return args[index + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail(usage) }

if command == "effects" {
    for effect in Effect.allCases { print("\(effect.rawValue)\t\(effect.displayName)") }
    exit(0)
}

let controllers = LightingControllerBrowser().enumerate()

switch command {
case "list":
    if controllers.isEmpty { fail(LightingError.noController.localizedDescription) }
    for controller in controllers { print(controller.productName) }
case "info":
    guard let controller = controllers.first else { fail(LightingError.noController.localizedDescription) }
    do {
        let info = try controller.readInfo()
        print("Product:     \(info.productString.isEmpty ? controller.productName : info.productString)")
        print("Firmware:    \(info.firmwareVersion)")
        print("FO series:   \(info.isFOSeries ? "yes" : "no")")
        print("Chip ID:     0x\(String(info.chipID, radix: 16))")
    } catch { fail(error.localizedDescription) }
case "set":
    guard args.count >= 2, let effect = Effect(rawValue: args[1]) else { fail(usage) }
    var settings = LightingSettings(effect: effect)
    if let hex = value(after: "--color", in: args) {
        guard let color = RGB(hex: hex) else { fail("Invalid color \(hex)") }
        settings.color = color
    }
    if let speed = value(after: "--speed", in: args).flatMap(Int.init) { settings.speed = speed }
    if let level = value(after: "--brightness", in: args).flatMap(Int.init) { settings.brightness = level }
    guard let controller = controllers.first else { fail(LightingError.noController.localizedDescription) }
    do { try controller.apply(settings) } catch { fail(error.localizedDescription) }
    print("Applied \(effect.displayName)")
default:
    fail(usage)
}
