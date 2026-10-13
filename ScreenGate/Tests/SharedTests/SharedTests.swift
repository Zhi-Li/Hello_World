import XCTest
import Shared
import Policy

final class SharedTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Australia/Melbourne")!; return c
    }
    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    func testDefaultScheduleAndBoundaries() throws {
        let settings = GateSettings(); try settings.validate()
        XCTAssertEqual(settings.mode(at: date(12, 8, 59), calendar: calendar), .afterSchool)
        XCTAssertEqual(settings.mode(at: date(12, 9, 0), calendar: calendar), .school)
        XCTAssertEqual(settings.mode(at: date(12, 15, 29), calendar: calendar), .school)
        XCTAssertEqual(settings.mode(at: date(12, 15, 30), calendar: calendar), .afterSchool)
        XCTAssertEqual(settings.mode(at: date(11, 10, 0), calendar: calendar), .afterSchool)
    }
    func testOvernightUsesStartingWeekday() throws {
        let settings = GateSettings(windows: [TimeWindow(mode: .afterSchool, weekdays: [5], startMinute: 1320, endMinute: 120)])
        try settings.validate()
        XCTAssertEqual(settings.mode(at: date(16, 22, 0), calendar: calendar), .afterSchool)
        XCTAssertEqual(settings.mode(at: date(17, 1, 59), calendar: calendar), .afterSchool)
        XCTAssertEqual(settings.mode(at: date(17, 2, 0), calendar: calendar), .school)
    }
    func testSchoolPriorityIndependentOfWindowOrder() {
        let school = TimeWindow(mode: .school, weekdays: [1], startMinute: 600, endMinute: 660)
        let after = TimeWindow(mode: .afterSchool, weekdays: [1], startMinute: 0, endMinute: 0, allDay: true)
        for windows in [[school, after], [after, school]] {
            XCTAssertEqual(GateSettings(windows: windows).mode(at: date(12, 10, 30), calendar: calendar), .school)
        }
    }
    func testInvalidUserSettingsAreRejectedBeforeNativeConversion() {
        XCTAssertThrowsError(try GateSettings(dailyLimitMinutes: 0).validate())
        XCTAssertThrowsError(try GateSettings(dailyLimitMinutes: 1441).validate())
        XCTAssertThrowsError(try GateSettings(windows: [TimeWindow(mode: .school, weekdays: [-1], startMinute: 0, endMinute: 100)]).validate())
        XCTAssertThrowsError(try GateSettings(windows: [TimeWindow(mode: .school, weekdays: [1], startMinute: 100, endMinute: 100)]).validate())
        XCTAssertThrowsError(try GateSettings(windows: [TimeWindow(mode: .school, weekdays: [], startMinute: 0, endMinute: 100)]).validate())
    }
    func testRequestRoundTripPreservesUnicodePasswordAndSchedule() throws {
        let request = GateRequest("save", token: "sample", password: "测试密码 🔒", settings: GateSettings())
        let result = try JSONDecoder().decode(GateRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(result.password, request.password); XCTAssertEqual(result.settings, request.settings)
    }
    func testOwnerStatusResponsePreservesRestrictionAndRestorationError() throws {
        let status = GateStatus(settings: GateSettings(dailyLimitMinutes: 60), usedSeconds: 3600,
            mode: .afterSchool, paused: false, stopped: false, blocked: true, active: true,
            networkError: "Restoration will retry", day: "2026-10-13")
        let response = GateResponse(ok: true, status: status)
        let decoded = try JSONDecoder().decode(GateResponse.self, from: JSONEncoder().encode(response))
        let received = try XCTUnwrap(decoded.status)
        XCTAssertTrue(decoded.ok); XCTAssertTrue(received.blocked)
        XCTAssertEqual(received.usedSeconds, 3600)
        XCTAssertEqual(received.settings.dailyLimitMinutes, 60)
        XCTAssertEqual(received.networkError, status.networkError)
        XCTAssertEqual(received.day, status.day)
    }
    func testLimitDoesNotAffectSchoolPausedOrStoppedModes() {
        XCTAssertEqual(sg_should_block(600, 600, 1, 0, 0), 1)
        XCTAssertEqual(sg_should_block(600, 600, 0, 0, 0), 0)
        XCTAssertEqual(sg_should_block(600, 600, 1, 1, 0), 0)
        XCTAssertEqual(sg_should_block(600, 600, 1, 0, 1), 0)
    }
    func testSleepGapDoesNotConsumeAllowance() {
        XCTAssertEqual(sg_accumulate(50, 3600, 1, 1, 0, 0), 50)
        XCTAssertEqual(sg_accumulate(50, 1, 1, 1, 0, 0), 51)
    }
}
