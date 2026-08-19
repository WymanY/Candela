import DisplayCore
import TestSupport
import XCTest

final class BrightnessFollowTests: XCTestCase {
    func testSourceIsTheBuiltInPanelAndSkipsVirtualRows() {
        let snapshots = FakeSnapshots.standard()
        let source = BrightnessFollowPolicy.source(in: snapshots)
        XCTAssertEqual(source?.id.persistentKey, snapshots[0].id.persistentKey)
        XCTAssertTrue(BrightnessFollowPolicy.canFollow(in: snapshots))

        let followers = BrightnessFollowPolicy.followers(
            in: snapshots,
            sourceKey: snapshots[0].id.persistentKey
        )
        XCTAssertEqual(
            followers.map(\.id.persistentKey),
            [snapshots[1].id.persistentKey, snapshots[2].id.persistentKey]
        )
        XCTAssertFalse(followers.contains(where: { $0.kind == .virtualUnsupported }))
    }

    func testCannotFollowWithoutAControllableExternal() {
        XCTAssertFalse(BrightnessFollowPolicy.canFollow(in: [FakeSnapshots.builtIn()]))
        XCTAssertFalse(BrightnessFollowPolicy.canFollow(in: [FakeSnapshots.sidecar()]))
        XCTAssertNil(BrightnessFollowPolicy.source(in: [FakeSnapshots.dellUSBC()]))
    }

    func testOffsetsKeepExternalDisplaysRelativelyBrighterOrDimmer() {
        var snapshots = FakeSnapshots.standard()
        snapshots[0].brightness.current = 0.40
        snapshots[1].brightness.current = 0.55
        snapshots[2].brightness.current = 0.20

        let offsets = BrightnessFollowPolicy.captureOffsets(
            snapshots: snapshots,
            sourceKey: snapshots[0].id.persistentKey,
            sourceBrightness: 0.40
        )
        XCTAssertEqual(offsets[snapshots[1].id.persistentKey] ?? 99, 0.15, accuracy: 0.0001)
        XCTAssertEqual(offsets[snapshots[2].id.persistentKey] ?? 99, -0.20, accuracy: 0.0001)

        let plan = BrightnessFollowPolicy.plan(
            snapshots: snapshots,
            sourceKey: snapshots[0].id.persistentKey,
            sourceBrightness: 0.70,
            offsets: offsets
        )
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(
            plan.first(where: { $0.persistentKey == snapshots[1].id.persistentKey })?.brightness ?? -1,
            0.85,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            plan.first(where: { $0.persistentKey == snapshots[2].id.persistentKey })?.brightness ?? -1,
            0.50,
            accuracy: 0.0001
        )
    }

    func testAppliedBrightnessClampsInsteadOfWrapping() {
        XCTAssertEqual(BrightnessFollowPolicy.appliedBrightness(source: 0.95, offset: 0.20), 1.0, accuracy: 0.0001)
        XCTAssertEqual(BrightnessFollowPolicy.appliedBrightness(source: 0.05, offset: -0.20), 0.0, accuracy: 0.0001)
        XCTAssertEqual(BrightnessFollowPolicy.offset(display: 1.4, source: 0.2), 1.0, accuracy: 0.0001)
    }

    func testPlanSkipsDisplaysAlreadyAtTheTarget() {
        var snapshots = FakeSnapshots.standard()
        snapshots[0].brightness.current = 0.50
        snapshots[1].brightness.current = 0.70
        snapshots[2].brightness.current = 0.40
        let offsets = BrightnessFollowPolicy.captureOffsets(
            snapshots: snapshots,
            sourceKey: snapshots[0].id.persistentKey,
            sourceBrightness: 0.50
        )
        let plan = BrightnessFollowPolicy.plan(
            snapshots: snapshots,
            sourceKey: snapshots[0].id.persistentKey,
            sourceBrightness: 0.50,
            offsets: offsets
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testMergingOffsetsKeepsKnownDeltasAndCapturesNewDisplays() {
        var snapshots = FakeSnapshots.standard()
        let dell = snapshots[1].id.persistentKey
        let tv = snapshots[2].id.persistentKey
        snapshots[0].brightness.current = 0.40
        snapshots[1].brightness.current = 0.80
        snapshots[2].brightness.current = 0.10
        let merged = BrightnessFollowPolicy.mergingOffsets(
            existing: [dell: 0.05],
            snapshots: snapshots,
            sourceKey: snapshots[0].id.persistentKey,
            sourceBrightness: 0.40
        )
        XCTAssertEqual(merged[dell] ?? 99, 0.05, accuracy: 0.0001)
        XCTAssertEqual(merged[tv] ?? 99, -0.30, accuracy: 0.0001)
        XCTAssertNil(merged[snapshots[3].id.persistentKey])
    }

    func testFirstSampleDoesNotLookLikeAKeyboardChange() {
        XCTAssertFalse(
            BrightnessFollowPolicy.shouldAdoptSourceChange(
                previous: nil,
                next: 0.42,
                lastSourceWrite: nil
            )
        )
        XCTAssertTrue(
            BrightnessFollowPolicy.shouldAdoptSourceChange(
                previous: 0.42,
                next: 0.50,
                lastSourceWrite: nil
            )
        )
        XCTAssertFalse(
            BrightnessFollowPolicy.shouldAdoptSourceChange(
                previous: 0.42,
                next: 0.43,
                lastSourceWrite: nil
            )
        )
    }

    func testOwnWritesAreIgnoredAsEcho() {
        let now = Date()
        XCTAssertFalse(
            BrightnessFollowPolicy.shouldAdoptSourceChange(
                previous: 0.40,
                next: 0.70,
                lastSourceWrite: now.addingTimeInterval(-0.10),
                now: now
            )
        )
        XCTAssertTrue(
            BrightnessFollowPolicy.shouldAdoptSourceChange(
                previous: 0.40,
                next: 0.70,
                lastSourceWrite: now.addingTimeInterval(-0.50),
                now: now
            )
        )
    }

    func testEngineIgnoresTheFirstSampleThenFollows() {
        var snapshots = FakeSnapshots.standard()
        snapshots[0].brightness.current = 0.40
        snapshots[1].brightness.current = 0.55
        snapshots[2].brightness.current = 0.20
        var engine = BrightnessFollowEngine()
        XCTAssertTrue(engine.ingestLiveSource(snapshots: snapshots, live: 0.40).isEmpty)

        let commands = engine.ingestLiveSource(snapshots: snapshots, live: 0.70)
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(
            commands.first(where: { $0.persistentKey == snapshots[1].id.persistentKey })?.brightness ?? -1,
            0.85,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            commands.first(where: { $0.persistentKey == snapshots[2].id.persistentKey })?.brightness ?? -1,
            0.50,
            accuracy: 0.0001
        )
    }

    func testEngineKeepsOffsetsWhenAFollowerIsDragged() {
        var snapshots = FakeSnapshots.standard()
        snapshots[0].brightness.current = 0.40
        snapshots[1].brightness.current = 0.40
        var engine = BrightnessFollowEngine()
        _ = engine.ingestLiveSource(snapshots: snapshots, live: 0.40)
        engine.noteFollowerWrite(
            key: snapshots[1].id.persistentKey,
            brightness: 0.70,
            sourceBrightness: 0.40
        )
        snapshots[1].brightness.current = 0.70
        let commands = engine.ingestLiveSource(snapshots: snapshots, live: 0.50)
        XCTAssertEqual(
            commands.first(where: { $0.persistentKey == snapshots[1].id.persistentKey })?.brightness ?? -1,
            0.80,
            accuracy: 0.0001
        )
    }

    func testDisabledEngineNeverPlansFollowers() {
        let snapshots = FakeSnapshots.standard()
        var engine = BrightnessFollowEngine(enabled: false)
        _ = engine.ingestLiveSource(snapshots: snapshots, live: 0.40)
        XCTAssertTrue(engine.ingestLiveSource(snapshots: snapshots, live: 0.90).isEmpty)
    }
}
