import Foundation

public struct NetworkRollingBuffer: Sendable {
    private let maxEventCount: Int
    private let maxRetainedBytes: Int
    private var events: [NetworkEvent]
    private var retainedBytes: Int

    public init(
        maxEventCount: Int = NetworkCapturePolicy.metadataOnly.maxEventCount,
        maxRetainedBytes: Int = NetworkCapturePolicy.metadataOnly.maxRetainedBytes
    ) {
        self.maxEventCount = max(1, maxEventCount)
        self.maxRetainedBytes = max(1, maxRetainedBytes)
        events = []
        retainedBytes = 0
    }

    public mutating func append(_ event: NetworkEvent) {
        events.append(event)
        retainedBytes += event.estimatedByteCount

        while events.count > maxEventCount || (retainedBytes > maxRetainedBytes && events.count > 1) {
            let removed = events.removeFirst()
            retainedBytes -= removed.estimatedByteCount
        }
    }

    public mutating func removeAll() {
        events.removeAll()
        retainedBytes = 0
    }

    public var snapshot: [NetworkEvent] {
        events
    }

    public var totalRetainedBytes: Int {
        retainedBytes
    }
}
