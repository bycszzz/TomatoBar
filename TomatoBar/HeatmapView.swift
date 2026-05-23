import SwiftUI

struct HeatmapView: View {
    let sessions: [TBSession]

    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 2
    private let weeksToShow = 53
    private let dayLabels = ["Mon", "", "Wed", "", "Fri", "", "Sun"]

    // Pre-compute pomodoro count per calendar day — O(n) once per body eval
    private func countsByDay(_ calendar: Calendar) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for s in sessions {
            let day = calendar.startOfDay(for: s.startedAt)
            result[day, default: 0] += 1
        }
        return result
    }

    // Monday of the week (weeksToShow-1) weeks ago
    private func gridStart(_ calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) // 1=Sun
        let daysToMonday = weekday == 1 ? 6 : weekday - 2
        let thisMonday = calendar.date(byAdding: .day, value: -daysToMonday, to: today)!
        return calendar.date(byAdding: .weekOfYear, value: -(weeksToShow - 1), to: thisMonday)!
    }

    private func monthLabels(start: Date, _ calendar: Calendar) -> [(col: Int, label: String)] {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        var results: [(Int, String)] = []
        var lastMonth = -1
        for col in 0 ..< weeksToShow {
            let date = calendar.date(byAdding: .day, value: col * 7, to: start)!
            let month = calendar.component(.month, from: date)
            if month != lastMonth {
                results.append((col, fmt.string(from: date)))
                lastMonth = month
            }
        }
        return results
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: return Color.secondary.opacity(0.12)
        case 1: return Color.green.opacity(0.30)
        case 2, 3: return Color.green.opacity(0.50)
        case 4, 5, 6: return Color.green.opacity(0.70)
        default: return Color.green
        }
    }

    var body: some View {
        let calendar = Calendar.current
        let counts = countsByDay(calendar)
        let start = gridStart(calendar)
        let today = calendar.startOfDay(for: Date())
        let labels = monthLabels(start: start, calendar)
        let stride = cellSize + cellSpacing
        let dayLabelWidth: CGFloat = 26

        VStack(alignment: .leading, spacing: 4) {
            // Month labels row
            ZStack(alignment: .topLeading) {
                Color.clear.frame(height: 14)
                ForEach(labels, id: \.col) { item in
                    Text(item.label)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .offset(x: dayLabelWidth + CGFloat(item.col) * stride)
                }
            }

            // Day labels + grid
            HStack(alignment: .top, spacing: 0) {
                // Day-of-week labels
                VStack(alignment: .trailing, spacing: cellSpacing) {
                    ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: dayLabelWidth - cellSpacing, height: cellSize,
                                   alignment: .trailing)
                    }
                }
                .padding(.trailing, cellSpacing)

                // Week columns
                HStack(spacing: cellSpacing) {
                    ForEach(0 ..< weeksToShow, id: \.self) { col in
                        VStack(spacing: cellSpacing) {
                            ForEach(0 ..< 7, id: \.self) { row in
                                let offset = col * 7 + row
                                let date = calendar.date(byAdding: .day,
                                                         value: offset, to: start)!
                                let isFuture = date > today
                                let count = isFuture ? 0 : (counts[date] ?? 0)
                                let tip = isFuture ? "" :
                                    "\(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)): \(count) pomodoro\(count == 1 ? "" : "s")"

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isFuture ? Color.clear : color(for: count))
                                    .frame(width: cellSize, height: cellSize)
                                    .help(tip)
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.system(size: 9)).foregroundColor(.secondary)
                ForEach([0, 1, 3, 5, 7], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: level))
                        .frame(width: cellSize, height: cellSize)
                }
                Text("More").font(.system(size: 9)).foregroundColor(.secondary)
            }
            .padding(.top, 2)
        }
    }
}
