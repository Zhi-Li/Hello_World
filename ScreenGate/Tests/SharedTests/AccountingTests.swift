import XCTest
import Shared
import Policy

final class AccountingTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return value
    }
    private func date(_ month: Int = 10, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day,
            hour: hour, minute: minute, second: second))!
    }
    private func record(_ ledger: inout ScreenTimeLedger, usage: inout [String: Double],
                        at start: Date, seconds: Int, paused: Bool = false, stopped: Bool = false,
                        settings: GateSettings = GateSettings()) {
        for i in 0..<seconds {
            ledger.record(from: start.addingTimeInterval(Double(i)),
                to: start.addingTimeInterval(Double(i + 1)), elapsed: 1, active: true,
                paused: paused, stopped: stopped, settings: settings, allowanceUsage: &usage, calendar: calendar)
        }
    }
    func testSchoolHoursAreRecordedWithoutConsumingAllowance() throws {
        var ledger = ScreenTimeLedger(), usage: [String: Double] = [:]
        record(&ledger, usage: &usage, at: date(10, 12, 10), seconds: 12)
        XCTAssertEqual(ledger.totals["2026-10-12"], 12)
        XCTAssertEqual(usage["2026-10-12"] ?? 0, 0)
    }
    func testBlockedUsageKeepsCountingAndAllowanceResetPreservesCalendar() throws {
        var ledger = ScreenTimeLedger(), usage = ["2026-10-15": 60.0]
        let settings = GateSettings(dailyLimitMinutes: 1)
        XCTAssertEqual(sg_should_block(usage["2026-10-15"]!, 60, 1, 0, 0), 1)
        record(&ledger, usage: &usage, at: date(10, 15, 20), seconds: 5, settings: settings)
        XCTAssertEqual(usage["2026-10-15"], 65)
        XCTAssertEqual(ledger.totals["2026-10-15"], 5)
        usage["2026-10-15"] = 0
        XCTAssertEqual(try ledger.history(for: "2026-10").days.first?.totalSeconds, 5)
    }
    func testPauseRecordsTotalsAndStopEndsRecording() {
        var ledger = ScreenTimeLedger(), usage: [String: Double] = [:]
        record(&ledger, usage: &usage, at: date(10, 15, 20), seconds: 10, paused: true)
        XCTAssertEqual(ledger.totals["2026-10-15"], 10)
        XCTAssertEqual(usage["2026-10-15"] ?? 0, 0)
        record(&ledger, usage: &usage, at: date(10, 16, 20), seconds: 10, stopped: true)
        XCTAssertNil(ledger.totals["2026-10-16"])
    }
    func testInactiveScreensSleepGapsAndClockJumpsAreNotCounted() {
        var ledger = ScreenTimeLedger(), usage: [String: Double] = [:]
        let start = date(10, 15, 20)
        for (elapsed, wall, active) in [(1.0, 1.0, false), (3600.0, 3600.0, true), (1.0, 60.0, true)] {
            ledger.record(from: start, to: start.addingTimeInterval(wall), elapsed: elapsed,
                active: active, paused: false, stopped: false, settings: GateSettings(),
                allowanceUsage: &usage, calendar: calendar)
        }
        XCTAssertEqual(ledger.totals["2026-10-15"], 0)
        XCTAssertTrue(usage.isEmpty)
    }
    func testMidnightSplitsBothCountersAndExpiresBonus() throws {
        var ledger = ScreenTimeLedger(), usage: [String: Double] = [:]
        let start = date(10, 15, 23, 59, 59), end = start.addingTimeInterval(2)
        try ledger.extend(minutes: 30, baseMinutes: 90, on: start, calendar: calendar)
        ledger.record(from: start, to: end, elapsed: 2, active: true, paused: false,
            stopped: false, settings: GateSettings(), allowanceUsage: &usage, calendar: calendar)
        XCTAssertEqual(ledger.totals["2026-10-15"], 1)
        XCTAssertEqual(ledger.totals["2026-10-16"], 1)
        XCTAssertEqual(usage["2026-10-15"], 1)
        XCTAssertEqual(usage["2026-10-16"], 1)
        XCTAssertEqual(ledger.effectiveLimit(baseMinutes: 90, on: start, calendar: calendar), 120)
        XCTAssertEqual(ledger.effectiveLimit(baseMinutes: 90, on: end, calendar: calendar), 90)
    }
    func testSchoolBoundaryOnlyChargesAfterSchoolPortion() {
        var ledger = ScreenTimeLedger(), usage: [String: Double] = [:]
        let start = date(10, 12, 15, 29, 59)
        ledger.record(from: start, to: start.addingTimeInterval(2), elapsed: 2, active: true,
            paused: false, stopped: false, settings: GateSettings(), allowanceUsage: &usage, calendar: calendar)
        XCTAssertEqual(ledger.totals["2026-10-12"], 2)
        XCTAssertEqual(usage["2026-10-12"], 1)
    }
    func testDaylightSavingClockChangeUsesElapsedTime() {
        var ledger = ScreenTimeLedger(), usage: [String: Double] = [:]
        let start = date(10, 4, 1, 59, 59), end = start.addingTimeInterval(2)
        XCTAssertEqual(calendar.component(.hour, from: end), 3)
        ledger.record(from: start, to: end, elapsed: 2, active: true, paused: false,
            stopped: false, settings: GateSettings(), allowanceUsage: &usage, calendar: calendar)
        XCTAssertEqual(ledger.totals["2026-10-04"], 2)
        XCTAssertEqual(usage["2026-10-04"], 2)
    }
    func testExtensionUnblocksWithoutResetAndPersistsAcrossRestart() throws {
        var ledger = ScreenTimeLedger()
        let now = date(10, 15, 20)
        let used = 65.0, base = 1
        XCTAssertEqual(sg_should_block(used, Double(base * 60), 1, 0, 0), 1)
        try ledger.extend(minutes: 15, baseMinutes: base, on: now, calendar: calendar)
        let restored = try JSONDecoder().decode(ScreenTimeLedger.self, from: JSONEncoder().encode(ledger))
        try restored.validate()
        XCTAssertEqual(restored.extraMinutes(on: now, calendar: calendar), 15)
        XCTAssertEqual(sg_should_block(used, Double(restored.effectiveLimit(baseMinutes: base, on: now, calendar: calendar) * 60), 1, 0, 0), 0)
        XCTAssertEqual(restored.effectiveLimit(baseMinutes: base, on: date(10, 16, 0), calendar: calendar), base)
    }
    func testRepeatedExtensionsAndInvalidAmounts() throws {
        var ledger = ScreenTimeLedger()
        let now = date(10, 15, 20)
        try ledger.extend(minutes: 15, baseMinutes: 90, on: now, calendar: calendar)
        try ledger.extend(minutes: 30, baseMinutes: 90, on: now, calendar: calendar)
        for amount in [0, -1, 1440, Int.max] {
            XCTAssertThrowsError(try ledger.extend(minutes: amount, baseMinutes: 90, on: now, calendar: calendar))
        }
        XCTAssertEqual(ledger.effectiveLimit(baseMinutes: 90, on: now, calendar: calendar), 135)
    }
    func testLegacyHistoryIsPreservedAndNotPresentedAsFullDayTime() throws {
        var ledger = ScreenTimeLedger(legacyUsage: ["2026-09-30": 80, "2026-10-14": 120])
        let old = try XCTUnwrap(ledger.history(for: "2026-10").days.first)
        XCTAssertNil(old.totalSeconds); XCTAssertEqual(old.legacyAfterSchoolSeconds, 120)
        var usage: [String: Double] = [:]
        record(&ledger, usage: &usage, at: date(10, 15, 20), seconds: 3)
        let history = try ledger.history(for: "2026-10")
        XCTAssertEqual(history.days.map(\.day), ["2026-10-14", "2026-10-15"])
        XCTAssertEqual(history.days.last?.totalSeconds, 3)
        XCTAssertThrowsError(try ledger.history(for: "2026-13"))
        XCTAssertThrowsError(try ledger.history(for: "2026-10-15"))
    }
    func testHistoryAndTodayExtensionSurviveWireRoundTrip() throws {
        var ledger = ScreenTimeLedger(), usage: [String: Double] = [:]
        record(&ledger, usage: &usage, at: date(10, 15, 20), seconds: 3)
        let request = GateRequest("extend", token: "owner", extraMinutes: 30, day: "2026-10-15")
        let decodedRequest = try JSONDecoder().decode(GateRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decodedRequest.extraMinutes, 30); XCTAssertEqual(decodedRequest.day, "2026-10-15")
        let response = GateResponse(ok: true, history: try ledger.history(for: "2026-10"))
        let decodedResponse = try JSONDecoder().decode(GateResponse.self, from: JSONEncoder().encode(response))
        XCTAssertEqual(decodedResponse.history?.days.first?.totalSeconds, 3)
    }
}
