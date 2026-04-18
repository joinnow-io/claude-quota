import Foundation

/// Display helpers for usage-limit keys returned by the API.
/// Known keys get curated names; unknown keys fall back to a titlecased version
/// of the raw snake_case key so new limits surface automatically.
enum LimitKind {
    static let displayName: [String: String] = [
        "five_hour":            "5-Hour Window",
        "seven_day":            "7-Day — All Models",
        "seven_day_sonnet":     "7-Day — Sonnet",
        "seven_day_opus":       "7-Day — Opus",
        "seven_day_cowork":     "7-Day — Cowork",
        "seven_day_oauth_apps": "7-Day — OAuth Apps",
    ]

    static func name(for key: String) -> String {
        if let name = displayName[key] { return name }
        return key
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    /// Stable display order: known keys in this order first, then any unknown
    /// keys sorted alphabetically.
    static let knownOrder = [
        "five_hour",
        "seven_day",
        "seven_day_sonnet",
        "seven_day_opus",
        "seven_day_omelette",
        "seven_day_cowork",
        "seven_day_oauth_apps",
    ]

    static func sorted(_ keys: [String]) -> [String] {
        let known = knownOrder.filter { keys.contains($0) }
        let unknown = keys.filter { !knownOrder.contains($0) }.sorted()
        return known + unknown
    }
}
