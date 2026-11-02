import Foundation

/// Orders overlapping refreshes by when they started, using a counter instead of the
/// wall clock, which can step back and would then reject every later refresh.
struct RefreshOrder {
    private(set) var started = 0
    private(set) var applied = 0

    mutating func begin() -> Int {
        started += 1
        return started
    }

    /// Failures are accepted too, so an older success landing later cannot clear a newer error.
    mutating func accept(_ sequence: Int) -> Bool {
        guard sequence > applied else { return false }
        applied = sequence
        return true
    }
}
