import BrightnessKit
import XCTest

final class AVServiceScoreTests: XCTestCase {
    /// Hyphenated uppercase IOReg-style UUID from the design/identity table.
    /// Offsets: 0=`10AC` vendor, 4=`4CD1` product LE, 19=`0A22` week/year, 30=`0000` (skip).
    private let exampleUUID = "10AC4CD1-0000-0000-0A22-3C2200000000"

    /// Same vendor/product/week-year; image size `3C22` sits at offset 30.
    private let imageSizeAt30UUID = "10AC4CD1-0000-0000-0A22-0000003C2200"

    func testUuidSliceFollowsDesignOffsets() {
        XCTAssertEqual(AVServiceMatcher.uuidSlice(exampleUUID, offset: AVServiceMatcher.vendorOffset), "10AC")
        XCTAssertEqual(AVServiceMatcher.uuidSlice(exampleUUID, offset: AVServiceMatcher.productOffset), "4CD1")
        XCTAssertEqual(AVServiceMatcher.uuidSlice(exampleUUID, offset: AVServiceMatcher.weekYearOffset), "0A22")
        XCTAssertEqual(AVServiceMatcher.uuidSlice(exampleUUID, offset: AVServiceMatcher.imageSizeOffset), "0000")
        XCTAssertEqual(AVServiceMatcher.uuidSlice(imageSizeAt30UUID, offset: AVServiceMatcher.imageSizeOffset), "3C22")
    }

    func testFragmentBuildersMatchDesignTable() {
        XCTAssertEqual(AVServiceMatcher.vendorFragment(vendorID: 0x10AC), "10AC")
        XCTAssertEqual(AVServiceMatcher.productFragment(productID: 0xD14C), "4CD1")
        XCTAssertEqual(AVServiceMatcher.weekYearFragment(week: 10, year: 2024), "0A22")
        XCTAssertEqual(AVServiceMatcher.weekYearFragment(week: 10, year: 34), "0A22")
        XCTAssertEqual(AVServiceMatcher.imageSizeFragment(horizontalMM: 600, verticalMM: 340), "3C22")
    }

    func testSkip0000Fragments() {
        XCTAssertNil(AVServiceMatcher.vendorFragment(vendorID: 0))
        XCTAssertNil(AVServiceMatcher.vendorFragment(vendorID: 0xFFFF_FFFF))
        XCTAssertNil(AVServiceMatcher.productFragment(productID: 0))
        XCTAssertNil(AVServiceMatcher.weekYearFragment(week: 0, year: 1990))
        XCTAssertNil(AVServiceMatcher.imageSizeFragment(horizontalMM: 0, verticalMM: 0))
    }

    func testExampleUUIDScoresVendorProductWeekYear() {
        let display = AVServiceScoreDisplay(
            vendorID: 0x10AC,
            productID: 0xD14C,
            weekOfManufacture: 10,
            yearOfManufacture: 2024,
            horizontalImageSizeMM: 600,
            verticalImageSizeMM: 340
        )
        let service = AVServiceScoreService(edidUUID: exampleUUID, serviceLocation: 1)
        // Image size is at string offset 24 in this UUID; offset 30 is 0000 and is skipped.
        XCTAssertEqual(AVServiceMatcher.score(display: display, service: service), 3)
    }

    func testImageSizeFragmentAtOffset30() {
        let display = AVServiceScoreDisplay(
            vendorID: 0x10AC,
            productID: 0xD14C,
            weekOfManufacture: 10,
            yearOfManufacture: 2024,
            horizontalImageSizeMM: 600,
            verticalImageSizeMM: 340
        )
        let service = AVServiceScoreService(edidUUID: imageSizeAt30UUID, serviceLocation: 1)
        XCTAssertEqual(AVServiceMatcher.score(display: display, service: service), 4)
    }

    func testLowercaseUUIDStillMatches() {
        let display = AVServiceScoreDisplay(vendorID: 0x10AC, productID: 0xD14C)
        let service = AVServiceScoreService(edidUUID: exampleUUID.lowercased(), serviceLocation: 1)
        XCTAssertEqual(AVServiceMatcher.score(display: display, service: service), 2)
    }

    func testLocationNameAndSerialBonuses() {
        let path = "IOService:/AppleARMPE/arm-io/DCP/dcpext/AVService"
        let display = AVServiceScoreDisplay(
            vendorID: 0x10AC,
            productID: 0xD14C,
            serial: 0x1234_5678,
            location: path,
            productName: "DELL U2723QE"
        )
        let service = AVServiceScoreService(
            edidUUID: exampleUUID,
            ioRegPath: path,
            productName: "dell u2723qe",
            serial: 0x1234_5678,
            serviceLocation: 2
        )
        XCTAssertEqual(AVServiceMatcher.score(display: display, service: service), 2 + 10 + 1 + 1)
    }

    func testZeroSerialDoesNotBonus() {
        let display = AVServiceScoreDisplay(vendorID: 0x10AC, productID: 0xD14C, serial: 0)
        let service = AVServiceScoreService(edidUUID: exampleUUID, serial: 0, serviceLocation: 1)
        XCTAssertEqual(AVServiceMatcher.score(display: display, service: service), 2)
    }

    func testScoreDisplayReadsCoreDisplayKeys() {
        let display = AVServiceMatcher.scoreDisplay(
            vendorID: 0x10AC,
            productID: 0xD14C,
            serial: 0,
            location: "IOService:/port",
            productName: "DELL U2723QE",
            coreDisplay: [
                AVServiceMatcher.weekOfManufactureKey: 10,
                AVServiceMatcher.yearOfManufactureKey: 2024,
                AVServiceMatcher.horizontalImageSizeKey: 600,
                AVServiceMatcher.verticalImageSizeKey: 340,
            ]
        )
        let service = AVServiceScoreService(edidUUID: imageSizeAt30UUID, serviceLocation: 1)
        XCTAssertEqual(AVServiceMatcher.score(display: display, service: service), 4)
    }

    func testAssignGreedyNoReuseDiscardZero() {
        let dell = AVServiceScoreDisplay(
            vendorID: 0x10AC,
            productID: 0xD14C,
            location: "IOService:/dell"
        )
        let lg = AVServiceScoreDisplay(
            vendorID: 0x1E6D,
            productID: 0x5B11,
            location: "IOService:/lg"
        )
        let unknown = AVServiceScoreDisplay(vendorID: 0xAAAA, productID: 0xBBBB)

        let dellService = AVServiceScoreService(
            edidUUID: exampleUUID,
            ioRegPath: "IOService:/dell",
            serviceLocation: 1
        )
        let lgUUID = "1E6D115B-0000-0000-0000-000000000000"
        let lgService = AVServiceScoreService(
            edidUUID: lgUUID,
            ioRegPath: "IOService:/lg",
            serviceLocation: 2
        )

        let assigned = AVServiceMatcher.assign(
            displays: [dell, lg, unknown],
            services: [dellService, lgService]
        )
        XCTAssertEqual(assigned.count, 2)
        XCTAssertEqual(
            assigned.first { $0.displayIndex == 0 },
            AVServiceAssignment(displayIndex: 0, serviceIndex: 0, serviceLocation: 1, score: 12)
        )
        XCTAssertEqual(
            assigned.first { $0.displayIndex == 1 },
            AVServiceAssignment(displayIndex: 1, serviceIndex: 1, serviceLocation: 2, score: 12)
        )
        XCTAssertNil(assigned.first { $0.displayIndex == 2 })
    }

    func testAssignDoesNotReuseServiceLocation() {
        let first = AVServiceScoreDisplay(vendorID: 0x10AC, productID: 0xD14C)
        let second = AVServiceScoreDisplay(vendorID: 0x10AC, productID: 0xD14C)
        let shared = AVServiceScoreService(edidUUID: exampleUUID, serviceLocation: 3)
        let twin = AVServiceScoreService(edidUUID: exampleUUID, serviceLocation: 3)

        let assigned = AVServiceMatcher.assign(displays: [first, second], services: [shared, twin])
        XCTAssertEqual(assigned.count, 1)
        XCTAssertEqual(assigned[0].displayIndex, 0)
        XCTAssertEqual(assigned[0].serviceLocation, 3)
        XCTAssertEqual(assigned[0].score, 2)
    }

    func testHigherScoreWinsTheSharedService() {
        let weak = AVServiceScoreDisplay(vendorID: 0x10AC, productID: 0xD14C)
        let strong = AVServiceScoreDisplay(
            vendorID: 0x10AC,
            productID: 0xD14C,
            location: "IOService:/external-a"
        )
        let shared = AVServiceScoreService(
            edidUUID: exampleUUID,
            ioRegPath: "IOService:/external-a",
            serviceLocation: 1
        )
        let leftover = AVServiceScoreService(
            edidUUID: "FFFF0000-0000-0000-0000-000000000000",
            serviceLocation: 2
        )

        let assigned = AVServiceMatcher.assign(
            displays: [weak, strong],
            services: [shared, leftover]
        )
        XCTAssertEqual(
            assigned.first { $0.displayIndex == 1 },
            AVServiceAssignment(displayIndex: 1, serviceIndex: 0, serviceLocation: 1, score: 12)
        )
        XCTAssertNil(assigned.first { $0.displayIndex == 0 })
    }
}
