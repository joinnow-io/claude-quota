import Foundation

/// Known plan types from keychain subscriptionType
enum SubscriptionType: String, CaseIterable {
    case pro
    case max
    case team
    case enterprise

    var displayName: String {
        switch self {
        case .pro: return "Claude Pro"
        case .max: return "Claude Max"
        case .team: return "Claude Team"
        case .enterprise: return "Claude Enterprise"
        }
    }
}

/// Rate limit configuration for a plan/tier combination
struct PlanLimitConfig: Codable, Equatable {
    var fiveHourTokenLimit: Int
    var sevenDayTokenLimit: Int
    var isCustomized: Bool

    static let proDefault = PlanLimitConfig(
        fiveHourTokenLimit: 45_000_000,
        sevenDayTokenLimit: 255_000_000,
        isCustomized: false
    )
}

enum PlanLimits {
    /// Base limits for Pro plan (calibrated against Claude's built-in usage display)
    static let proBaseFiveHour = 45_000_000    // ~45M tokens
    static let proBaseSevenDay = 255_000_000   // ~255M tokens

    /// Parse the multiplier from a rate limit tier string like "default_claude_max_5x"
    static func parseMultiplier(from tier: String?) -> Int {
        guard let tier = tier else { return 1 }
        // Match patterns like "5x", "20x" at the end
        if let range = tier.range(of: #"(\d+)x$"#, options: .regularExpression) {
            let numStr = tier[range].dropLast() // remove "x"
            return Int(numStr) ?? 1
        }
        return 1
    }

    /// Get default limits for a subscription type and tier
    static func defaultLimits(subscription: SubscriptionType?, tier: String?) -> PlanLimitConfig {
        let multiplier = parseMultiplier(from: tier)
        return PlanLimitConfig(
            fiveHourTokenLimit: proBaseFiveHour * multiplier,
            sevenDayTokenLimit: proBaseSevenDay * multiplier,
            isCustomized: false
        )
    }

    /// Load user-customized limits or return defaults
    static func loadLimits(subscription: SubscriptionType?, tier: String?) -> PlanLimitConfig {
        let key = limitsKey(subscription: subscription, tier: tier)
        if let data = UserDefaults.standard.data(forKey: key),
           let config = try? JSONDecoder().decode(PlanLimitConfig.self, from: data) {
            return config
        }
        return defaultLimits(subscription: subscription, tier: tier)
    }

    /// Save user-customized limits
    static func saveLimits(_ config: PlanLimitConfig, subscription: SubscriptionType?, tier: String?) {
        let key = limitsKey(subscription: subscription, tier: tier)
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Reset to defaults
    static func resetToDefaults(subscription: SubscriptionType?, tier: String?) {
        let key = limitsKey(subscription: subscription, tier: tier)
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func limitsKey(subscription: SubscriptionType?, tier: String?) -> String {
        "plan_limits_\(subscription?.rawValue ?? "unknown")_\(tier ?? "default")"
    }
}
