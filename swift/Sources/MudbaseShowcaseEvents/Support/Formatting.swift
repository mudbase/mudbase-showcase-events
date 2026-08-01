import Foundation

enum Formatting {
    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }

    /// Mirrors `web/src/lib/utils.ts`'s `formatRelativeTime` — a short relative label ("just now",
    /// "5m", "3h", "2d") that falls back to an absolute medium date once the gap exceeds a week.
    static func relativeTime(_ date: Date) -> String {
        let diffSeconds = Int(Date().timeIntervalSince(date).rounded())

        if abs(diffSeconds) < 5 { return "just now" }
        if abs(diffSeconds) < 60 { return "\(diffSeconds)s" }
        let diffMinutes = Int((Double(diffSeconds) / 60).rounded())
        if abs(diffMinutes) < 60 { return "\(diffMinutes)m" }
        let diffHours = Int((Double(diffMinutes) / 60).rounded())
        if abs(diffHours) < 24 { return "\(diffHours)h" }
        let diffDays = Int((Double(diffHours) / 24).rounded())
        if abs(diffDays) < 7 { return "\(diffDays)d" }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }
}
