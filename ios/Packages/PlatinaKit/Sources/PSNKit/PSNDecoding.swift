import Foundation

/// Dates and durations as PSN writes them.
public enum PSNDate {
    /// `2015-07-10T19:40:19Z`, `2024-08-03T19:28:27.12Z`, `2023-01-05T10:00:00.000+00:00`: the
    /// fraction of a second has any number of digits, or none.
    public static func parse(_ string: String) -> Date? {
        var whole = string
        var fraction: Double = 0
        if let dot = string.firstIndex(of: ".") {
            let afterDot = string.index(after: dot)
            let zoneStart = string[afterDot...].firstIndex { !$0.isNumber } ?? string.endIndex
            let digits = string[afterDot..<zoneStart]
            fraction = Double("0." + digits) ?? 0
            whole = String(string[..<dot]) + String(string[zoneStart...])
        }
        guard let date = try? Date(whole, strategy: .iso8601) else { return nil }
        return date.addingTimeInterval(fraction)
    }

    static let decodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = parse(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a PSN date: \(string)")
        }
        return date
    }
}

/// An ISO 8601 duration as the game list writes the time played: `PT228H56M33S`, `PT45M`,
/// `P1DT2H`.
public enum PSNDuration {
    public static func parse(_ string: String) -> TimeInterval? {
        guard string.hasPrefix("P") else { return nil }
        var total: TimeInterval = 0
        var number = ""
        var inTime = false
        var sawValue = false
        for character in string.dropFirst() {
            if character == "T" {
                guard number.isEmpty else { return nil }
                inTime = true
                continue
            }
            if character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
                continue
            }
            guard let value = Double(number) else { return nil }
            number = ""
            sawValue = true
            switch (character, inTime) {
            case ("W", false): total += value * 7 * 86_400
            case ("D", false): total += value * 86_400
            case ("H", true): total += value * 3_600
            case ("M", true): total += value * 60
            case ("S", true): total += value
            default: return nil
            }
        }
        return number.isEmpty && sawValue ? total : nil
    }
}

extension JSONDecoder {
    static let psn: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = PSNDate.decodingStrategy
        return decoder
    }()
}
