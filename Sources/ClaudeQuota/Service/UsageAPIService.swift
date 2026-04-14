import Foundation

/// Response from GET https://api.anthropic.com/api/oauth/usage
struct UsageAPIResponse: Codable {
    let fiveHour: WindowQuota
    let sevenDay: WindowQuota

    struct WindowQuota: Codable {
        let utilization: Double    // percentage, e.g. 6.0 = 6%
        let resetsAt: String       // ISO 8601 timestamp

        var resetsAtDate: Date? {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: resetsAt) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: resetsAt)
        }

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

/// Manages OAuth token lifecycle and usage API calls.
actor UsageAPIService {
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let tokenURL = URL(string: "https://api.anthropic.com/v1/oauth/token")!
    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// Cached access token (may be refreshed independently of keychain)
    private var cachedAccessToken: String?
    private var cachedTokenExpiry: Date?

    /// Fetch usage, handling token refresh automatically.
    func fetchUsage(credentials: ClaudeCredentials) async throws -> UsageAPIResponse {
        let token = try await getValidToken(credentials: credentials)

        do {
            return try await callUsageAPI(token: token)
        } catch UsageAPIError.unauthorized {
            // Token was rejected — force refresh
            let freshToken = try await refreshToken(credentials: credentials)
            return try await callUsageAPI(token: freshToken)
        }
    }

    private func getValidToken(credentials: ClaudeCredentials) async throws -> String {
        // Use cached token if still valid (with 60s buffer)
        if let cached = cachedAccessToken, let expiry = cachedTokenExpiry,
           expiry > Date().addingTimeInterval(60) {
            return cached
        }

        // Check if keychain token is still valid
        if let token = credentials.accessToken,
           let expiry = credentials.expiresAt, expiry > Date().addingTimeInterval(60) {
            cachedAccessToken = token
            cachedTokenExpiry = expiry
            return token
        }

        // Need to refresh
        return try await refreshToken(credentials: credentials)
    }

    private func refreshToken(credentials: ClaudeCredentials) async throws -> String {
        guard let refreshToken = credentials.refreshToken else {
            throw UsageAPIError.noRefreshToken
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw UsageAPIError.tokenRefreshFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            throw UsageAPIError.tokenRefreshFailed
        }

        let expiresIn = json["expires_in"] as? Int ?? 28800
        cachedAccessToken = newAccessToken
        cachedTokenExpiry = Date().addingTimeInterval(Double(expiresIn))

        // Save new tokens to keychain — refresh tokens are single-use,
        // so we MUST persist the replacement or future refreshes will fail.
        let newRefreshToken = json["refresh_token"] as? String
        Self.updateKeychainTokens(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
            expiresIn: expiresIn
        )

        return newAccessToken
    }

    /// Update access + refresh tokens in the keychain.
    private static func updateKeychainTokens(accessToken: String, refreshToken: String?, expiresIn: Int) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var oauth = json["claudeAiOauth"] as? [String: Any] else {
            return
        }

        oauth["accessToken"] = accessToken
        if let refreshToken = refreshToken {
            oauth["refreshToken"] = refreshToken
        }
        oauth["expiresAt"] = (Date().timeIntervalSince1970 + Double(expiresIn)) * 1000
        json["claudeAiOauth"] = oauth

        guard let updatedData = try? JSONSerialization.data(withJSONObject: json) else { return }

        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: updatedData,
        ]
        SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
    }

    private func callUsageAPI(token: String) async throws -> UsageAPIResponse {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageAPIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw UsageAPIError.unauthorized
        }

        if httpResponse.statusCode == 429 {
            throw UsageAPIError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw UsageAPIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(UsageAPIResponse.self, from: data)
    }
}

enum UsageAPIError: Error, LocalizedError {
    case noToken
    case noRefreshToken
    case unauthorized
    case invalidResponse
    case httpError(Int)
    case tokenRefreshFailed
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .noToken: return "No OAuth token"
        case .noRefreshToken: return "No refresh token"
        case .unauthorized: return "Auth failed"
        case .invalidResponse: return "Invalid response"
        case .httpError(let code): return "HTTP \(code)"
        case .tokenRefreshFailed: return "Token refresh failed"
        case .rateLimited: return "Rate limited, retrying..."
        }
    }
}
