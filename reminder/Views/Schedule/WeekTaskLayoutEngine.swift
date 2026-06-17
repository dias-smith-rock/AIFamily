import CoreGraphics
import Foundation

struct WeekGridMetrics {
    static let hourRowHeight: CGFloat = 60
    static let hoursPerDay = 24
    static let compactEventMinHeight: CGFloat = 36
    static let columnSpacing: CGFloat = 1
    static let eventHorizontalInset: CGFloat = 1

    static var gridHeight: CGFloat {
        hourRowHeight * CGFloat(hoursPerDay)
    }
}

struct WeekTaskLayoutItem: Identifiable {
    let id: UUID
    let task: FamilyTask
    let frame: CGRect

    init(task: FamilyTask, frame: CGRect) {
        self.id = task.id
        self.task = task
        self.frame = frame
    }
}

enum WeekTaskLayoutEngine {
    static func layout(
        tasks: [FamilyTask],
        weekDays: [Date],
        columnWidth: CGFloat,
        calendar: Calendar = .current,
        taskStart: (FamilyTask) -> Date,
        taskEnd: (FamilyTask) -> Date
    ) -> [WeekTaskLayoutItem] {
        guard columnWidth > 0, weekDays.count == 7 else { return [] }

        let timedTasks = tasks.filter { $0.isAllDay == false }
        var items: [WeekTaskLayoutItem] = []

        for dayIndex in 0..<7 {
            let dayStart = calendar.startOfDay(for: weekDays[dayIndex])
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            let dayTasks = timedTasks.compactMap { task -> (FamilyTask, CGFloat, CGFloat)? in
                let start = taskStart(task)
                guard calendar.isDate(start, inSameDayAs: dayStart) else { return nil }

                let rawEnd = taskEnd(task)
                let clippedEnd = min(rawEnd, dayEnd)
                let startY = yOffset(for: start, calendar: calendar)
                var endY = yOffset(for: clippedEnd, calendar: calendar)
                if endY <= startY {
                    endY = startY + WeekGridMetrics.compactEventMinHeight
                }
                return (task, startY, endY)
            }
            .sorted { $0.1 < $1.1 }

            guard dayTasks.isEmpty == false else { continue }

            var laneEnds: [CGFloat] = []
            var placements: [(FamilyTask, Int, CGFloat, CGFloat)] = []

            for (task, startY, endY) in dayTasks {
                var lane = 0
                while lane < laneEnds.count, laneEnds[lane] > startY + 0.5 {
                    lane += 1
                }
                if lane == laneEnds.count {
                    laneEnds.append(endY)
                } else {
                    laneEnds[lane] = max(laneEnds[lane], endY)
                }
                placements.append((task, lane, startY, endY))
            }

            let laneCount = max(1, laneEnds.count)
            let laneWidth = max(
                8,
                (columnWidth - WeekGridMetrics.eventHorizontalInset * 2) / CGFloat(laneCount)
            )

            for (task, lane, startY, endY) in placements {
                let height = max(WeekGridMetrics.compactEventMinHeight, endY - startY)
                let x = CGFloat(dayIndex) * columnWidth
                    + WeekGridMetrics.eventHorizontalInset
                    + CGFloat(lane) * laneWidth
                let frame = CGRect(
                    x: x,
                    y: startY,
                    width: laneWidth - WeekGridMetrics.columnSpacing,
                    height: height
                )
                items.append(WeekTaskLayoutItem(task: task, frame: frame))
            }
        }

        return items
    }

    static func yOffset(for date: Date, calendar: Calendar = .current) -> CGFloat {
        fractionalHour(for: date, calendar: calendar) * WeekGridMetrics.hourRowHeight
    }

    static func fractionalHour(for date: Date, calendar: Calendar = .current) -> CGFloat {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = CGFloat(components.hour ?? 0)
        let minute = CGFloat(components.minute ?? 0)
        let second = CGFloat(components.second ?? 0)
        return hour + minute / 60 + second / 3600
    }
}
