import Foundation

enum Formatting {
    /// Format a token count for compact display: 37.8M, 1.7B, 234K
    static func tokens(_ count: Int) -> String {
        let abs = abs(count)
        let sign = count < 0 ? "-" : ""
        if abs >= 1_000_000_000 {
            let value = Double(abs) / 1_000_000_000
            return "\(sign)\(formatNumber(value))B"
        } else if abs >= 1_000_000 {
            let value = Double(abs) / 1_000_000
            return "\(sign)\(formatNumber(value))M"
        } else if abs >= 1_000 {
            let value = Double(abs) / 1_000
            return "\(sign)\(formatNumber(value))K"
        } else {
            return "\(sign)\(abs)"
        }
    }

    /// Format a percentage: "72%" or "—" if nil
    static func percent(_ value: Double?) -> String {
        guard let value = value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    /// Format time remaining: "2h 14m" or "4d 11h"
    static func timeRemaining(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval))
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Format a full token count with commas: "37,826,638"
    static func tokensDetailed(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private static func formatNumber(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        } else if value >= 10 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}
