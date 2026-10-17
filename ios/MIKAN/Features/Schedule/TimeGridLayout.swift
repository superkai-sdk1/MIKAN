import Foundation

/// Pure layout math for the time grid: visible hours, day clipping, side-by-side lanes for overlaps, time ↔ y.
/// Minutes are counted from the day's local midnight; y is measured from the top of the visible range.
nonisolated enum TimeGridLayout {
    static let minutesPerDay = 24 * 60
    static let fullDay = 0..<minutesPerDay
    static let slotMinutes = 15
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

    /// Hours the grid shows: the working hours of every visible day (`windows`), widened to whole hours and
    /// to every appointment segment outside them, so early and late appointments are never cut off.
    static func visibleRange(
        windows: [Range<Int>],
        segments: [Segment],
        minimumDuration: Int = minimumLayoutMinutes
    ) -> Range<Int> {
        let starts = windows.filter { !$0.isEmpty }.map(\.lowerBound) + segments.map(\.startMinute)
        let ends = windows.filter { !$0.isEmpty }.map(\.upperBound)
            + segments.map { max($0.endMinute, $0.startMinute + minimumDuration) }
        guard let first = starts.min(), let last = ends.max() else { return fullDay }
        let lower = min(max(0, first / 60 * 60), minutesPerDay - 60)
        let upper = min(max(lower + 60, (last + 59) / 60 * 60), minutesPerDay)
        return lower..<upper
    }

    /// y of `minute` in a grid whose top is `rangeStart`.
    static func y(forMinute minute: Double, hourHeight: Double, rangeStart: Int = 0) -> Double {
        (minute - Double(rangeStart)) / 60 * hourHeight
    }

    static func minute(forY y: Double, hourHeight: Double, rangeStart: Int = 0) -> Double {
        guard hourHeight > 0 else { return Double(rangeStart) }
        return Double(rangeStart) + y / hourHeight * 60
    }

    /// Start of the 15-minute slot under `y`, clamped to the visible range.
    static func slotStart(forY y: Double, hourHeight: Double, range: Range<Int> = fullDay, step: Int = slotMinutes) -> Int {
        let minute = Int(minute(forY: y, hourHeight: hourHeight, rangeStart: range.lowerBound).rounded(.down))
        let floored = (minute / step) * step
        return min(max(range.lowerBound, floored), max(range.lowerBound, range.upperBound - step))
    }

    /// Minutes since midnight of `date` in `calendar`'s time zone.
    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Where the grid opens: an hour before now when today is visible, otherwise half an hour
    /// before the first appointment, otherwise the start of the working day.
    static func initialScrollMinute(nowMinute: Int?, firstAppointmentMinute: Int?, workdayStartMinute: Int) -> Int {
        if let nowMinute { return max(0, nowMinute - 60) }
        if let firstAppointmentMinute { return max(0, firstAppointmentMinute - 30) }
        return workdayStartMinute
    }
}
