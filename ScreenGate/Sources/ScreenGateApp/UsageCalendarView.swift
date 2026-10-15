import SwiftUI
import Shared

@MainActor struct TodayAllowanceExtension: View {
    @EnvironmentObject var model: AppModel
    @State private var minutes = 30
    private var remaining: Int { max(0, 1440 - (model.status?.effectiveLimitMinutes ?? 1440)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Extra time for today", systemImage: "clock.badge.plus").font(.headline)
                Spacer()
                if let status = model.status {
                    Text("\(status.extraMinutes ?? 0) min added · \(status.effectiveLimitMinutes) min total")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                ForEach([15, 30, 60], id: \.self) { amount in
                    Button("+\(amount) min") { model.extendToday(minutes: amount) }
                        .disabled(model.busy || amount > remaining)
                }
                Spacer()
                TextField("Minutes", value: $minutes, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                    .onSubmit { if minutes > 0 && minutes <= remaining { model.extendToday(minutes: minutes) } }
                Button("Add minutes") { model.extendToday(minutes: minutes) }
                    .buttonStyle(.borderedProminent).tint(accent)
                    .disabled(model.busy || minutes < 1 || minutes > remaining)
            }
            Text("Expires at local midnight. Your regular allowance and recorded usage stay the same.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: minutes) { _ in model.interacted() }
    }
}

@MainActor struct UsageCalendarView: View {
    @EnvironmentObject var model: AppModel
    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()
    private var calendar: Calendar { .autoupdatingCurrent }
    private var monthStart: Date { calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth }
    private var month: String { ScreenDates.monthKey(monthStart, calendar: calendar) }
    private var selectedKey: String { ScreenDates.dayKey(selectedDate, calendar: calendar) }
    private var selectedRecord: ScreenTimeDay? { model.history?.days.first { $0.day == selectedKey } }
    private var selectedTotal: Double? {
        if model.status?.day == selectedKey, let total = model.status?.screenSeconds { return total }
        return selectedRecord?.totalSeconds
    }
    private var leadingSpaces: Int {
        (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
    }
    private var daysInMonth: Int { calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0 }
    private var isCurrentMonth: Bool { month == ScreenDates.monthKey(Date(), calendar: calendar) }
    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Screen-time calendar", systemImage: "calendar").font(.headline)
                Spacer()
                Button("Today") { showToday() }.disabled(model.historyLoading)
            }
            HStack(alignment: .top, spacing: 28) {
                calendarGrid.frame(width: 300)
                selectedDayDetails.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.historyError {
                HStack {
                    Text(error).foregroundStyle(.red).font(.caption)
                    Button("Retry") { model.loadHistory(month: month) }
                }
            }
            Text("Counts awake, unlocked screen time, including school hours and offline use. Pausing protection still records totals; Stop & Quit stops recording.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { model.loadHistory(month: month) }
    }
    private var calendarGrid: some View {
        VStack(spacing: 10) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(model.historyLoading).help("Previous month")
                Spacer()
                Text(format(monthStart, pattern: "LLLL yyyy")).font(.subheadline.bold())
                Spacer()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(model.historyLoading || isCurrentMonth).help("Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdays[index]).font(.caption).foregroundStyle(.secondary).frame(height: 20)
                }
                ForEach(0..<(leadingSpaces + daysInMonth), id: \.self) { index in
                    if index < leadingSpaces { Color.clear.frame(height: 32) }
                    else if let date = calendar.date(byAdding: .day, value: index - leadingSpaces, to: monthStart) {
                        dayButton(date)
                    }
                }
            }
        }
    }
    private func dayButton(_ date: Date) -> some View {
        let key = ScreenDates.dayKey(date, calendar: calendar)
        let selected = key == selectedKey
        let today = calendar.isDateInToday(date)
        let hasRecord = model.history?.days.contains(where: { $0.day == key }) == true
        return Button { selectedDate = date; model.interacted() } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))").font(.callout)
                    .fontWeight(today || selected ? .semibold : .regular)
                Circle().fill(hasRecord ? (selected ? Color.white : accent) : Color.clear).frame(width: 3, height: 3)
            }.frame(maxWidth: .infinity).frame(height: 32)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
            .disabled(calendar.startOfDay(for: date) > calendar.startOfDay(for: Date()) || model.historyLoading)
            .accessibilityLabel(format(date, pattern: "EEEE d MMMM yyyy"))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var selectedDayDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(format(selectedDate, pattern: "EEEE, d MMMM yyyy")).font(.subheadline.bold())
            if model.historyLoading {
                ProgressView().controlSize(.small)
                Text("Loading recorded time…").font(.callout).foregroundStyle(.secondary)
            } else if let total = selectedTotal {
                Text(duration(total)).font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Recorded screen time").font(.callout).foregroundStyle(.secondary)
                if let start = model.history?.recordingStartedAt,
                   ScreenDates.dayKey(start, calendar: calendar) == selectedKey {
                    Text("Calendar recording began at \(format(start, pattern: "h:mm a")) on this date.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let earlier = selectedRecord?.legacyAfterSchoolSeconds, earlier > 0 {
                        Text("Earlier after-school record: \(duration(earlier)).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if let earlier = selectedRecord?.legacyAfterSchoolSeconds {
                Text(duration(earlier)).font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("After-school only").font(.callout).foregroundStyle(.secondary)
                Text("The earlier app recorded after-school usage. A full-day total is unavailable for this date.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No recorded time").font(.title3)
                Text("ScreenGate has no recording for this date.").font(.caption).foregroundStyle(.secondary)
            }
            if let start = model.history?.recordingStartedAt {
                Text("Full-day recording since \(format(start, pattern: "d MMM yyyy"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.top, 5)
    }
    private func moveMonth(_ amount: Int) {
        guard let next = calendar.date(byAdding: .month, value: amount, to: monthStart) else { return }
        displayedMonth = next; selectedDate = next
        model.loadHistory(month: ScreenDates.monthKey(next, calendar: calendar))
    }
    private func showToday() {
        displayedMonth = Date(); selectedDate = Date(); model.loadHistory(month: month)
    }
    private func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter(); formatter.calendar = calendar
        formatter.locale = .autoupdatingCurrent; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(pattern)
        return formatter.string(from: date)
    }
    private func duration(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        if value >= 3600 { return "\(value / 3600)h \((value % 3600) / 60)m \(value % 60)s" }
        return "\(value / 60)m \(value % 60)s"
    }
}
