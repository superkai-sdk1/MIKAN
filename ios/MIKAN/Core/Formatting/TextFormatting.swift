import Foundation

/// Russian plural forms: 1 запись, 2 записи, 5 записей.
nonisolated enum Plural {
    static func word(_ count: Int, one: String, few: String, many: String) -> String {
        let n10 = abs(count) % 10
        let n100 = abs(count) % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }

    static func count(_ count: Int, one: String, few: String, many: String) -> String {
        "\(count) \(word(count, one: one, few: few, many: many))"
    }

    static func appointments(_ count: Int) -> String {
        Self.count(count, one: "запись", few: "записи", many: "записей")
    }

    static func days(_ count: Int) -> String {
        Self.count(count, one: "день", few: "дня", many: "дней")
    }
}

nonisolated enum PhoneText {
    /// "+79991234567" → "+7 999 123-45-67"; other formats are returned unchanged.
    static func display(_ phone: String?) -> String {
        guard let phone = phone.nonEmpty else { return "" }
        let digits = phone.filter(\.isNumber)
        guard phone.hasPrefix("+7"), digits.count == 11 else { return phone }
        let chars = Array(digits)
        let code = String(chars[1...3])
        let first = String(chars[4...6])
        let second = String(chars[7...8])
        let third = String(chars[9...10])
        return "+7 \(code) \(first)-\(second)-\(third)"
    }

    /// URL for the Phone app, or `nil` when there is nothing to dial.
    static func callURL(_ phone: String?) -> URL? {
        guard let phone = phone.nonEmpty else { return nil }
        let dialable = phone.filter { $0.isNumber || $0 == "+" }
        guard !dialable.isEmpty else { return nil }
        return URL(string: "tel:\(dialable)")
    }
}

nonisolated enum Initials {
    /// "Иван Петров" → "ИП", "Анна" → "А".
    static func from(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
