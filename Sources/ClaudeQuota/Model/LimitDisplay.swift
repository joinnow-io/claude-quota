import Foundation

/// Per-limit menu bar display rule.
enum LimitDisplay: String, CaseIterable {
    case always
    case hide
    case atLeast10
    case atLeast50
    case atLeast60
    case atLeast70
    case atLeast80
    case atLeast90
    case atLeast100

    /// Threshold that utilization must meet to be shown, or nil for always/hide.
    var threshold: Double? {
        switch self {
        case .always, .hide: return nil
        case .atLeast10: return 10
        case .atLeast50: return 50
        case .atLeast60: return 60
        case .atLeast70: return 70
        case .atLeast80: return 80
        case .atLeast90: return 90
        case .atLeast100: return 100
        }
    }

    var label: String {
        switch self {
        case .always: return "Always"
        case .hide: return "Hide"
        case .atLeast10: return "≥10%"
        case .atLeast50: return "≥50%"
        case .atLeast60: return "≥60%"
        case .atLeast70: return "≥70%"
        case .atLeast80: return "≥80%"
        case .atLeast90: return "≥90%"
        case .atLeast100: return "100%"
        }
    }
}
