import Foundation

// The only usage data available without unlocking owner controls.
public struct TodayScreenTime: Codable, Sendable {
    public var day: String
    public var screenSeconds: Double?
    public var breakdown: ScreenTimeBreakdown?
    public init(day: String, screenSeconds: Double?, breakdown: ScreenTimeBreakdown? = nil) {
        self.day = day; self.screenSeconds = screenSeconds
        self.breakdown = breakdown
    }
    public static let unavailableTooltip = "ScreenGate\nToday's screen time: Unavailable"
    public func tooltip(at now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> String {
        guard day == ScreenDates.dayKey(now, calendar: calendar) else {
            return "ScreenGate\nToday's screen time: Updating…"
        }
        guard let seconds = screenSeconds else { return "ScreenGate\nToday's screen time: Not recorded yet" }
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return Self.unavailableTooltip }
        var lines = ["ScreenGate", "Today's screen time: \(duration(seconds))"]
        if let split = breakdown, split.isValid, split.totalSeconds <= seconds + 0.001 {
            lines += ["In-school: \(duration(split.inSchoolSeconds))",
                      "After-school: \(duration(split.afterSchoolSeconds))"]
            if split.outsideScheduleSeconds > 0 {
                lines.append("Outside scheduled modes: \(duration(split.outsideScheduleSeconds))")
            }
            if split.unsplitSeconds(in: seconds) >= 1 {
                lines.append("Earlier unsplit time: \(duration(split.unsplitSeconds(in: seconds)))")
            }
        }
        return lines.joined(separator: "\n")
    }
    private func duration(_ seconds: Double) -> String {
        let value = Int(seconds)
        return value >= 3600
            ? String(format: "%dh %02dm %02ds", value / 3600, (value % 3600) / 60, value % 60)
            : String(format: "%dm %02ds", value / 60, value % 60)
    }
}
