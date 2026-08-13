import CoreGraphics
import Darwin
import Foundation
import os

/// Function pointers only. Never `extern` private names (they would need linking).
enum PrivateSymbols {
    typealias DisplayServicesGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias DisplayServicesSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    typealias CGSFlagFn = @convention(c) (CGDirectDisplayID) -> Int32
    typealias CGSServiceForDisplayNumberFn = @convention(c) (CGDirectDisplayID) -> UInt32
    typealias CoreDisplayCreateInfoDictionaryFn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

    private static let log = Logger(subsystem: "app.candela.macos", category: "private-io")
    private static var loggedMissing = Set<String>()

    private static let displayServicesHandle: UnsafeMutableRawPointer? = {
        #if CANDELA_GAMMA_ONLY
        return nil
        #else
        return open("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices")
        #endif
    }()

    private static let coreDisplayHandle: UnsafeMutableRawPointer? = open(
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"
    )

    private static let skyLightHandle: UnsafeMutableRawPointer? = open(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    )

    static let displayServicesGetBrightness: DisplayServicesGetBrightnessFn? = {
        #if CANDELA_GAMMA_ONLY
        return nil
        #else
        return symbol(displayServicesHandle, name: "DisplayServicesGetBrightness")
        #endif
    }()

    static let displayServicesSetBrightness: DisplayServicesSetBrightnessFn? = {
        #if CANDELA_GAMMA_ONLY
        return nil
        #else
        return symbol(displayServicesHandle, name: "DisplayServicesSetBrightness")
        #endif
    }()

    static let coreDisplayCreateInfoDictionary: CoreDisplayCreateInfoDictionaryFn? = symbol(
        coreDisplayHandle,
        name: "CoreDisplay_DisplayCreateInfoDictionary"
    )

    static let cgsIsHDREnabled: CGSFlagFn? = symbol(skyLightHandle, name: "CGSIsHDREnabled")
    static let cgsIsHDRSupported: CGSFlagFn? = symbol(skyLightHandle, name: "CGSIsHDRSupported")
    static let cgsServiceForDisplayNumber: CGSServiceForDisplayNumberFn? = symbol(
        skyLightHandle,
        name: "CGSServiceForDisplayNumber"
    )

    static var displayServicesAvailable: Bool {
        displayServicesGetBrightness != nil && displayServicesSetBrightness != nil
    }

    /// `nil` if the symbol is missing (treat as pre-macOS 15; do not HDR-skip).
    static func isHDREnabled(_ displayID: CGDirectDisplayID) -> Bool? {
        guard let cgsIsHDREnabled else { return nil }
        return cgsIsHDREnabled(displayID) != 0
    }

    static func isHDRSupported(_ displayID: CGDirectDisplayID) -> Bool? {
        guard let cgsIsHDRSupported else { return nil }
        return cgsIsHDRSupported(displayID) != 0
    }

    private static func open(_ path: String) -> UnsafeMutableRawPointer? {
        guard let handle = dlopen(path, RTLD_LAZY) else {
            logMissing("dlopen \(path)")
            return nil
        }
        return handle
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer?, name: String) -> T? {
        guard let handle, let raw = dlsym(handle, name) else {
            logMissing(name)
            return nil
        }
        return unsafeBitCast(raw, to: T.self)
    }

    private static func logMissing(_ what: String) {
        if loggedMissing.contains(what) { return }
        loggedMissing.insert(what)
        log.error("private symbol unavailable: \(what, privacy: .public)")
    }
}
