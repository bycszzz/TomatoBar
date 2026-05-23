import Charts
import SwiftUI

struct ProjectRetroView: View {
    let project: TBProject
    @ObservedObject private var store = TrackingStore.shared
    @Environment(\.dismiss) private var dismiss

    // MARK: - Filtered sessions

    private var sessions: [TBSession] {
        store.sessions.filter { $0.projectId == project.id && $0.type == .work && $0.completed }
    }

    // MARK: - Summary stats

    private var totalHours: Double { sessions.reduce(0.0) { $0 + $1.actualDuration } / 3600 }
    private var activeDays: Int {
        Set(sessions.map { Calendar.current.startOfDay(for: $0.startedAt) }).count
    }
    private var firstDate: Date? { sessions.map { $0.startedAt }.min() }
    private var lastDate: Date? { sessions.map { $0.startedAt }.max() }

    private var durationString: String {
        let h = Int(totalHours)
        let m = Int((totalHours - Double(h)) * 60)
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    // MARK: - Chart data types

    private struct AreaEntry: Identifiable {
        let id: String
        let name: String
        let hours: Double
    }

    private struct HourEntry: Identifiable {
        let id: Int
        let hour: Int
        let count: Int
    }

    private struct CumEntry: Identifiable {
        let id: TimeInterval
        let date: Date
        let cumulativeHours: Double
    }

    // MARK: - Chart data

    private var areaData: [AreaEntry] {
        let areaMap = Dictionary(uniqueKeysWithValues: store.areas(for: project.id).map { ($0.id, $0.name) })
        var grouped: [UUID?: [TBSession]] = [:]
        for s in sessions { grouped[s.areaId, default: []].append(s) }
        return grouped.map { areaId, items in
            AreaEntry(
                id: areaId?.uuidString ?? "unassigned",
                name: areaId.flatMap { areaMap[$0] } ?? "Unassigned",
                hours: items.reduce(0.0) { $0 + $1.actualDuration } / 3600
            )
        }.sorted { $0.hours > $1.hours }
    }

    private var hourlyData: [HourEntry] {
        let grouped = Dictionary(grouping: sessions) {
            Calendar.current.component(.hour, from: $0.startedAt)
        }
        return (0 ..< 24).map { h in
            HourEntry(id: h, hour: h, count: grouped[h]?.count ?? 0)
        }
    }

    private var cumulativeData: [CumEntry] {
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        var total: Double = 0
        return sorted.map { s in
            total += s.actualDuration / 3600
            return CumEntry(id: s.startedAt.timeIntervalSince1970, date: s.startedAt, cumulativeHours: total)
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name).font(.title2.bold())
                    if let status = statusLabel {
                        Text(status).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Stats row
                    HStack(spacing: 12) {
                        StatChip(label: "Sessions", value: "\(sessions.count)")
                        StatChip(label: "Focus time", value: durationString)
                        StatChip(label: "Active days", value: "\(activeDays)")
                        if let f = firstDate {
                            StatChip(label: "Since", value: f.formatted(.dateTime.year().month().day()))
                        }
                    }

                    if sessions.isEmpty {
                        Text("No completed sessions for this project.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        // Area breakdown
                        if areaData.count > 1 || (areaData.count == 1 && areaData[0].id != "unassigned") {
                            GroupBox("Time by Area") {
                                HStack(alignment: .top, spacing: 16) {
                                    // Pie chart
                                    Chart(areaData) { entry in
                                        SectorMark(
                                            angle: .value("Hours", entry.hours),
                                            innerRadius: .ratio(0.5),
                                            angularInset: 2
                                        )
                                        .foregroundStyle(by: .value("Area", entry.name))
                                        .cornerRadius(4)
                                    }
                                    .chartLegend(position: .trailing, alignment: .center)
                                    .frame(width: 200, height: 160)

                                    // Bar chart alongside
                                    Chart(areaData) { entry in
                                        BarMark(
                                            x: .value("Hours", entry.hours),
                                            y: .value("Area", entry.name)
                                        )
                                        .foregroundStyle(by: .value("Area", entry.name))
                                        .cornerRadius(4)
                                        .annotation(position: .trailing) {
                                            Text(String(format: "%.1fh", entry.hours))
                                                .font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                    .chartLegend(.hidden)
                                    .chartXAxisLabel("Hours")
                                    .frame(maxWidth: .infinity, minHeight: 120)
                                }
                                .padding(.top, 4)
                            }
                        }

                        // Hourly distribution
                        GroupBox("Focus Hours Distribution") {
                            Chart(hourlyData) { entry in
                                BarMark(
                                    x: .value("Hour", entry.hour),
                                    y: .value("Sessions", entry.count)
                                )
                                .foregroundStyle(entry.count > 0
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.15))
                                .cornerRadius(3)
                            }
                            .chartXAxis {
                                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                                    AxisValueLabel {
                                        if let h = value.as(Int.self) {
                                            Text("\(h):00").font(.caption2)
                                        }
                                    }
                                    AxisGridLine()
                                }
                            }
                            .chartYAxisLabel("Sessions")
                            .frame(height: 100)
                            .padding(.top, 4)
                        }

                        // Cumulative focus curve
                        if cumulativeData.count > 1 {
                            GroupBox("Cumulative Focus Time") {
                                Chart(cumulativeData) { entry in
                                    LineMark(
                                        x: .value("Date", entry.date),
                                        y: .value("Hours", entry.cumulativeHours)
                                    )
                                    .foregroundStyle(Color.accentColor)
                                    .interpolationMethod(.stepEnd)

                                    AreaMark(
                                        x: .value("Date", entry.date),
                                        y: .value("Hours", entry.cumulativeHours)
                                    )
                                    .foregroundStyle(Color.accentColor.opacity(0.15))
                                    .interpolationMethod(.stepEnd)
                                }
                                .chartYAxisLabel("Total hours")
                                .frame(height: 120)
                                .padding(.top, 4)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 640, height: 540)
    }

    private var statusLabel: String? {
        switch project.status {
        case .completed:
            guard let d = project.completedAt else { return "Completed" }
            return "Completed \(d.formatted(.dateTime.year().month().day()))"
        case .archived:
            return "Archived"
        case .active:
            return nil
        }
    }
}

// MARK: - Stat chip

private struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }
}
