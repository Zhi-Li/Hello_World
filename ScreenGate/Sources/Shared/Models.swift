import Foundation
import Policy

public enum GateMode: Int, Codable, CaseIterable, Sendable {
    case school = 0, afterSchool = 1
    public var title: String { self == .school ? "In-school" : "After-school" }
}

public struct TimeWindow: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var mode: GateMode
    public var weekdays: [Int] // 0 Sunday ... 6 Saturday
    public var startMinute: Int
    public var endMinute: Int
    public var allDay: Bool
    public init(id: UUID = UUID(), mode: GateMode, weekdays: [Int], startMinute: Int, endMinute: Int, allDay: Bool = false) {
        self.id = id; self.mode = mode; self.weekdays = weekdays
        self.startMinute = startMinute; self.endMinute = endMinute; self.allDay = allDay
    }
    public var native: SGWindow {
        SGWindow(start_minute: UInt16(clamping: startMinute), end_minute: UInt16(clamping: endMinute),
                 weekdays: weekdays.reduce(0) { $0 | UInt8(1 << $1) },
                 mode: UInt8(mode.rawValue), all_day: allDay ? 1 : 0)
    }
}

public struct GateSettings: Codable, Equatable, Sendable {
    public var dailyLimitMinutes: Int
    public var windows: [TimeWindow]
    public init(dailyLimitMinutes: Int = 90, windows: [TimeWindow] = [
        TimeWindow(mode: .school, weekdays: [1,2,3,4,5], startMinute: 540, endMinute: 930),
        TimeWindow(mode: .afterSchool, weekdays: [0,1,2,3,4,5,6], startMinute: 0, endMinute: 0, allDay: true)
    ]) { self.dailyLimitMinutes = dailyLimitMinutes; self.windows = windows }

    public func validate() throws {
        guard (1...1440).contains(dailyLimitMinutes), windows.count <= 40 else {
            throw GateError("Choose a daily limit between 1 and 1,440 minutes and at most 40 windows.")
        }
        for window in windows {
            guard !window.weekdays.isEmpty, Set(window.weekdays).count == window.weekdays.count,
                  window.weekdays.allSatisfy({ (0...6).contains($0) }),
                  (0...1439).contains(window.startMinute), (0...1439).contains(window.endMinute),
                  sg_window_valid(window.native) == 1 else {
                throw GateError("Each window needs valid days and different start/end times, or All day.")
            }
        }
    }

    public func mode(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> GateMode {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let windows = self.windows.map(\.native)
        let result = windows.withUnsafeBufferPointer {
            sg_mode($0.baseAddress, $0.count, Int32((c.weekday ?? 1) - 1), Int32((c.hour ?? 0) * 60 + (c.minute ?? 0)))
        }
        return result == 1 ? .afterSchool : .school
    }
}

public struct GateStatus: Codable, Sendable {
    public var settings: GateSettings
    public var usedSeconds: Double
    public var mode: GateMode
    public var paused: Bool
    public var stopped: Bool
    public var blocked: Bool
    public var active: Bool
    public var networkError: String?
    public var day: String
    public var extraMinutes: Int?
    public var screenSeconds: Double?
    public var recordingStartedAt: Date?
    public var effectiveLimitMinutes: Int { min(1440, settings.dailyLimitMinutes + (extraMinutes ?? 0)) }
    public init(settings: GateSettings, usedSeconds: Double, mode: GateMode, paused: Bool,
                stopped: Bool, blocked: Bool, active: Bool, networkError: String?, day: String,
                extraMinutes: Int? = nil, screenSeconds: Double? = nil, recordingStartedAt: Date? = nil) {
        self.settings = settings; self.usedSeconds = usedSeconds; self.mode = mode
        self.paused = paused; self.stopped = stopped; self.blocked = blocked; self.active = active
        self.networkError = networkError; self.day = day
        self.extraMinutes = extraMinutes; self.screenSeconds = screenSeconds
        self.recordingStartedAt = recordingStartedAt
    }
}

public struct GateRequest: Codable, Sendable {
    public var command: String
    public var token: String?
    public var password: String?
    public var newPassword: String?
    public var settings: GateSettings?
    public var month: String?
    public var extraMinutes: Int?
    public var day: String?
    public init(_ command: String, token: String? = nil, password: String? = nil,
                newPassword: String? = nil, settings: GateSettings? = nil,
                month: String? = nil, extraMinutes: Int? = nil, day: String? = nil) {
        self.command = command; self.token = token; self.password = password
        self.newPassword = newPassword; self.settings = settings
        self.month = month; self.extraMinutes = extraMinutes; self.day = day
    }
}

public struct GateResponse: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var token: String?
    public var status: GateStatus?
    public var unauthorized: Bool?
    public var history: ScreenTimeMonth?
    public var today: TodayScreenTime?
    public init(ok: Bool, error: String? = nil, token: String? = nil, status: GateStatus? = nil,
                unauthorized: Bool? = nil, history: ScreenTimeMonth? = nil, today: TodayScreenTime? = nil) {
        self.ok = ok; self.error = error; self.token = token; self.status = status; self.unauthorized = unauthorized
        self.history = history
        self.today = today
    }
}

public struct GateError: LocalizedError {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum GatePaths {
    public static let directory = "/Library/Application Support/ScreenGate"
    public static let state = directory + "/state.json"
}
