import Foundation

/// Estimate USD cost from token usage based on published Anthropic pricing.
enum CostEstimator {
    struct ModelPricing {
        let inputPerMToken: Double
        let outputPerMToken: Double
        let cacheReadPerMToken: Double
        let cacheWritePerMToken: Double
    }

    static let pricing: [String: ModelPricing] = [
        "claude-opus-4-6": ModelPricing(inputPerMToken: 15.0, outputPerMToken: 75.0, cacheReadPerMToken: 1.5, cacheWritePerMToken: 18.75),
        "claude-opus-4-5-20251101": ModelPricing(inputPerMToken: 15.0, outputPerMToken: 75.0, cacheReadPerMToken: 1.5, cacheWritePerMToken: 18.75),
        "claude-sonnet-4-6": ModelPricing(inputPerMToken: 3.0, outputPerMToken: 15.0, cacheReadPerMToken: 0.3, cacheWritePerMToken: 3.75),
        "claude-sonnet-4-5-20250929": ModelPricing(inputPerMToken: 3.0, outputPerMToken: 15.0, cacheReadPerMToken: 0.3, cacheWritePerMToken: 3.75),
        "claude-haiku-4-5-20251001": ModelPricing(inputPerMToken: 0.80, outputPerMToken: 4.0, cacheReadPerMToken: 0.08, cacheWritePerMToken: 1.0),
    ]

    static let defaultPricing = ModelPricing(inputPerMToken: 3.0, outputPerMToken: 15.0, cacheReadPerMToken: 0.3, cacheWritePerMToken: 3.75)

    static func estimateCost(usage: TokenUsage, model: String) -> Double {
        let p = pricing[model] ?? matchPricing(model: model)
        let inputCost = Double(usage.inputTokens) / 1_000_000 * p.inputPerMToken
        let outputCost = Double(usage.outputTokens) / 1_000_000 * p.outputPerMToken
        let cacheReadCost = Double(usage.cacheReadInputTokens) / 1_000_000 * p.cacheReadPerMToken
        let cacheWriteCost = Double(usage.cacheCreationInputTokens) / 1_000_000 * p.cacheWritePerMToken
        return inputCost + outputCost + cacheReadCost + cacheWriteCost
    }

    static func estimateCost(window: WindowUsage) -> Double {
        window.byModel.values.reduce(0) { sum, modelUsage in
            sum + estimateCost(usage: modelUsage.tokens, model: modelUsage.model)
        }
    }

    static func formatCost(_ cost: Double) -> String {
        if cost >= 1.0 {
            return String(format: "$%.2f", cost)
        } else if cost >= 0.01 {
            return String(format: "$%.2f", cost)
        } else {
            return String(format: "$%.4f", cost)
        }
    }

    private static func matchPricing(model: String) -> ModelPricing {
        if model.contains("opus") {
            return pricing["claude-opus-4-6"]!
        } else if model.contains("haiku") {
            return pricing["claude-haiku-4-5-20251001"]!
        } else {
            return defaultPricing // sonnet-like pricing as default
        }
    }
}
