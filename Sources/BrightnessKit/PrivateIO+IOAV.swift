import Darwin
import Foundation
import IOKit
import os
#if !CANDELA_MAS
import CandelaPrivateIO
#endif

#if CANDELA_MAS
enum IOAVSymbols {
    static var isReady: Bool { false }
}
#else
extension PrivateSymbols {
    typealias IOAVCreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> UnsafeRawPointer?
    typealias IOAVI2CFn = @convention(c) (
        UnsafeRawPointer?,
        UInt32,
        UInt32,
        UnsafeMutableRawPointer?,
        UInt32
    ) -> IOReturn

    /// RTLD_DEFAULT first, then CoreDisplay. Never `IOAVServiceCreate`.
    static let ioavCreateWithService: IOAVCreateWithServiceFn? = IOAVLoader.load("IOAVServiceCreateWithService")
    static let ioavReadI2C: IOAVI2CFn? = IOAVLoader.load("IOAVServiceReadI2C")
    static let ioavWriteI2C: IOAVI2CFn? = IOAVLoader.load("IOAVServiceWriteI2C")

    static var ioavAvailable: Bool {
        ioavCreateWithService != nil && ioavReadI2C != nil && ioavWriteI2C != nil
    }
}

/// Create-rule retain + I²C helpers. Chip address is always `0x37`.
enum IOAVSymbols {
    static var isReady: Bool { PrivateSymbols.ioavAvailable }

    static func createService(from proxy: io_service_t) -> AnyObject? {
        guard let create = PrivateSymbols.ioavCreateWithService,
              let raw = create(kCFAllocatorDefault, proxy)
        else {
            return nil
        }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeRetainedValue()
    }

    static func writeI2C(service: AnyObject, dataAddress: UInt32, bytes: [UInt8]) -> IOReturn {
        guard let write = PrivateSymbols.ioavWriteI2C else { return kIOReturnUnsupported }
        var packet = bytes
        let count = UInt32(packet.count)
        return packet.withUnsafeMutableBytes { buffer in
            write(
                Unmanaged.passUnretained(service).toOpaque(),
                0x37,
                dataAddress,
                buffer.baseAddress,
                count
            )
        }
    }

    static func readI2C(service: AnyObject, offset: UInt32, count: Int) -> (IOReturn, [UInt8]) {
        guard let read = PrivateSymbols.ioavReadI2C else { return (kIOReturnUnsupported, []) }
        var reply = [UInt8](repeating: 0, count: count)
        let status = reply.withUnsafeMutableBytes { buffer in
            read(
                Unmanaged.passUnretained(service).toOpaque(),
                0x37,
                offset,
                buffer.baseAddress,
                UInt32(count)
            )
        }
        return (status, reply)
    }
}

private enum IOAVLoader {
    private static let log = Logger(subsystem: "app.candela.macos", category: "ddc")
    private static var didLogMissing = false

    static func load<T>(_ name: String) -> T? {
        #if CANDELA_GAMMA_ONLY
        return nil
        #else
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {
            return unsafeBitCast(symbol, to: T.self)
        }
        for path in [
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            "/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay",
        ] {
            if let handle = dlopen(path, RTLD_LAZY), let symbol = dlsym(handle, name) {
                return unsafeBitCast(symbol, to: T.self)
            }
        }
        if !didLogMissing {
            didLogMissing = true
            log.error("dlsym \(name, privacy: .public) failed; Arm64 DDC unavailable")
        }
        return nil
        #endif
    }
}
#endif
