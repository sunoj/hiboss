// Finds the USB lamp by its product string and writes one command line to its serial port.
// Exports: LampPortWriting, USBLampPort (IOKit lookup + non-blocking tty write on its own queue).
// Dependencies: Darwin termios, IOKit serial registry; firmware lives in macos/lamp-firmware.

import Darwin
import Foundation
import IOKit
import IOKit.serial

protocol LampPortWriting: Sendable {
    func send(_ line: String)
    /// Blocks until every line sent so far has been written or dropped.
    func drain()
}

final class USBLampPort: LampPortWriting, @unchecked Sendable {
    static let productName = "HiBoss Lamp"
    private let queue = DispatchQueue(label: "work.hiboss.lamp")
    private let locate: @Sendable () -> String?

    init(locate: @escaping @Sendable () -> String? = { USBLampPort.calloutPath() }) {
        self.locate = locate
    }

    /// Lookup and I/O stay off the main actor: a tty that is mid-unplug can stall `open`.
    /// A missing lamp drops the line; the controller's periodic resend restores the state.
    func send(_ line: String) {
        queue.async { [locate] in
            guard let path = locate() else { return }
            _ = Self.write(line + "\n", to: path)
        }
    }

    func drain() {
        queue.sync {}
    }

    /// Opens without blocking or becoming the controlling tty, writes raw 8N1, and closes.
    @discardableResult
    static func write(_ text: String, to path: String) -> Bool {
        let fd = open(path, O_WRONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var attributes = termios()
        if tcgetattr(fd, &attributes) == 0 {
            cfmakeraw(&attributes)
            attributes.c_cflag |= tcflag_t(CLOCAL)
            cfsetspeed(&attributes, speed_t(B115200))
            tcsetattr(fd, TCSANOW, &attributes)
        }
        let bytes = Array(text.utf8)
        return bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) } == bytes.count
    }

    /// The callout device (`/dev/cu.*`) of the first serial service whose USB ancestor is the lamp.
    static func calloutPath() -> String? {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let product = IORegistryEntrySearchCFProperty(service, kIOServicePlane,
                "USB Product Name" as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? String
            guard product == productName else { continue }
            return IORegistryEntryCreateCFProperty(service, kIOCalloutDeviceKey as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        }
        return nil
    }
}
