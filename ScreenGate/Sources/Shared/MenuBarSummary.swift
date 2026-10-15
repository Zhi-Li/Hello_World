import Foundation

// The only usage data available without unlocking owner controls.
public struct TodayScreenTime: Codable, Sendable {
    public var day: String
    public var screenSeconds: Double?
    public init(day: String, screenSeconds: Double?) {
        self.day = day; self.screenSeconds = screenSeconds
    }
    public static let unavailableTooltip = "ScreenGate\nToday's screen time: Unavailable"
    public func tooltip(at now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> String {
        guard day == ScreenDates.dayKey(now, calendar: calendar) else {
            return "ScreenGate\nToday's screen time: Updating…"
        }
        guard let seconds = screenSeconds else { return "ScreenGate\nToday's screen time: Not recorded yet" }
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return Self.unavailableTooltip }
        let value = Int(seconds)
        let duration = value >= 3600
            ? String(format: "%dh %02dm %02ds", value / 3600, (value % 3600) / 60, value % 60)
            : String(format: "%dm %02ds", value / 60, value % 60)
        return "ScreenGate\nToday's screen time: \(duration)"
    }
}
