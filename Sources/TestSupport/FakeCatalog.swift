import DisplayCore
import Foundation

public final class FakeCatalog: DisplayCataloging {
    public private(set) var snapshots: [DisplaySnapshot]
    public let updates: AsyncStream<[DisplaySnapshot]>
    private let continuation: AsyncStream<[DisplaySnapshot]>.Continuation
    public private(set) var isRunning = false

    public init(snapshots: [DisplaySnapshot] = FakeSnapshots.standard()) {
        self.snapshots = snapshots
        let stream: (AsyncStream<[DisplaySnapshot]>, AsyncStream<[DisplaySnapshot]>.Continuation)
        stream = AsyncStream<[DisplaySnapshot]>.makeStream()
        self.updates = stream.0
        self.continuation = stream.1
    }

    public func start() {
        isRunning = true
        continuation.yield(snapshots)
    }

    public func stop() {
        isRunning = false
        continuation.finish()
    }

    public func replace(_ snapshots: [DisplaySnapshot]) {
        self.snapshots = snapshots
        if isRunning {
            continuation.yield(snapshots)
        }
    }
}

public final class EmptyCatalog: DisplayCataloging {
    public let snapshots: [DisplaySnapshot] = []
    public let updates: AsyncStream<[DisplaySnapshot]>
    private let continuation: AsyncStream<[DisplaySnapshot]>.Continuation

    public init() {
        let stream = AsyncStream<[DisplaySnapshot]>.makeStream()
        self.updates = stream.0
        self.continuation = stream.1
    }

    public func start() {
        continuation.yield(snapshots)
    }

    public func stop() {
        continuation.finish()
    }
}
