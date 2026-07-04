import Foundation
import SwiftUI

// MARK: - Quota Models

struct QuotaResponse: Codable {
    let buckets: [QuotaBucket]?
    let error: QuotaError?
}

struct QuotaError: Codable {
    let code: Int?
    let message: String?
    let status: String?
}

struct QuotaBucket: Codable, Identifiable {
    let resetTime: String?
    let tokenType: String?
    let modelId: String
    let remainingFraction: Double?
    let remainingAmount: Int?
    let maxAmount: Int?
    var customDisplayName: String? = nil
    
    var id: String { modelId }
    
    var displayName: String {
        if let custom = customDisplayName {
            return custom
        }
        switch modelId.lowercased() {
        case "gemini-3.1-pro-high", "gemini-3.1-pro":
            return "Gemini 3.1 Pro (High)"
        case "gemini-3.1-pro-preview":
            return "Gemini 3.1 Pro Preview"
        case "gemini-3.1-flash-lite":
            return "Gemini 3.1 Flash-Lite"
        case "gemini-3.1-flash-lite-preview":
            return "Gemini 3.1 Flash-Lite Preview"
        case "gemini-3-pro-preview":
            return "Gemini 3 Pro Preview"
        case "gemini-3-flash-preview":
            return "Gemini 3 Flash Preview"
        case "gemini-2.5-pro":
            return "Gemini 2.5 Pro"
        case "gemini-2.5-flash":
            return "Gemini 2.5 Flash"
        case "gemini-2.5-flash-lite":
            return "Gemini 2.5 Flash-Lite"
        case "gemini-2.0-pro", "gemini-2.0-pro-exp":
            return "Gemini 2.0 Pro"
        case "gemini-2.0-flash", "gemini-2.0-flash-exp":
            return "Gemini 2.0 Flash"
        case "gemini-2.0-flash-thinking", "gemini-2.0-flash-thinking-exp":
            return "Gemini 2.0 Flash Thinking"
        case "gemini-1.5-pro", "gemini-1.5-pro-5h", "gemini-1.5-pro-latest":
            return "Gemini 1.5 Pro"
        case "gemini-1.5-flash", "gemini-1.5-flash-5h", "gemini-1.5-flash-latest":
            return "Gemini 1.5 Flash"
        case "gemini-pro", "gemini-pro-5h", "gemini-pro-latest":
            return "Gemini Pro"
        case "gemini-flash", "gemini-flash-5h", "gemini-flash-latest":
            return "Gemini Flash"
        case "gemini-ultra", "gemini-ultra-weekly", "gemini-ultra-latest":
            return "Gemini Ultra"
        case "claude-3-7-sonnet", "claude-sonnet-3-7":
            return "Claude 3.7 Sonnet"
        case "claude-3-5-sonnet", "claude-sonnet-3-5":
            return "Claude 3.5 Sonnet"
        case "claude-opus-4-6-thinking", "claude-4-6-opus":
            return "Claude Opus 4.6 (Thinking)"
        case "official-codex-cli-5h":
            return "Codex / OpenAI • 5-Hour Limit"
        case "official-openai-api":
            return "OpenAI API • USD Budget"
        default:
            return modelId
                .split(separator: "-")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }
    
    var remainingPercentage: Int {
        if let fraction = remainingFraction {
            return Int(round(fraction * 100.0))
        }
        if let remaining = remainingAmount, let max = maxAmount, max > 0 {
            return Int(round((Double(remaining) / Double(max)) * 100.0))
        }
        return 100
    }
    
    var progressColor: Color {
        let pct = remainingPercentage
        if pct >= 70 {
            return Color(red: 0.2, green: 0.85, blue: 0.5) // Vibrant Green
        } else if pct >= 30 {
            return Color(red: 0.98, green: 0.7, blue: 0.2) // Amber Gold
        } else {
            return Color(red: 0.95, green: 0.3, blue: 0.4) // Coral Red
        }
    }
    
    var progressGradient: LinearGradient {
        let pct = remainingPercentage
        if pct >= 70 {
            return LinearGradient(
                colors: [Color(red: 0.0, green: 0.95, blue: 0.8), Color(red: 0.2, green: 0.8, blue: 0.4)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else if pct >= 30 {
            return LinearGradient(
                colors: [Color(red: 0.98, green: 0.85, blue: 0.3), Color(red: 0.98, green: 0.55, blue: 0.2)],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.9, green: 0.1, blue: 0.3)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    var resetDate: Date? {
        guard let resetTime = resetTime else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: resetTime) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: resetTime)
    }
}

// MARK: - Summary Quota Models

struct QuotaSummaryResponseWrapper: Codable {
    let response: QuotaSummaryPayload?
}

struct QuotaSummaryPayload: Codable {
    let groups: [QuotaSummaryGroup]?
}

struct QuotaSummaryGroup: Codable {
    let displayName: String?
    let description: String?
    let buckets: [QuotaSummaryBucket]?
}

struct QuotaSummaryBucket: Codable {
    let bucketId: String?
    let displayName: String?
    let description: String?
    let window: String?
    let remainingFraction: Double?
    let resetTime: String?
}

// MARK: - Code Assist Tier Models

struct TierResponse: Codable {
    let currentTier: TierDetail?
    let allowedTiers: [TierDetail]?
    let cloudaicompanionProject: String?
    let paidTier: TierDetail?
}

struct TierDetail: Codable {
    let id: String?
    let name: String?
    let description: String?
}

// MARK: - OAuth Models

struct OAuthTokenFile: Codable {
    let token: OAuthTokenDetail
}

struct OAuthTokenDetail: Codable {
    let access_token: String?
    let token_type: String?
    let refresh_token: String?
    let expiry: String?
}

struct OAuthRefreshResponse: Codable {
    let access_token: String
    let expires_in: Int?
    let token_type: String?
}
