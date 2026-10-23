import Foundation
import IOKit.hid

public enum LightingError: Error, LocalizedError {
    case noController
    case io(String, IOReturn)
    case badReply
    case unsupportedFirmware(String)

    public var errorDescription: String? {
        switch self {
        case .noController:
            "No compatible monitor lighting controller found. Connect the monitor's USB upstream cable (USB-C or USB-B) to this Mac."
        case let .io(step, code):
            "USB transfer failed during \(step) (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .badReply:
            "The lighting controller returned an unexpected reply."
        case let .unsupportedFirmware(version):
            "Controller firmware \(version) does not use the FO-series command set; this app only drives FO-series monitors."
        }
    }
}

/// One opened lighting controller.
public final class LightingController {
    let device: IOHIDDevice
    public private(set) var info: ControllerInfo?
    private var sessionPrepared = false

    init(device: IOHIDDevice) { self.device = device }

    public var productName: String {
        (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Monitor"
    }

    func open() throws {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw LightingError.io("open", result) }
    }

    func close() { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

    private func setFeature(_ report: [UInt8], step: String) throws {
        let result = report.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(report[0]), buffer.baseAddress!, buffer.count)
        }
        guard result == kIOReturnSuccess else { throw LightingError.io(step, result) }
    }

    private func getFeature() throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: ControllerIdentity.reportLength)
        var length = CFIndex(buffer.count)
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(ControllerIdentity.reportID), pointer.baseAddress!, &length)
        }
        guard result == kIOReturnSuccess else { throw LightingError.io("read info", result) }
        return Array(buffer.prefix(length))
    }

    /// Read-only identity query (SetFeature 0x60, then GetFeature).
    @discardableResult
    public func readInfo() throws -> ControllerInfo {
        try setFeature(ReportBuilder.queryInfo(), step: "query info")
        guard let parsed = ControllerInfo(report: try getFeature()) else { throw LightingError.badReply }
        info = parsed
        return parsed
    }

    /// Sends an effect: identify, one-time session setup, effect, apply.
    public func apply(_ settings: LightingSettings) throws {
        if !sessionPrepared {
            let info = try readInfo()
            guard info.isFOSeries else { throw LightingError.unsupportedFirmware(info.firmwareVersion) }
            try setFeature(ReportBuilder.foSeriesReset(), step: "reset")
            try setFeature(ReportBuilder.apply(), step: "apply")
            try setFeature(ReportBuilder.disableStripStreaming(), step: "strip control")
            sessionPrepared = true
        }
        try setFeature(ReportBuilder.effect(settings), step: "effect")
        try setFeature(ReportBuilder.apply(), step: "apply")
    }
}

/// Finds monitor lighting controllers and tracks hot-plug.
@MainActor
public final class LightingControllerBrowser {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    public private(set) var controllers: [LightingController] = []
    public var onChange: (() -> Void)?

    public init() {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: ControllerIdentity.vendorID,
            kIOHIDProductIDKey: ControllerIdentity.productID,
            kIOHIDPrimaryUsagePageKey: ControllerIdentity.usagePage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    }

    /// Starts watching on the main run loop; callbacks update `controllers`.
    public func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            let browser = Unmanaged<LightingControllerBrowser>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated { browser.added(device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            let browser = Unmanaged<LightingControllerBrowser>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated { browser.removed(device) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// One-shot synchronous enumeration (for the CLI).
    public func enumerate() -> [LightingController] {
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        for device in devices { added(device) }
        return controllers
    }

    private func added(_ device: IOHIDDevice) {
        guard !controllers.contains(where: { $0.device == device }) else { return }
        let controller = LightingController(device: device)
        guard (try? controller.open()) != nil else { return }
        controllers.append(controller)
        onChange?()
    }

    private func removed(_ device: IOHIDDevice) {
        controllers.removeAll { $0.device == device }
        onChange?()
    }
}
