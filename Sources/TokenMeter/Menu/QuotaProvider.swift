import Foundation

/// The service a quota card belongs to, in the order the menu lists them.
enum QuotaProvider: String, CaseIterable {
    case gemini
    case claude
    case codex

    var name: String {
        switch self {
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    var symbolName: String {
        switch self {
        case .gemini: return "sparkle"
        case .claude: return "sparkles"
        case .codex: return "terminal"
        }
    }

    static func of(_ bucket: QuotaBucket) -> QuotaProvider {
        let id = bucket.modelId
        if id.hasPrefix("official-claude") { return .claude }
        if id.hasPrefix("official-codex") || id.hasPrefix("official-openai") { return .codex }
        return .gemini
    }

    /// Cards grouped by provider, providers in menu order, cards in the order they arrived.
    static func grouped(_ buckets: [QuotaBucket]) -> [(provider: QuotaProvider, buckets: [QuotaBucket])] {
        allCases.compactMap { provider in
            let members = buckets.filter { of($0) == provider }
            return members.isEmpty ? nil : (provider, members)
        }
    }

    /// The card's name without the provider prefix its section header already shows.
    static func shortName(for bucket: QuotaBucket) -> String {
        let prefix = of(bucket).name + " - "
        let name = bucket.displayName
        return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
    }
}
