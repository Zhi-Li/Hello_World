import SwiftUI
import Shared

let accent = Color(red: 0.21, green: 0.38, blue: 0.86)

@MainActor struct OwnerView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 28)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ScreenGate").font(.title2.bold())
                    Text("A little structure for screen time.").foregroundStyle(.secondary)
                }
                Spacer()
                if model.unlocked { Button { model.lock() } label: { Label("Lock controls", systemImage: "lock.fill") } }
            }.padding(24)
            Divider()
            if model.unlocked { Dashboard() } else { UnlockView() }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.showingQuit) { PasswordSheet(kind: .quit).environmentObject(model) }
        .sheet(isPresented: $model.showingPassword) { PasswordSheet(kind: .change).environmentObject(model) }
    }
}

@MainActor struct UnlockView: View {
    @EnvironmentObject var model: AppModel
    @State private var password = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 56, weight: .light)).foregroundStyle(accent)
            Text("Owner access").font(.largeTitle.bold())
            Text("Enter your password to view usage or change controls.").foregroundStyle(.secondary)
            SecureField("Owner password", text: $password).textFieldStyle(.roundedBorder)
                .focused($focused).onSubmit(unlock).frame(width: 300)
            Button(action: unlock) { Text(model.busy ? "Unlocking…" : "Unlock controls").frame(width: 280) }
                .buttonStyle(.borderedProminent).tint(accent).disabled(model.busy || password.isEmpty)
            if let error = model.error { Text(error).foregroundStyle(.red).frame(maxWidth: 430) }
            Spacer()
            Text("Protection runs independently of this window.").font(.caption).foregroundStyle(.secondary)
            Text("Forgot your password? The Mac administrator can use Recover.command.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(32).frame(maxWidth: .infinity).onAppear { focused = true }
    }
    private func unlock() { model.unlock(password); password = "" }
}

@MainActor struct Dashboard: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmingReset = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let s = model.status {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(s.stopped ? "Protection stopped" : s.paused ? "Protection paused" : s.mode.title,
                                  systemImage: s.paused || s.stopped ? "pause.circle" : "clock.fill")
                                .font(.headline).foregroundStyle(accent)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(duration(s.usedSeconds)).font(.system(size: 42, weight: .semibold, design: .rounded))
                                Text("/ \(s.effectiveLimitMinutes) min today").foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(s.usedSeconds, Double(s.effectiveLimitMinutes * 60)),
                                         total: Double(s.effectiveLimitMinutes * 60)).tint(accent)
                            Text("After-school allowance used").font(.caption).foregroundStyle(.secondary)
                            Text(s.active ? "Screen awake and unlocked" : "Screen sleeping, locked, or logged out")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Divider().frame(height: 115)
                        VStack(alignment: .leading, spacing: 12) {
                            Label(s.blocked ? "Internet blocked" : "Internet available",
                                  systemImage: s.blocked ? "wifi.slash" : "wifi")
                                .font(.headline).foregroundStyle(s.blocked ? Color.orange : Color.green)
                            Text(s.stopped ? "Resume to start protection again." : s.paused ? "Allowance counting is paused." :
                                 s.mode == .school ? "No restrictions during in-school time." : "Internet stops when the daily allowance is used.")
                                .font(.callout).foregroundStyle(.secondary).frame(width: 215, alignment: .leading)
                            Button(s.paused || s.stopped ? "Resume protection" : "Pause & restore internet") {
                                model.action(s.paused || s.stopped ? "resume" : "pause")
                            }.disabled(model.busy)
                        }
                    }.padding(22).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                    if let error = s.networkError { banner(error, color: .orange) }
                }
                if let error = model.error { banner(error, color: .red) }
                if let notice = model.notice { banner(notice, color: .green) }

                TodayAllowanceExtension()
                UsageCalendarView()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Regular daily allowance").font(.headline)
                        Text("Resets at local midnight. Use the controls above to add time for today only.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("Minutes", value: $model.draft.dailyLimitMinutes, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 80)
                    Text("minutes")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Weekly schedule").font(.headline)
                    Text("In-school windows override after-school windows. Outside both, the Mac is unrestricted.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach($model.draft.windows) { $window in
                        WindowEditor(window: $window) { model.draft.windows.removeAll { $0.id == window.id }; model.interacted() }
                    }
                    HStack {
                        Button { add(.school) } label: { Label("Add in-school window", systemImage: "plus") }
                        Button { add(.afterSchool) } label: { Label("Add after-school window", systemImage: "plus") }
                        Spacer()
                        Button("Save changes") { model.save() }.buttonStyle(.borderedProminent).tint(accent).disabled(model.busy)
                    }
                    Text("Overnight windows belong to their starting day. Times follow this Mac's timezone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Button("Reset today's allowance counter…") { confirmingReset = true }
                    Button("Change password…") { model.error = nil; model.showingPassword = true }
                    Spacer()
                    Button("Stop & Quit…") { model.requestQuit() }.foregroundStyle(.red)
                }.disabled(model.busy)
            }.padding(24)
        }
        .onChange(of: model.draft) { _ in model.interacted() }
        .confirmationDialog("Reset today's allowance counter? Calendar history will be kept.", isPresented: $confirmingReset) {
            Button("Reset allowance counter") { model.action("reset") }
        }
    }
    private func add(_ mode: GateMode) {
        model.draft.windows.append(TimeWindow(mode: mode, weekdays: [1,2,3,4,5], startMinute: mode == .school ? 540 : 930, endMinute: mode == .school ? 930 : 1260))
        model.interacted()
    }
    private func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds)); return String(format: "%d:%02d", total / 60, total % 60)
    }
    private func banner(_ text: String, color: Color) -> some View {
        Label(text, systemImage: "info.circle").font(.callout).foregroundStyle(color).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor struct WindowEditor: View {
    @Binding var window: TimeWindow
    var remove: () -> Void
    private let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(window.mode.title, systemImage: window.mode == .school ? "graduationcap" : "house")
                    .font(.subheadline.bold()).foregroundStyle(window.mode == .school ? accent : .purple)
                Spacer()
                Toggle("All day", isOn: $window.allDay).toggleStyle(.checkbox)
                if !window.allDay {
                    TimeField(label: "From", minute: $window.startMinute)
                    TimeField(label: "To", minute: $window.endMinute)
                }
                Button(action: remove) { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Delete window")
            }
            HStack(spacing: 7) {
                ForEach(0..<7) { day in
                    let selected = window.weekdays.contains(day)
                    Button {
                        if selected { window.weekdays.removeAll { $0 == day } }
                        else { window.weekdays.append(day); window.weekdays.sort() }
                    } label: {
                        Text(days[day]).fontWeight(selected ? .semibold : .regular)
                    }.buttonStyle(.bordered).tint(selected ? accent : .gray)
                }
                Spacer()
                if !window.allDay && window.endMinute < window.startMinute {
                    Text("Ends next day").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

@MainActor struct TimeField: View {
    var label: String
    @Binding var minute: Int
    private var date: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        }, set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }
    var body: some View { DatePicker(label, selection: date, displayedComponents: .hourAndMinute).frame(width: 150) }
}

enum PasswordSheetKind: Equatable { case quit, change }
@MainActor struct PasswordSheet: View {
    @EnvironmentObject var model: AppModel
    var kind: PasswordSheetKind
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(kind == .quit ? "Stop protection & quit?" : "Change owner password").font(.title2.bold())
            if kind == .quit {
                Text("Internet will be restored. Protection stays stopped until you open ScreenGate and resume it.").foregroundStyle(.secondary)
            }
            SecureField("Current owner password", text: $current).textFieldStyle(.roundedBorder).onSubmit(submit)
            if kind == .change {
                SecureField("New password (at least 8 characters)", text: $new).textFieldStyle(.roundedBorder)
                SecureField("Confirm new password", text: $confirm).textFieldStyle(.roundedBorder).onSubmit(submit)
            }
            if let error = model.error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { model.showingQuit = false; model.showingPassword = false; model.error = nil }
                    .keyboardShortcut(.cancelAction)
                Button(model.busy ? "Please wait…" : kind == .quit ? "Restore internet & quit" : "Update password", action: submit)
                    .buttonStyle(.borderedProminent).tint(accent).disabled(model.busy || current.isEmpty)
            }
        }.padding(28).frame(width: 430)
    }
    private func submit() {
        guard !model.busy else { return }
        if kind == .quit { model.stopAndQuit(current) }
        else {
            guard new == confirm else { model.error = "The new passwords do not match."; return }
            model.changePassword(current: current, new: new)
        }
    }
}
