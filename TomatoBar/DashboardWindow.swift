import Charts
import SwiftUI

// MARK: - Root view

struct DashboardWindow: View {
    @ObservedObject private var store = TrackingStore.shared
    @State private var filterProjectIdStr: String = ""

    private var filterProjectId: UUID? { UUID(uuidString: filterProjectIdStr) }

    private var filterOptions: [TBProject] {
        store.projects.filter { $0.status != .archived }
    }

    // MARK: - Session filters

    private var filteredSessions: [TBSession] {
        store.sessions.filter { s in
            guard s.type == .work, s.completed else { return false }
            if let pid = filterProjectId { return s.projectId == pid }
            return true
        }
    }

    private var todaySessions: [TBSession] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return filteredSessions.filter { $0.startedAt >= start && $0.startedAt < end }
    }

    private var weekSessions: [TBSession] {
        guard let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start
        else { return [] }
        return filteredSessions.filter { $0.startedAt >= start }
    }

    private var monthSessions: [TBSession] {
        guard let start = Calendar.current.dateInterval(of: .month, for: Date())?.start
        else { return [] }
        return filteredSessions.filter { $0.startedAt >= start }
    }

    // MARK: - Chart data types

    private struct BreakdownEntry: Identifiable {
        let id: String
        let label: String
        let hours: Double
        let count: Int
    }

    private struct WeekDayEntry: Identifiable {
        let id: Int
        let label: String
        let minutes: Double
        let isToday: Bool
    }

    private struct MonthEntry: Identifiable {
        var id: String { "\(date.timeIntervalSince1970)-\(projectName)" }
        let date: Date
        let projectName: String
        let minutes: Double
    }

    struct SessionLogEntry: Identifiable {
        let id: UUID
        let startedAt: Date
        let endedAt: Date
        let projectName: String
        let areaName: String?
        let notes: String?
    }

    private struct DayGroup: Identifiable {
        let id: Date
        let entries: [SessionLogEntry]
    }

    // MARK: - Computed chart data

    private var breakdownData: [BreakdownEntry] {
        let work = filteredSessions
        if let pid = filterProjectId {
            let areaMap = Dictionary(uniqueKeysWithValues: store.areas(for: pid).map { ($0.id, $0.name) })
            var grouped: [UUID?: [TBSession]] = [:]
            for s in work { grouped[s.areaId, default: []].append(s) }
            return grouped.map { areaId, items in
                BreakdownEntry(
                    id: areaId?.uuidString ?? "unassigned",
                    label: areaId.flatMap { areaMap[$0] } ?? "Unassigned",
                    hours: items.reduce(0.0) { $0 + $1.actualDuration } / 3600,
                    count: items.count
                )
            }.sorted { $0.hours > $1.hours }
        } else {
            let projectMap = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id, $0.name) })
            var grouped: [UUID?: [TBSession]] = [:]
            for s in work { grouped[s.projectId, default: []].append(s) }
            return grouped.map { projectId, items in
                BreakdownEntry(
                    id: projectId?.uuidString ?? "unassigned",
                    label: projectId.flatMap { projectMap[$0] } ?? "Unassigned",
                    hours: items.reduce(0.0) { $0 + $1.actualDuration } / 3600,
                    count: items.count
                )
            }.sorted { $0.hours > $1.hours }
        }
    }

    private var sessionLog: [DayGroup] {
        let cal = Calendar.current
        let projectMap = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id, $0.name) })
        let areaMap = Dictionary(uniqueKeysWithValues: store.areas.map { ($0.id, $0.name) })
        var grouped: [Date: [SessionLogEntry]] = [:]
        for s in filteredSessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            let day = cal.startOfDay(for: s.startedAt)
            grouped[day, default: []].append(SessionLogEntry(
                id: s.id,
                startedAt: s.startedAt,
                endedAt: s.endedAt,
                projectName: s.projectId.flatMap { projectMap[$0] } ?? "Unassigned",
                areaName: s.areaId.flatMap { areaMap[$0] },
                notes: s.notes
            ))
        }
        return grouped.map { day, entries in
            DayGroup(id: day, entries: entries)
        }.sorted { $0.id > $1.id }
    }

    private var weeklyData: [WeekDayEntry] {
        let cal = Calendar.current
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        let grouped = Dictionary(grouping: weekSessions) { cal.startOfDay(for: $0.startedAt) }
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return (0 ..< 7).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: weekInterval.start) else { return nil }
            let items = grouped[day] ?? []
            return WeekDayEntry(
                id: offset,
                label: fmt.string(from: day),
                minutes: items.reduce(0.0) { $0 + $1.actualDuration } / 60,
                isToday: day == today
            )
        }
    }

    private var monthlyData: [MonthEntry] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: Date()) else { return [] }
        let sessions: [TBSession]
        if filterProjectId != nil {
            sessions = monthSessions
        } else {
            sessions = store.sessions.filter { s in
                guard s.type == .work, s.completed else { return false }
                return s.startedAt >= interval.start && s.startedAt < interval.end
            }
        }
        let projectMap = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id, $0.name) })
        struct Key: Hashable { let date: Date; let name: String }
        var acc: [Key: Double] = [:]
        for s in sessions {
            let day = cal.startOfDay(for: s.startedAt)
            let name = s.projectId.flatMap { projectMap[$0] } ?? "Unassigned"
            acc[Key(date: day, name: name), default: 0] += s.actualDuration / 60
        }
        return acc.map { key, min in MonthEntry(date: key.date, projectName: key.name, minutes: min) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header + project filter
                HStack {
                    Text("Dashboard").font(.title2.bold())
                    Spacer()
                    Picker(selection: $filterProjectIdStr, label: EmptyView()) {
                        Text("All projects").tag("")
                        if !filterOptions.isEmpty {
                            Divider()
                            ForEach(filterOptions) { p in Text(p.name).tag(p.id.uuidString) }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                // Summary cards
                HStack(spacing: 12) {
                    SummaryCard(title: "Today",
                                pomodoros: todaySessions.count,
                                seconds: todaySessions.reduce(0) { $0 + $1.actualDuration })
                    SummaryCard(title: "This week",
                                pomodoros: weekSessions.count,
                                seconds: weekSessions.reduce(0) { $0 + $1.actualDuration })
                    SummaryCard(title: "This month",
                                pomodoros: monthSessions.count,
                                seconds: monthSessions.reduce(0) { $0 + $1.actualDuration })
                }

                // Weekly + Monthly charts
                HStack(alignment: .top, spacing: 12) {
                    // Weekly bar chart
                    GroupBox("This Week — Daily Focus") {
                        if weeklyData.allSatisfy({ $0.minutes == 0 }) {
                            Text("No sessions this week")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            Chart(weeklyData) { entry in
                                BarMark(
                                    x: .value("Day", entry.label),
                                    y: .value("Minutes", entry.minutes)
                                )
                                .foregroundStyle(entry.isToday
                                    ? Color.accentColor
                                    : Color.accentColor.opacity(0.45))
                                .cornerRadius(4)
                            }
                            .chartYAxisLabel("min")
                            .frame(height: 150)
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Monthly stacked chart
                    GroupBox("This Month — By Project") {
                        if monthlyData.isEmpty {
                            Text("No sessions this month")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            Chart(monthlyData) { entry in
                                BarMark(
                                    x: .value("Day", entry.date, unit: .day),
                                    y: .value("Minutes", entry.minutes)
                                )
                                .foregroundStyle(by: .value("Project", entry.projectName))
                                .cornerRadius(2)
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 7)) {
                                    AxisValueLabel(format: .dateTime.day())
                                    AxisGridLine()
                                }
                            }
                            .chartYAxisLabel("min")
                            .chartLegend(position: .bottom, alignment: .leading)
                            .frame(height: 150)
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Heatmap
                GroupBox("Focus History (past 12 months)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HeatmapView(sessions: filteredSessions)
                            .padding(8)
                    }
                }

                // Session log
                GroupBox("Session Log") {
                    if sessionLog.isEmpty {
                        Text("No completed sessions yet")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(sessionLog) { group in
                                Text(group.id, format: .dateTime.year().month().day().weekday())
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                                ForEach(group.entries) { entry in
                                    SessionLogRow(entry: entry)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Project / area breakdown
                GroupBox(filterProjectId != nil ? "Time by Area" : "Time by Project") {
                    if breakdownData.isEmpty {
                        Text("No completed sessions")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        Chart(breakdownData) { entry in
                            BarMark(
                                x: .value("Label", entry.label),
                                y: .value("Hours", entry.hours)
                            )
                            .foregroundStyle(Color.accentColor.gradient)
                            .cornerRadius(4)
                            .annotation(position: .top, alignment: .center) {
                                Text(String(format: "%.1fh", entry.hours))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .chartYAxisLabel("Hours")
                        .frame(height: 160)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 760, idealWidth: 860, maxWidth: .infinity,
               minHeight: 540, idealHeight: 720, maxHeight: .infinity)
        .background(DashboardLifecycleHandler())
    }
}

// MARK: - Summary card

private struct SummaryCard: View {
    let title: String
    let pomodoros: Int
    let seconds: TimeInterval

    private var durationString: String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(pomodoros)").font(.title2.bold())
                Text("🍅")
            }
            Text(durationString).font(.callout).foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Session log row

private struct SessionLogRow: View {
    let entry: DashboardWindow.SessionLogEntry

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var timeRange: String {
        "\(Self.timeFmt.string(from: entry.startedAt))–\(Self.timeFmt.string(from: entry.endedAt))"
    }

    private var projectLabel: String {
        guard let area = entry.areaName else { return entry.projectName }
        return "\(entry.projectName) › \(area)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("🍅").font(.caption2)
                Text(timeRange)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Text(projectLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let note = entry.notes, !note.isEmpty {
                Text("「\(note)」")
                    .font(.callout.weight(.medium))
                    .foregroundColor(.primary)
                    .padding(.leading, 22)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lifecycle handler (activation policy)

private struct DashboardLifecycleHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.delegate = context.coordinator
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let visible = NSApp.windows.filter { $0.isVisible && $0.canBecomeKey }
                if visible.isEmpty { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }
}
