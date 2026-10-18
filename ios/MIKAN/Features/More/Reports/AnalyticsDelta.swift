import Foundation

/// Change of a number against the previous period of the same length: «▲ 12 %», «▼ 3,5 %», «0 %», or «—» when the
/// previous value is 0 (nothing to compare with). Percentages (margin) change in percentage points: «▲ 2,3 п.п.».
nonisolated struct AnalyticsDelta: Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        case up, down, flat
    }

    /// How the change reads for the studio: green, red or grey.
    enum Tone: Equatable, Sendable {
        case good, bad, neutral
    }

    /// Relative change in percent (or the difference in points); `nil` when there is no base to compare with.
    let value: Double?
    let direction: Direction
    var isPoints = false

    /// Relative change of `current` against `previous` (a negative base, e.g. refunds above sales, counts by magnitude).
    static func of(_ current: Int, previous: Int) -> AnalyticsDelta {
        let direction: Direction = current > previous ? .up : (current < previous ? .down : .flat)
        guard previous != 0 else { return AnalyticsDelta(value: nil, direction: direction) }
        let change = Double(current - previous) / Double(abs(previous)) * 100
        // A change that rounds to «0» reads as no change.
        return AnalyticsDelta(value: change, direction: abs(change) < 0.05 ? .flat : direction)
    }

    /// Difference of two percentages in points; `nil` when either is unknown.
    static func points(_ current: Double?, previous: Double?) -> AnalyticsDelta {
        guard let current, let previous else { return AnalyticsDelta(value: nil, direction: .flat, isPoints: true) }
        let change = (current - previous) * 10
        let rounded = change.rounded() / 10
        let direction: Direction = rounded > 0 ? .up : (rounded < 0 ? .down : .flat)
        return AnalyticsDelta(value: rounded, direction: direction, isPoints: true)
    }

    var text: String {
        guard let value else { return "—" }
        let number = Self.number(abs(value))
        let unit = isPoints ? "\u{00A0}п.п." : "\u{00A0}%"
        switch direction {
        case .up: return "▲ " + number + unit
        case .down: return "▼ " + number + unit
        case .flat: return "0" + unit
        }
    }

    /// Growth is good for revenue and clients, bad for refunds, expenses and no-shows.
    func tone(higherIsBetter: Bool = true) -> Tone {
        guard value != nil, direction != .flat else { return .neutral }
        return (direction == .up) == higherIsBetter ? .good : .bad
    }

    /// Whole numbers from 10 up, one decimal below: 12, 3,5, 0,4.
    private static func number(_ magnitude: Double) -> String {
        let digits = magnitude >= 10 ? 0...0 : 0...1
        return magnitude.formatted(.number.precision(.fractionLength(digits)).grouping(.automatic).locale(.app))
    }
}
