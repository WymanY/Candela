import BrightnessKit
import XCTest

final class GammaTableTests: XCTestCase {
    func testScaleGammaHalvesTable() {
        let baseline: [Float] = [0, 0.25, 0.5, 1.0]
        let scaled = scaleGamma(baseline: baseline, t: 0.5)
        XCTAssertEqual(scaled.count, 4)
        XCTAssertEqual(scaled[0], 0, accuracy: 0.000_1)
        XCTAssertEqual(scaled[1], 0.125, accuracy: 0.000_1)
        XCTAssertEqual(scaled[2], 0.25, accuracy: 0.000_1)
        XCTAssertEqual(scaled[3], 0.5, accuracy: 0.000_1)
    }

    func testScaleGammaIdentityAndZero() {
        let baseline: [Float] = [0.2, 0.8]
        XCTAssertEqual(scaleGamma(baseline: baseline, t: 1), baseline)
        XCTAssertEqual(scaleGamma(baseline: baseline, t: 0), [0, 0])
    }

    func testReconstructBaselineInvertsLeftoverDim() {
        let original: [Float] = [0, 0.5, 1]
        let leftover = scaleGamma(baseline: original, t: 0.5)
        let recovered = reconstructGammaBaseline(current: leftover, measuredT: 0.5)
        XCTAssertEqual(recovered[0], 0, accuracy: 0.000_1)
        XCTAssertEqual(recovered[1], 0.5, accuracy: 0.000_1)
        XCTAssertEqual(recovered[2], 1, accuracy: 0.000_1)
    }

    func testLaunchRepairWritesLastWhenRestoreOn() {
        XCTAssertEqual(
            gammaLaunchRepairTarget(measuredT: 1.0, lastBrightness: 0.7, restoreOnReconnect: true),
            0.7
        )
        XCTAssertEqual(
            gammaLaunchRepairTarget(measuredT: 0.4, lastBrightness: nil, restoreOnReconnect: true),
            1.0
        )
        XCTAssertNil(
            gammaLaunchRepairTarget(measuredT: 0.7, lastBrightness: 0.7, restoreOnReconnect: true)
        )
        XCTAssertEqual(
            gammaLaunchRepairTarget(measuredT: 0.4, lastBrightness: 0.7, restoreOnReconnect: false),
            1.0
        )
    }

    func testGammaPeak() {
        XCTAssertEqual(gammaTablePeak([0.1, 0.9, 0.3]), 0.9)
        XCTAssertEqual(gammaTablePeak([]), 0)
    }
}
