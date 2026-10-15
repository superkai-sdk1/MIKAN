import Foundation

/// Integer-ruble money formatting: `12400` → "12 400 ₽" (ru_RU grouping with no-break spaces).
nonisolated enum Money {
    /// No-break space, as used by ru_RU digit grouping.
    static let groupSeparator = "\u{00A0}"
    static let symbol = "₽"
    static let minus = "−"

    static func format(_ amount: Int) -> String {
        (amount < 0 ? minus : "") + group(amount.magnitude) + groupSeparator + symbol
    }

    /// "+1 000 ₽", "−200 ₽", "0 ₽" — for differences and deltas.
    static func formatSigned(_ amount: Int) -> String {
        amount > 0 ? "+" + format(amount) : format(amount)
    }

    /// "от 2 500 ₽" when the price is a lower bound.
    static func format(_ amount: Int, from isFrom: Bool) -> String {
        isFrom ? "от " + format(amount) : format(amount)
    }

    /// Catalog price of a service: «2 500 ₽», «от 15 000 ₽», «от 2 000 до 5 000 ₽», «до 10 000 ₽», «Бесплатно».
    static func servicePrice(_ price: Int, max: Int?, from isFrom: Bool) -> String {
        if let max {
            return price > 0 ? "от " + group(UInt(Swift.max(0, price))) + " до " + format(max) : "до " + format(max)
        }
        if isFrom { return "от " + format(price) }
        return price == 0 ? "Бесплатно" : format(price)
    }

    /// Compact axis labels: 1500 → "1,5 тыс.", 120000 → "120 тыс.".
    static func compact(_ amount: Int) -> String {
        let value = Double(amount)
        switch abs(value) {
        case 1_000_000...: return (value / 1_000_000).formatted(.number.precision(.fractionLength(0...1)).locale(.app)) + " млн"
        case 1_000...: return (value / 1_000).formatted(.number.precision(.fractionLength(0...1)).locale(.app)) + " тыс."
        default: return String(amount)
        }
    }

    /// Digits grouped by three with no-break spaces: 1234567 → "1 234 567".
    static func group(_ value: UInt) -> String {
        let digits = Array(String(value))
        let groups = stride(from: digits.count, to: 0, by: -3).reversed().map { end in
            String(digits[max(0, end - 3)..<end])
        }
        return groups.joined(separator: groupSeparator)
    }

    /// Parses user input like "12 400", "12400 ₽" → 12400. Returns `nil` when there are no digits.
    static func parse(_ text: String) -> Int? {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits.prefix(maxDigits))
    }

    static let maxDigits = 9
}
