import Foundation
import IOKit.pwr_mgt

/// Manages system sleep prevention assertions while uploads or long-running pipeline tasks are active.
public final class SleepAssertionManager: @unchecked Sendable {
    public static let shared = SleepAssertionManager()

    private let lock = NSLock()
    private var assertionID: IOPMAssertionID = 0
    private var activeCount: Int = 0

    private init() {}

    /// Acquires a sleep prevention assertion. Safe to call multiple times (ref-counted).
    public func acquire(reason: String = "JellyBoiMediaPipeline: Active upload in progress") {
        lock.lock()
        defer { lock.unlock() }

        activeCount += 1
        guard activeCount == 1 else { return }

        var id: IOPMAssertionID = 0
        let cfReason = reason as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            cfReason,
            &id
        )

        if result == kIOReturnSuccess {
            self.assertionID = id
        }
    }

    /// Releases a sleep prevention assertion.
    public func release() {
        lock.lock()
        defer { lock.unlock() }

        guard activeCount > 0 else { return }
        activeCount -= 1

        if activeCount == 0 && assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }

    /// Forcibly releases any active sleep prevention assertions.
    public func releaseAll() {
        lock.lock()
        defer { lock.unlock() }

        activeCount = 0
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
}
