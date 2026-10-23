import GlowbarKit
import AppKit
import ServiceManagement
import SwiftUI

/// The whole app: a menu bar panel with every lighting control.
struct LightingPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        let effect = model.settings.effect
        VStack(alignment: .leading, spacing: 14) {
            StatusHeader(model: model)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                EffectGrid(selection: $model.settings.effect)
                Text(effect.summary)
                    .font(.caption)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ColorSection(color: $model.settings.color)
                .disabledLook(!effect.usesColor)
            VStack(spacing: 8) {
                LevelSlider(
                    title: "Speed", value: $model.settings.speed,
                    range: LightingSettings.speedRange, low: "tortoise", high: "hare"
                )
                .disabledLook(!effect.usesSpeed)
                LevelSlider(
                    title: "Brightness", value: $model.settings.brightness,
                    range: LightingSettings.brightnessRange, low: "sun.min", high: "sun.max"
                )
                .disabledLook(!effect.usesBrightness)
            }
            Divider()
            PanelFooter()
        }
        .padding(14)
        .frame(width: 320)
    }
}

// MARK: - Header

private struct StatusHeader: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.controllerName ?? "No monitor connected")
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                model.applyNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!model.isConnected)
            .help("Send current settings to the monitor again")
        }
    }

    private var dotColor: Color {
        switch model.status {
        case .searching: .secondary
        case .connected, .applied: .green
        case .failed: .orange
        }
    }

    private var detail: String {
        switch model.status {
        case .searching: "Connect the monitor's USB upstream cable to this Mac."
        case .connected: "Ready"
        case let .applied(name): "\(name)" + (model.firmware.map { " · firmware \($0)" } ?? "")
        case let .failed(message): message
        }
    }
}

// MARK: - Effects

private struct EffectGrid: View {
    @Binding var selection: Effect

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Effect.allCases) { effect in
                EffectTile(effect: effect, isSelected: effect == selection) { selection = effect }
            }
        }
    }
}

private struct EffectTile: View {
    let effect: Effect
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: effect.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 18)
                Text(effect.shortName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(effect.displayName): \(effect.summary)")
        .accessibilityLabel(effect.displayName)
        .accessibilityHint(effect.summary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return .accentColor }
        return Color.primary.opacity(isHovered ? 0.12 : 0.06)
    }
}

private extension Effect {
    var shortName: String {
        switch self {
        case .doubleFlash: "2× Flash"
        case .colorCycle: "Cycle"
        default: displayName
        }
    }

    var symbol: String {
        switch self {
        case .staticColor: "circle.fill"
        case .pulse: "waveform.path"
        case .flash: "bolt.fill"
        case .doubleFlash: "bolt.horizontal.fill"
        case .colorCycle: "paintpalette"
        case .scanner: "arrow.left.arrow.right"
        case .expand: "arrow.left.and.line.vertical.and.arrow.right"
        case .rainbowWave: "water.waves"
        case .starSlide: "star.fill"
        case .meteor: "wind"
        case .shaking: "arrow.left.and.right"
        case .recover: "rainbow"
        case .doubleMeteor: "arrow.right.and.line.vertical.and.arrow.left"
        case .colorStack: "square.stack.3d.up.fill"
        case .colorRain: "cloud.rain.fill"
        case .off: "power"
        }
    }
}

// MARK: - Color

private struct ColorSection: View {
    @Binding var color: RGB
    @State private var hexText = ""
    @FocusState private var hexFocused: Bool

    private static let presets: [RGB] = [
        RGB(red: 255, green: 255, blue: 255),
        RGB(red: 255, green: 0, blue: 0),
        .orange,
        RGB(red: 255, green: 200, blue: 0),
        RGB(red: 0, green: 255, blue: 0),
        RGB(red: 0, green: 255, blue: 255),
        RGB(red: 0, green: 80, blue: 255),
        RGB(red: 160, green: 0, blue: 255),
        RGB(red: 255, green: 0, blue: 160),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Self.presets, id: \.hex) { preset in
                    Swatch(color: preset, isSelected: preset == color) { color = preset }
                    if preset != Self.presets.last { Spacer(minLength: 0) }
                }
            }
            HueStrip(color: $color)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.swiftUIColor)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.primary.opacity(0.2)))
                    .frame(width: 22, height: 22)
                Text("#").foregroundStyle(.secondary)
                TextField("RRGGBB", text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 90)
                    .focused($hexFocused)
                    .onSubmit(commitHex)
                    .onChange(of: hexFocused) { _, focused in if !focused { commitHex() } }
                Spacer()
            }
        }
        .onAppear { hexText = color.hex }
        .onChange(of: color) { _, new in if !hexFocused { hexText = new.hex } }
    }

    private func commitHex() {
        if let parsed = RGB(hex: hexText.trimmingCharacters(in: .whitespaces)) {
            color = parsed
        }
        hexText = color.hex
    }
}

private struct Swatch: View {
    let color: RGB
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.swiftUIColor)
                .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 0.5))
                .frame(width: 22, height: 22)
                .padding(2)
                .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help("#\(color.hex)")
    }
}

/// Drag across the rainbow to pick a fully saturated hue.
private struct HueStrip: View {
    @Binding var color: RGB
    private let knob: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            // The knob's center travels between knob/2 and width - knob/2; the gradient spans the same range.
            let track = geometry.size.width - knob
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { Color(hue: $0, saturation: 1, brightness: 1) },
                    startPoint: UnitPoint(x: knob / 2 / geometry.size.width, y: 0.5),
                    endPoint: UnitPoint(x: 1 - knob / 2 / geometry.size.width, y: 0.5)
                )
                .clipShape(Capsule())
                if let hue = color.saturatedHue {
                    Circle()
                        .fill(color.swiftUIColor)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(radius: 1)
                        .frame(width: knob, height: knob)
                        .offset(x: hue * track)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let hue = min(max((value.location.x - knob / 2) / track, 0), 0.999)
                    color = RGB(hue: hue)
                }
            )
        }
        .frame(height: knob)
        .accessibilityElement()
        .accessibilityLabel("Hue")
    }
}

// MARK: - Sliders

private struct LevelSlider: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let low: String
    let high: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .frame(width: 72, alignment: .leading)
            Image(systemName: low).foregroundStyle(.secondary).font(.caption).frame(width: 18)
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .controlSize(.small)
            Image(systemName: high).foregroundStyle(.secondary).font(.caption).frame(width: 18)
        }
    }
}

// MARK: - Footer

private struct PanelFooter: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            Toggle("Open at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.callout)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Spacer()
            Button {
                // A menu bar app has to come forward itself, or the window opens behind others.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "house")
            }
            .buttonStyle(.borderless)
            .help("Home Assistant")
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
    }
}

// MARK: - Helpers

private extension View {
    /// Dims controls the current effect ignores, keeping the panel layout stable.
    func disabledLook(_ disabled: Bool) -> some View {
        self.disabled(disabled).opacity(disabled ? 0.35 : 1)
    }
}

private extension RGB {
    var swiftUIColor: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    init(hue: Double) {
        let ns = NSColor(hue: hue, saturation: 1, brightness: 1, alpha: 1).usingColorSpace(.sRGB)!
        self.init(
            red: UInt8((ns.redComponent * 255).rounded().clamped(to: 0...255)),
            green: UInt8((ns.greenComponent * 255).rounded().clamped(to: 0...255)),
            blue: UInt8((ns.blueComponent * 255).rounded().clamped(to: 0...255))
        )
    }

    /// Position on the hue strip, or nil for colors the strip can't represent (whites, pastels).
    var saturatedHue: Double? {
        let ns = NSColor(srgbRed: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, alpha: 1)
        guard ns.saturationComponent > 0.95, ns.brightnessComponent > 0.95 else { return nil }
        return ns.hueComponent
    }
}
