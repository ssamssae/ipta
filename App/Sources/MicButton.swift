import AppKit
import Foundation
import IOKit
import IOKit.hid

struct MicButtonSpec: Equatable {
    var vendorId: Int
    var productId: Int
    var usagePage: Int
    var usage: Int
    var productName: String

    static let mediaPage = -1

    var label: String {
        if usagePage == Self.mediaPage {
            return productName.isEmpty ? "마이크 미디어 버튼" : productName
        }
        if productName.isEmpty { return "마이크 버튼" }
        return "\(productName) 버튼"
    }

    static func load() -> MicButtonSpec? {
        let d = UserDefaults.standard
        guard d.object(forKey: "malgyeol.micbtn.usage") != nil else { return nil }
        return MicButtonSpec(
            vendorId: d.integer(forKey: "malgyeol.micbtn.vendor"),
            productId: d.integer(forKey: "malgyeol.micbtn.product"),
            usagePage: d.integer(forKey: "malgyeol.micbtn.page"),
            usage: d.integer(forKey: "malgyeol.micbtn.usage"),
            productName: d.string(forKey: "malgyeol.micbtn.name") ?? ""
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(vendorId, forKey: "malgyeol.micbtn.vendor")
        d.set(productId, forKey: "malgyeol.micbtn.product")
        d.set(usagePage, forKey: "malgyeol.micbtn.page")
        d.set(usage, forKey: "malgyeol.micbtn.usage")
        d.set(productName, forKey: "malgyeol.micbtn.name")
    }

    static func clearSaved() {
        let d = UserDefaults.standard
        ["vendor", "product", "page", "usage", "name"].forEach {
            d.removeObject(forKey: "malgyeol.micbtn.\($0)")
        }
    }

    static func isIgnorable(name: String, usagePage: Int) -> Bool {
        if usagePage == 0x07 { return true }
        let n = name.lowercased()
        if n.contains("keyboard") || n.contains("trackpad") || n.contains("키보") { return true }
        if n.contains("magic mouse") || n.contains("apple mouse") { return true }
        return false
    }

    func matches(vendorId: Int, productId: Int, usagePage: Int, usage: Int) -> Bool {
        guard usagePage == self.usagePage, usage == self.usage else { return false }
        if self.vendorId != 0, vendorId != 0, vendorId != self.vendorId { return false }
        if self.productId != 0, productId != 0, productId != self.productId { return false }
        return true
    }
}

enum WirelessMicHint {
    static func looksWireless(_ name: String) -> Bool {
        let n = name.lowercased()
        for key in ["dji", "wireless", "rode", "hollyland", "godox", "transmitter", "receiver", "mic mini", "무선"] {
            if n.contains(key) { return true }
        }
        return false
    }
}

final class MicButtonCenter {
    private var manager: IOHIDManager?
    private var mediaMonitor: Any?
    private var lastFire = Date.distantPast
    private let debounce: TimeInterval = 0.35
    var capturing = false
    var bound: MicButtonSpec?
    var onCapture: ((MicButtonSpec) -> Void)?
    var onToggle: (() -> Void)?

    func start() {
        bound = MicButtonSpec.load()
        startHID()
        startMediaKeys()
    }

    func stop() {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        if let mediaMonitor {
            NSEvent.removeMonitor(mediaMonitor)
        }
        mediaMonitor = nil
    }

    private func startHID() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, nil)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, _, value in
            guard let ctx else { return }
            Unmanaged<MicButtonCenter>.fromOpaque(ctx).takeUnretainedValue().handleHID(value)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
    }

    private func startMediaKeys() {
        mediaMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handleMedia(event)
        }
        _ = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handleMedia(event)
            return event
        }
    }

    private func handleHID(_ value: IOHIDValue) {
        guard IOHIDValueGetIntegerValue(value) != 0 else { return }
        let element = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        guard usage != 0, page == 0x0C || page == 0x09 || page >= 0xFF00 else { return }
        let device = IOHIDElementGetDevice(element)
        let name = stringProp(device, kIOHIDProductKey) ?? ""
        guard !MicButtonSpec.isIgnorable(name: name, usagePage: page) else { return }
        let spec = MicButtonSpec(
            vendorId: intProp(device, kIOHIDVendorIDKey),
            productId: intProp(device, kIOHIDProductIDKey),
            usagePage: page,
            usage: usage,
            productName: name
        )
        consider(spec)
    }

    private func handleMedia(_ event: NSEvent) {
        guard event.subtype.rawValue == 8 else { return }
        let data1 = event.data1
        let key = (data1 & 0xFFFF0000) >> 16
        let flags = data1 & 0x0000FFFF
        let down = ((flags & 0xFF00) >> 8) == 0x0A
        guard down else { return }
        let spec = MicButtonSpec(
            vendorId: 0,
            productId: 0,
            usagePage: MicButtonSpec.mediaPage,
            usage: key,
            productName: "무선 마이크 버튼"
        )
        consider(spec)
    }

    private func consider(_ spec: MicButtonSpec) {
        if capturing {
            capturing = false
            onCapture?(spec)
            return
        }
        guard let bound, bound.matches(vendorId: spec.vendorId, productId: spec.productId, usagePage: spec.usagePage, usage: spec.usage) else {
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastFire) > debounce else { return }
        lastFire = now
        onToggle?()
    }

    private func intProp(_ device: IOHIDDevice?, _ key: String) -> Int {
        guard let device, let raw = IOHIDDeviceGetProperty(device, key as CFString) else { return 0 }
        return (raw as? NSNumber)?.intValue ?? 0
    }

    private func stringProp(_ device: IOHIDDevice?, _ key: String) -> String? {
        guard let device, let raw = IOHIDDeviceGetProperty(device, key as CFString) as? String else { return nil }
        return raw
    }
}
