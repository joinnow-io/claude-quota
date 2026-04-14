import Foundation
import Security

struct ClaudeCredentials {
    let subscriptionType: SubscriptionType?
    let rateLimitTier: String?
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Date?

    var tierMultiplier: Int {
        PlanLimits.parseMultiplier(from: rateLimitTier)
    }

    var tierDisplayName: String {
        guard let sub = subscriptionType else { return "Unknown" }
        let multiplier = tierMultiplier
        if multiplier > 1 {
            return "\(sub.displayName) (\(multiplier)x)"
        }
        return sub.displayName
    }
}

enum KeychainService {
    private static let serviceName = "Claude Code-credentials"

    /// Read Claude Code OAuth credentials from the macOS Keychain.
    static func readCredentials() -> ClaudeCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any] else {
            return nil
        }

        let subType = (oauth["subscriptionType"] as? String).flatMap { SubscriptionType(rawValue: $0) }
        let tier = oauth["rateLimitTier"] as? String
        let accessToken = oauth["accessToken"] as? String
        let refreshToken = oauth["refreshToken"] as? String
        let expiresAtMs = oauth["expiresAt"] as? Double
        let expiresAt = expiresAtMs.map { Date(timeIntervalSince1970: $0 / 1000.0) }

        return ClaudeCredentials(
            subscriptionType: subType,
            rateLimitTier: tier,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }
}
