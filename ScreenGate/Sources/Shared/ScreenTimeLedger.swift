import Foundation
import Policy

public enum ScreenDates {
    public static func dayKey(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public static func monthKey(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        String(dayKey(date, calendar: calendar).prefix(7))
    }
}

public struct ScreenTimeBreakdown: Codable, Sendable {
    public var inSchoolSeconds: Double
    public var afterSchoolSeconds: Double
    public var outsideScheduleSeconds: Double
    public init(inSchoolSeconds: Double = 0, afterSchoolSeconds: Double = 0,
                outsideScheduleSeconds: Double = 0) {
        self.inSchoolSeconds = inSchoolSeconds; self.afterSchoolSeconds = afterSchoolSeconds
        self.outsideScheduleSeconds = outsideScheduleSeconds
    }
    public var totalSeconds: Double { inSchoolSeconds + afterSchoolSeconds + outsideScheduleSeconds }
    public var isValid: Bool {
        [inSchoolSeconds, afterSchoolSeconds, outsideScheduleSeconds, totalSeconds]
            .allSatisfy { $0.isFinite && $0 >= 0 }
    }
    public func unsplitSeconds(in total: Double) -> Double { max(0, total - totalSeconds) }
    mutating func add(_ seconds: Double, category: ScreenTimeCategory) {
        switch category {
        case .inSchool: inSchoolSeconds += seconds
        case .afterSchool: afterSchoolSeconds += seconds
        case .outsideSchedule: outsideScheduleSeconds += seconds
        }
    }
}

public struct ScreenTimeDay: Codable, Sendable, Identifiable {
    public var day: String
    public var totalSeconds: Double?
    public var legacyAfterSchoolSeconds: Double?
    public var breakdown: ScreenTimeBreakdown?
    public var id: String { day }
    public init(day: String, totalSeconds: Double?, legacyAfterSchoolSeconds: Double? = nil,
                breakdown: ScreenTimeBreakdown? = nil) {
        self.day = day; self.totalSeconds = totalSeconds; self.legacyAfterSchoolSeconds = legacyAfterSchoolSeconds
        self.breakdown = breakdown
    }
}

public struct ScreenTimeMonth: Codable, Sendable {
    public var month: String
    public var days: [ScreenTimeDay]
    public var recordingStartedAt: Date?
}

// Persistent measurement is independent of the resettable allowance counter.
public struct ScreenTimeLedger: Codable, Sendable {
    public private(set) var totals: [String: Double] = [:]
    public private(set) var legacyAfterSchool: [String: Double]
    public private(set) var bonuses: [String: Int] = [:]
    public private(set) var recordingStartedAt: Date?
    // Optional so histories saved before split recording decode without losing data.
    public private(set) var breakdowns: [String: ScreenTimeBreakdown]?

    public init(legacyUsage: [String: Double] = [:]) { legacyAfterSchool = legacyUsage }

    public func validate() throws {
        guard totals.values.allSatisfy({ $0.isFinite && $0 >= 0 }),
              legacyAfterSchool.values.allSatisfy({ $0.isFinite && $0 >= 0 }),
              bonuses.values.allSatisfy({ (0...1440).contains($0) }),
              (breakdowns ?? [:]).allSatisfy({ day, split in
                  split.isValid && totals[day] != nil && split.totalSeconds <= (totals[day] ?? 0) + 0.001
              }) else {
            throw GateError("Invalid screen-time history.")
        }
    }

    public mutating func record(from start: Date, to end: Date, elapsed: Double,
                                active: Bool, paused: Bool, stopped: Bool,
                                settings: GateSettings, allowanceUsage: inout [String: Double],
                                calendar: Calendar = .autoupdatingCurrent) {
        guard !stopped else { return }
        if recordingStartedAt == nil { recordingStartedAt = start }
        let endDay = ScreenDates.dayKey(end, calendar: calendar)
        if totals[endDay] == nil { totals[endDay] = 0 }
        var splits = breakdowns ?? [:]
        if splits[endDay] == nil { splits[endDay] = ScreenTimeBreakdown() }
        breakdowns = splits
        let wallDelta = end.timeIntervalSince(start)
        guard active, elapsed.isFinite, elapsed > 0, elapsed <= 2.5,
              wallDelta.isFinite, abs(wallDelta - elapsed) < 2 else { return }
        // Split samples at midnight and schedule boundaries, including DST transitions.
        let steps = max(1, Int(ceil(elapsed / 0.25)))
        for i in 0..<steps {
            let sample = start.addingTimeInterval(wallDelta * (Double(i) + 0.5) / Double(steps))
            let day = ScreenDates.dayKey(sample, calendar: calendar)
            let seconds = elapsed / Double(steps)
            totals[day, default: 0] += seconds
            let category = settings.recordingCategory(at: sample, calendar: calendar)
            splits[day, default: ScreenTimeBreakdown()].add(seconds, category: category)
            // Internet availability never gates measurement or allowance accumulation.
            allowanceUsage[day] = sg_accumulate(allowanceUsage[day] ?? 0, seconds,
                category == .afterSchool ? 1 : 0,
                1, paused ? 1 : 0, 0)
        }
        breakdowns = splits
    }

    public func extraMinutes(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        bonuses[ScreenDates.dayKey(date, calendar: calendar)] ?? 0
    }
    public func effectiveLimit(baseMinutes: Int, on date: Date,
                               calendar: Calendar = .autoupdatingCurrent) -> Int {
        min(1440, baseMinutes + extraMinutes(on: date, calendar: calendar))
    }
    public mutating func extend(minutes: Int, baseMinutes: Int, on date: Date,
                                calendar: Calendar = .autoupdatingCurrent) throws {
        let key = ScreenDates.dayKey(date, calendar: calendar)
        let existing = bonuses[key] ?? 0
        guard (1...1440).contains(baseMinutes), (1...1440).contains(minutes),
              existing >= 0, existing <= 1440 - baseMinutes,
              minutes <= 1440 - baseMinutes - existing else {
            throw GateError("Add a positive number of minutes. Today's total allowance cannot exceed 1,440 minutes.")
        }
        bonuses[key] = existing + minutes
    }

    public func history(for month: String) throws -> ScreenTimeMonth {
        guard month.range(of: "^[0-9]{4}-(0[1-9]|1[0-2])$", options: .regularExpression) != nil else {
            throw GateError("Choose a valid calendar month.")
        }
        let keys = Set(totals.keys).union(legacyAfterSchool.keys)
            .filter { $0.hasPrefix(month + "-") }.sorted()
        return ScreenTimeMonth(month: month, days: keys.map {
            ScreenTimeDay(day: $0, totalSeconds: totals[$0], legacyAfterSchoolSeconds: legacyAfterSchool[$0],
                          breakdown: breakdowns?[$0])
        }, recordingStartedAt: recordingStartedAt)
    }
}
