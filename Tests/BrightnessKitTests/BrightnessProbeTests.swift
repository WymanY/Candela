import BrightnessKit
import DisplayCore
import XCTest

final class BrightnessProbeTests: XCTestCase {
    func testHDRSkipRequiresNonAppleVendorAndBothFlags() {
        XCTAssertTrue(
            shouldSkipDisplayServicesForHDR(vendorID: 0x10AC, hdrSupported: true, hdrEnabled: true)
        )
        XCTAssertFalse(
            shouldSkipDisplayServicesForHDR(vendorID: appleDisplayVendorID, hdrSupported: true, hdrEnabled: true)
        )
        XCTAssertFalse(
            shouldSkipDisplayServicesForHDR(vendorID: 0x10AC, hdrSupported: nil, hdrEnabled: true)
        )
        XCTAssertFalse(
            shouldSkipDisplayServicesForHDR(vendorID: 0x10AC, hdrSupported: true, hdrEnabled: nil)
        )
        XCTAssertFalse(
            shouldSkipDisplayServicesForHDR(vendorID: 0x10AC, hdrSupported: true, hdrEnabled: false)
        )
        XCTAssertFalse(
            shouldSkipDisplayServicesForHDR(vendorID: 0x10AC, hdrSupported: false, hdrEnabled: true)
        )
    }

    func testProbeWinnerExclusive() {
        XCTAssertEqual(
            probeBrightnessWinner(
                kind: .virtualUnsupported,
                displayServicesSucceeded: true,
                skipDisplayServicesForHDR: false,
                softwareAllowed: true,
                gammaAvailable: true
            ),
            .none
        )
        XCTAssertEqual(
            probeBrightnessWinner(
                kind: .genericExternal,
                displayServicesSucceeded: true,
                skipDisplayServicesForHDR: false,
                softwareAllowed: true,
                gammaAvailable: true
            ),
            .displayServices
        )
        XCTAssertEqual(
            probeBrightnessWinner(
                kind: .genericExternal,
                displayServicesSucceeded: true,
                skipDisplayServicesForHDR: true,
                softwareAllowed: true,
                gammaAvailable: true
            ),
            .softwareGamma
        )
        XCTAssertEqual(
            probeBrightnessWinner(
                kind: .builtIn,
                displayServicesSucceeded: false,
                skipDisplayServicesForHDR: false,
                softwareAllowed: true,
                gammaAvailable: true
            ),
            .softwareGamma
        )
        XCTAssertEqual(
            probeBrightnessWinner(
                kind: .genericExternal,
                displayServicesSucceeded: false,
                skipDisplayServicesForHDR: false,
                softwareAllowed: false,
                gammaAvailable: true
            ),
            .none
        )
        XCTAssertEqual(
            probeBrightnessWinner(
                kind: .genericExternal,
                displayServicesSucceeded: false,
                skipDisplayServicesForHDR: false,
                softwareAllowed: true,
                gammaAvailable: false
            ),
            .none
        )
        XCTAssertEqual(
            probeBrightnessWinner(
                kind: .genericExternal,
                displayServicesSucceeded: false,
                skipDisplayServicesForHDR: false,
                softwareAllowed: true,
                gammaAvailable: true,
                ddcAvailable: true
            ),
            .ddc
        )
        XCTAssertEqual(
            probeBrightnessWinner(
                kind: .builtIn,
                displayServicesSucceeded: false,
                skipDisplayServicesForHDR: false,
                softwareAllowed: true,
                gammaAvailable: true,
                isBuiltin: true,
                ddcAvailable: true
            ),
            .softwareGamma
        )
        XCTAssertEqual(
            probeBrightnessWinner(
                kind: .genericExternal,
                displayServicesSucceeded: true,
                skipDisplayServicesForHDR: false,
                softwareAllowed: true,
                gammaAvailable: true,
                ddcAvailable: true,
                forceDDC: true
            ),
            .displayServices
        )
    }

    func testLiveFailNeverGoesToDDC() {
        XCTAssertNil(
            nextBackendAfterLiveFailure(current: .displayServices, consecutiveFails: 2, softwareAllowed: true)
        )
        XCTAssertEqual(
            nextBackendAfterLiveFailure(current: .displayServices, consecutiveFails: 3, softwareAllowed: true),
            .softwareGamma
        )
        XCTAssertEqual(
            nextBackendAfterLiveFailure(current: .displayServices, consecutiveFails: 3, softwareAllowed: false),
            BrightnessBackendKind.none
        )
        XCTAssertEqual(
            nextBackendAfterLiveFailure(current: .ddc, consecutiveFails: 3, softwareAllowed: true),
            .softwareGamma
        )
        XCTAssertNil(
            nextBackendAfterLiveFailure(current: .softwareGamma, consecutiveFails: 3, softwareAllowed: true)
        )
    }
}
