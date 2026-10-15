import Foundation

/// Pure layout math for the time grid: day clipping, side-by-side lanes for overlaps, time ↔ y.
nonisolated enum TimeGridLayout {
    static let minutesPerDay = 24 * 60
    static let slotMinutes = 15
    static let workdayStartHour = 8
    /// Blocks shorter than this still get room, so short neighbours don't visually collide.
    static let minimumLayoutMinutes = 20

    struct Interval: Equatable, Sendable {
        let id: Int
        let start: Date
        let end: Date
    }

    /// Part of an interval inside one day, in minutes since that day's midnight.
    struct Segment: Equatable, Sendable {
        let id: Int
        let startMinute: Int
        let endMinute: Int
    }

    struct Placement: Equatable, Sendable {
        let id: Int
        let startMinute: Int
        let endMinute: Int
        /// Zero-based lane inside its overlap cluster.
        let lane: Int
        /// Number of lanes the cluster is split into (column width ÷ laneCount).
        let laneCount: Int
    }

    /// Clips intervals to `[dayStart, next midnight)`; intervals outside the day are dropped.
    static func segments(of intervals: [Interval], dayStart: Date, calendar: Calendar) -> [Segment] {
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return intervals.compactMap { interval in
            guard interval.start < dayEnd, interval.end > dayStart else { return nil }
            let start = max(interval.start, dayStart)
            let end = min(interval.end, dayEnd)
            let startMinute = Int((start.timeIntervalSince(dayStart) / 60).rounded(.down))
            let endMinute = Int((end.timeIntervalSince(dayStart) / 60).rounded(.up))
            return Segment(
                id: interval.id,
                startMinute: min(max(0, startMinute), minutesPerDay),
                endMinute: min(max(startMinute, endMinute), minutesPerDay)
            )
        }
    }

    /// Assigns overlapping segments to side-by-side lanes.
    /// A cluster is a run of transitively overlapping segments; every segment in it shares `laneCount`.
    /// Back-to-back segments (end == next start) do not overlap.
    static func placements(for segments: [Segment], minimumDuration: Int = minimumLayoutMinutes) -> [Placement] {
        let sorted = segments.sorted {
            ($0.startMinute, -$0.endMinute, $0.id) < ($1.startMinute, -$1.endMinute, $1.id)
        }
        var result: [Placement] = []
        var cluster: [(segment: Segment, lane: Int)] = []
        var laneEnds: [Int] = []
        var clusterEnd = Int.min

        func flushCluster() {
            let laneCount = laneEnds.count
            result += cluster.map { entry in
                Placement(
                    id: entry.segment.id,
                    startMinute: entry.segment.startMinute,
                    endMinute: entry.segment.endMinute,
                    lane: entry.lane,
                    laneCount: laneCount
                )
            }
            cluster = []
            laneEnds = []
        }

        for segment in sorted {
            let effectiveEnd = max(segment.endMinute, segment.startMinute + minimumDuration)
            if !cluster.isEmpty, segment.startMinute >= clusterEnd {
                flushCluster()
                clusterEnd = Int.min
            }
            if let lane = laneEnds.firstIndex(where: { $0 <= segment.startMinute }) {
                laneEnds[lane] = effectiveEnd
                cluster.append((segment, lane))
            } else {
                laneEnds.append(effectiveEnd)
                cluster.append((segment, laneEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, effectiveEnd)
        }
        flushCluster()
        return result
    }

    static func y(forMinute minute: Double, hourHeight: Double) -> Double {
        minute / 60 * hourHeight
    }

    static func minute(forY y: Double, hourHeight: Double) -> Double {
        guard hourHeight > 0 else { return 0 }
        return y / hourHeight * 60
    }

    /// Start of the 15-minute slot under `y`, clamped to the day.
    static func slotStart(forY y: Double, hourHeight: Double, step: Int = slotMinutes) -> Int {
        let minute = Int(minute(forY: y, hourHeight: hourHeight).rounded(.down))
        let floored = (minute / step) * step
        return min(max(0, floored), minutesPerDay - step)
    }

    /// Minutes since midnight of `date` in `calendar`'s time zone.
    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Where the grid opens: an hour before now when today is visible, otherwise half an hour
    /// before the first appointment, otherwise the start of the working day.
    static func initialScrollMinute(nowMinute: Int?, firstAppointmentMinute: Int?) -> Int {
        if let nowMinute { return max(0, nowMinute - 60) }
        if let firstAppointmentMinute { return max(0, firstAppointmentMinute - 30) }
        return workdayStartHour * 60
    }
}
