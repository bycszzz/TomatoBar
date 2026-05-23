import Foundation

struct TBDayAggregate {
    let date: Date
    let pomodoroCount: Int
    let focusSeconds: TimeInterval
}

struct TBHourAggregate {
    let hour: Int  // 0-23
    let pomodoroCount: Int
    let focusSeconds: TimeInterval
}

enum Aggregations {
    static func byDay(_ sessions: [TBSession], calendar: Calendar = .current) -> [TBDayAggregate] {
        let work = sessions.filter { $0.type == .work && $0.completed }
        let grouped = Dictionary(grouping: work) { calendar.startOfDay(for: $0.startedAt) }
        return grouped.map { date, items in
            TBDayAggregate(
                date: date,
                pomodoroCount: items.count,
                focusSeconds: items.reduce(0) { $0 + $1.actualDuration }
            )
        }.sorted { $0.date < $1.date }
    }

    static func byHour(_ sessions: [TBSession], calendar: Calendar = .current) -> [TBHourAggregate] {
        let work = sessions.filter { $0.type == .work && $0.completed }
        let grouped = Dictionary(grouping: work) { calendar.component(.hour, from: $0.startedAt) }
        return (0 ..< 24).map { hour in
            let items = grouped[hour] ?? []
            return TBHourAggregate(
                hour: hour,
                pomodoroCount: items.count,
                focusSeconds: items.reduce(0) { $0 + $1.actualDuration }
            )
        }
    }
}
