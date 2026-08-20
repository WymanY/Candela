import BrightnessKit
import DisplayCore
import TestSupport
import XCTest

final class DisplayIOBoxTests: XCTestCase {
    func testMailboxStoresBrightnessWithoutIO() async {
        let snapshot = FakeSnapshots.dellUSBC()
        let box = DisplayIOBox(snapshot: snapshot)
        box.setBrightness(0.42)
        let value = await box.currentBrightness()
        XCTAssertEqual(value, 0.42, accuracy: 0.000_1)
        XCTAssertGreaterThan(DisplayIOBox.ioavServiceRefSize, 0)
    }

    func testMailboxStoresVolumeAndMute() async {
        let box = DisplayIOBox(snapshot: FakeSnapshots.dellUSBC())
        box.setVolume(0.1)
        box.setMuted(true)
        let volume = await box.currentVolume()
        let muted = await box.isMuted()
        XCTAssertEqual(volume, 0.1, accuracy: 0.000_1)
        XCTAssertTrue(muted)
    }

    func testMailboxConsumeOneSetOneWrite() async throws {
        let sink = RecordingBrightnessSink()
        let box = DisplayIOBox(snapshot: FakeSnapshots.hdmiTV(), brightnessWriter: sink)
        box.setBrightness(0.5)
        try await Self.waitPastSliderHold()
        XCTAssertEqual(sink.writes.count, 1)
        XCTAssertEqual(sink.writes[0], 0.5, accuracy: 0.000_1)
        try await Self.waitPastSliderHold()
        XCTAssertEqual(sink.writes.count, 1)
        let stamped = await box.debugLastDDCStamped()
        XCTAssertFalse(stamped)
    }

    func testMailboxCoalescesSetsDuringHold() async throws {
        let sink = RecordingBrightnessSink()
        let box = DisplayIOBox(snapshot: FakeSnapshots.hdmiTV(), brightnessWriter: sink)
        box.setBrightness(0.2)
        box.setBrightness(0.8)
        try await Self.waitPastSliderHold()
        XCTAssertEqual(sink.writes.count, 1)
        XCTAssertEqual(sink.writes[0], 0.8, accuracy: 0.000_1)
        try await Self.waitPastSliderHold()
        XCTAssertEqual(sink.writes.count, 1)
    }

    func testLiveFailSwitchesDisplayServicesToGamma() async throws {
        let sink = FailingBrightnessSink()
        let box = DisplayIOBox(snapshot: FakeSnapshots.builtIn(), brightnessWriter: sink)
        box.setBrightness(0.1)
        try await Self.waitPastSliderHold()
        box.setBrightness(0.2)
        try await Self.waitPastSliderHold()
        box.setBrightness(0.3)
        try await Self.waitPastSliderHold()
        let caps = await box.currentBrightnessCapabilities()
        XCTAssertEqual(caps.backend, .softwareGamma)
        XCTAssertEqual(caps.notes, "!")
        XCTAssertGreaterThanOrEqual(sink.writes, 3)
    }

    func testFakeSnapshotProbeDoesNotUseHardware() async {
        let box = DisplayIOBox(snapshot: FakeSnapshots.dellUSBC())
        let caps = await box.probeBrightness(kind: .genericExternal)
        XCTAssertEqual(caps.backend, .ddc)
        XCTAssertEqual(caps.current, 0.50, accuracy: 0.000_1)
    }

    func testLiveBrightnessSampleSkipsFakeHardware() async {
        let box = DisplayIOBox(snapshot: FakeSnapshots.dellUSBC())
        let live = await box.sampleLiveBrightness()
        XCTAssertNil(live)
    }

    func testLiveBrightnessSampleSkipsPendingMailboxWrite() async {
        let box = DisplayIOBox(snapshot: FakeSnapshots.hdmiTV(), brightnessWriter: RecordingBrightnessSink())
        box.setBrightness(0.33)
        let live = await box.sampleLiveBrightness()
        XCTAssertNil(live)
    }

    private static func waitPastSliderHold() async throws {
        let ns = UInt64(BrightnessTiming.sliderHoldMilliseconds + 120) * 1_000_000
        try await Task.sleep(nanoseconds: ns)
    }
}

private final class RecordingBrightnessSink: BrightnessWriting {
    private let lock = NSLock()
    private var storage: [Double] = []

    var writes: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func writeBrightness(_ value: Double) -> Bool {
        lock.lock()
        storage.append(value)
        lock.unlock()
        return true
    }
}

private final class FailingBrightnessSink: BrightnessWriting {
    private let lock = NSLock()
    private var count = 0

    var writes: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func writeBrightness(_ value: Double) -> Bool {
        _ = value
        lock.lock()
        count += 1
        lock.unlock()
        return false
    }
}
