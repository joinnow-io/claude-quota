import Foundation

struct TokenUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationInputTokens + cacheReadInputTokens
    }

    static let zero = TokenUsage(inputTokens: 0, outputTokens: 0, cacheCreationInputTokens: 0, cacheReadInputTokens: 0)

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheCreationInputTokens: lhs.cacheCreationInputTokens + rhs.cacheCreationInputTokens,
            cacheReadInputTokens: lhs.cacheReadInputTokens + rhs.cacheReadInputTokens
        )
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

struct ModelUsage: Identifiable {
    let model: String
    var tokens: TokenUsage
    var messageCount: Int

    var id: String { model }

    var displayName: String {
        model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-2025", with: "")
            .replacingOccurrences(of: "-2026", with: "")
    }
}

struct WindowUsage {
    var total: TokenUsage = .zero
    var messageCount: Int = 0
    var sessionCount: Int = 0
    var byModel: [String: ModelUsage] = [:]

    var modelBreakdown: [ModelUsage] {
        byModel.values.sorted { $0.tokens.totalTokens > $1.tokens.totalTokens }
    }

    mutating func add(tokens: TokenUsage, model: String) {
        total = total + tokens
        messageCount += 1
        if var existing = byModel[model] {
            existing.tokens = existing.tokens + tokens
            existing.messageCount += 1
            byModel[model] = existing
        } else {
            byModel[model] = ModelUsage(model: model, tokens: tokens, messageCount: 1)
        }
    }
}

struct UsageSnapshot {
    var fiveHour: WindowUsage = WindowUsage()
    var sevenDay: WindowUsage = WindowUsage()
    var today: WindowUsage = WindowUsage()
    var fiveHourWindow: RateLimitWindow.FiveHourWindow?
    var sevenDayWindow: RateLimitWindow.SevenDayWindow?
    var lastUpdated: Date = Date()
}

/// Parsed assistant message from a JSONL session file
struct SessionMessage {
    let timestamp: Date
    let model: String
    let usage: TokenUsage
}
