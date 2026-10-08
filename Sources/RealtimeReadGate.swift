import Foundation

/// Rate limit for one kind of real-time read.
///
/// `tryAcquire(now:)` returns true when at least `minInterval` has passed since
/// the last acquired read (or none has happened yet) and records `now` as that
/// read. Thread-safe: streaming ticks can overlap.
final class RealtimeReadGate {
    private let minInterval: TimeInterval
    private var lastReadAt: Date?
    private let lock = NSLock()

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    func tryAcquire(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let last = lastReadAt, now.timeIntervalSince(last) < minInterval {
            return false
        }
        lastReadAt = now
        return true
    }
}
