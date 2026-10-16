import XCTest
import Shared

final class MenuBarSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return value
    }
    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    func testTooltipShowsRecordedHoursMinutesAndSeconds() {
        for (seconds, expected) in [(0.0, "0m 00s"), (61.9, "1m 01s"), (3723.9, "1h 02m 03s")] {
            let summary = TodayScreenTime(day: "2026-10-15", screenSeconds: seconds)
            XCTAssertEqual(summary.tooltip(at: date(15), calendar: calendar), "ScreenGate\nToday's screen time: \(expected)")
        }
        XCTAssertTrue(TodayScreenTime(day: "2026-10-15", screenSeconds: nil)
            .tooltip(at: date(15), calendar: calendar).contains("Not recorded yet"))
        XCTAssertEqual(TodayScreenTime(day: "2026-10-15", screenSeconds: .infinity)
            .tooltip(at: date(15), calendar: calendar), TodayScreenTime.unavailableTooltip)
    }
    func testStaleSnapshotCannotBePresentedAsTodaysTotalAfterMidnight() {
        let summary = TodayScreenTime(day: "2026-10-15", screenSeconds: 3723)
        let text = summary.tooltip(at: date(16, 0), calendar: calendar)
        XCTAssertTrue(text.contains("Updating")); XCTAssertFalse(text.contains("1h 02m"))
    }
    func testReadOnlySummaryWirePayloadContainsNoOwnerData() throws {
        let response = GateResponse(ok: true, today: TodayScreenTime(day: "2026-10-15", screenSeconds: 3723,
            breakdown: ScreenTimeBreakdown(inSchoolSeconds: 3600, afterSchoolSeconds: 123)))
        let data = try JSONEncoder().encode(response)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["ok", "today"])
        let decoded = try JSONDecoder().decode(GateResponse.self, from: data)
        XCTAssertEqual(decoded.today?.screenSeconds, 3723)
        XCTAssertEqual(decoded.today?.breakdown?.inSchoolSeconds, 3600)
        XCTAssertEqual(decoded.today?.breakdown?.afterSchoolSeconds, 123)
        let todayObject = try XCTUnwrap(object["today"] as? [String: Any])
        XCTAssertEqual(Set(todayObject.keys), ["day", "screenSeconds", "breakdown"])
        XCTAssertNil(decoded.status); XCTAssertNil(decoded.history); XCTAssertNil(decoded.token)
        let olderResponse = try JSONDecoder().decode(GateResponse.self, from: Data("{\"ok\":true}".utf8))
        XCTAssertNil(olderResponse.today)
    }
    func testTooltipShowsBothModesAndKeepsEarlierUnsplitTime() {
        let summary = TodayScreenTime(day: "2026-10-15", screenSeconds: 4000,
            breakdown: ScreenTimeBreakdown(inSchoolSeconds: 3600, afterSchoolSeconds: 120))
        let text = summary.tooltip(at: date(15), calendar: calendar)
        XCTAssertTrue(text.contains("Today's screen time: 1h 06m 40s"))
        XCTAssertTrue(text.contains("In-school: 1h 00m 00s"))
        XCTAssertTrue(text.contains("After-school: 2m 00s"))
        XCTAssertTrue(text.contains("Earlier unsplit time: 4m 40s"))
        XCTAssertFalse(text.contains("Outside scheduled modes"))
    }
    func testTooltipIncludesScheduleGapsAndDecodesOlderSummary() throws {
        let summary = TodayScreenTime(day: "2026-10-15", screenSeconds: 60,
            breakdown: ScreenTimeBreakdown(outsideScheduleSeconds: 60))
        let text = summary.tooltip(at: date(15), calendar: calendar)
        XCTAssertTrue(text.contains("In-school: 0m 00s"))
        XCTAssertTrue(text.contains("After-school: 0m 00s"))
        XCTAssertTrue(text.contains("Outside scheduled modes: 1m 00s"))
        let old = try JSONDecoder().decode(TodayScreenTime.self,
            from: Data("{\"day\":\"2026-10-15\",\"screenSeconds\":60}".utf8))
        XCTAssertNil(old.breakdown)
        XCTAssertTrue(old.tooltip(at: date(15), calendar: calendar).contains("Today's screen time: 1m 00s"))
    }
}
