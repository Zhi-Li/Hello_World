import Foundation
import XCTest
import Shared
import ServiceSupport

final class UsageCheckpointTests: XCTestCase {
    private enum Failure: Error { case disk }

    func testOneHourOfLiveUpdatesUses120CheckpointsInsteadOf3600() throws {
        let checkpoint = UsageCheckpoint(at: 0)
        var writes = 0
        for second in 1...3600 {
            checkpoint.markDirty()
            try checkpoint.flush(at: Double(second)) { writes += 1 }
        }
        XCTAssertEqual(writes, 120)
        XCTAssertFalse(checkpoint.isDirty)
    }
    func testCleanStoppedStateDoesNotWriteAndOwnerChangesFlushImmediately() throws {
        let checkpoint = UsageCheckpoint(at: 0)
        var writes = 0
        for second in 1...3600 { try checkpoint.flush(at: Double(second)) { writes += 1 } }
        XCTAssertEqual(writes, 0)
        for second in [3601.0, 3602, 3603] {
            checkpoint.markDirty()
            try checkpoint.flush(at: second, force: true) { writes += 1 }
        }
        XCTAssertEqual(writes, 3)
        try checkpoint.flush(at: 4000, force: true) { writes += 1 }
        XCTAssertEqual(writes, 3)
    }
    func testFailedSaveRetainsDataAndBacksOffUntilRetry() throws {
        let checkpoint = UsageCheckpoint(at: 0)
        checkpoint.markDirty()
        var attempts = 0
        XCTAssertThrowsError(try checkpoint.flush(at: 30) { attempts += 1; throw Failure.disk })
        XCTAssertTrue(checkpoint.isDirty)
        for second in 31...34 { try checkpoint.flush(at: Double(second)) { attempts += 1 } }
        XCTAssertEqual(attempts, 1)
        try checkpoint.flush(at: 35) { attempts += 1 }
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(checkpoint.isDirty)
    }
    func testJournalSaveCoversPendingUsageAndShutdownCanForceEarlierFlush() throws {
        let checkpoint = UsageCheckpoint(at: 0)
        var writes = 0
        checkpoint.markDirty()
        checkpoint.didSave(at: 29) // An immediate network-journal save included this usage.
        try checkpoint.flush(at: 30) { writes += 1 }
        XCTAssertEqual(writes, 0)
        checkpoint.markDirty()
        try checkpoint.flush(at: 31, force: true) { writes += 1 }
        XCTAssertEqual(writes, 1)
        XCTAssertFalse(checkpoint.isDirty)
    }
    func testInactiveAndStoppedLedgerSamplesDoNotKeepMarkingHistoryDirty() {
        var ledger = ScreenTimeLedger(), usage: [String: Double] = [:]
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func record(_ second: Int, stopped: Bool = false, active: Bool = false) -> Bool {
            ledger.record(from: start.addingTimeInterval(Double(second)),
                to: start.addingTimeInterval(Double(second + 1)), elapsed: 1,
                active: active, paused: false, stopped: stopped, settings: GateSettings(),
                allowanceUsage: &usage)
        }
        XCTAssertTrue(record(0)) // Create today's initial zero record once.
        for second in 1...120 { XCTAssertFalse(record(second)) }
        XCTAssertTrue(record(121, active: true))
        XCTAssertFalse(record(122, stopped: true, active: true))
    }
}
