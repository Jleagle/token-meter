import Foundation

/// Turns the `/api/oauth/usage` payload into Claude quota cards: the 5-hour and 7-day windows,
/// any model-scoped weekly limits from the `limits` array, and the Sonnet weekly window.
enum ClaudeUsageMapper {
    static func buckets(from data: Data) -> [QuotaBucket] {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        var buckets: [QuotaBucket] = []
        // Cards are Identifiable by modelId, so a window reported twice keeps its first form
        func add(_ bucket: QuotaBucket?) {
            guard let bucket, !buckets.contains(where: { $0.modelId == bucket.modelId }) else { return }
            buckets.append(bucket)
        }

        add(window(json["five_hour"], id: "official-claude-cli-5h", name: "Claude - 5 Hour", type: "5h"))
        add(window(json["seven_day"], id: "official-claude-weekly", name: "Claude - Weekly", type: "weekly"))
        for entry in (json["limits"] as? [Any]) ?? [] {
            guard let limit = entry as? [String: Any],
                  limit["kind"] as? String == "weekly_scoped",
                  let scope = limit["scope"] as? [String: Any],
                  let model = (scope["model"] as? [String: Any])?["display_name"] as? String,
                  !model.isEmpty,
                  let percent = (limit["percent"] as? NSNumber)?.doubleValue
            else { continue }
            add(bucket(
                id: "official-claude-weekly-\(slug(model))",
                name: "Claude - \(model) Weekly",
                type: "weekly",
                utilization: percent,
                resetsAt: limit["resets_at"]
            ))
        }
        add(window(json["seven_day_sonnet"], id: "official-claude-weekly-sonnet", name: "Claude - Sonnet Weekly", type: "weekly"))
        return buckets
    }

    private static func window(_ value: Any?, id: String, name: String, type: String) -> QuotaBucket? {
        guard let window = value as? [String: Any],
              let utilization = (window["utilization"] as? NSNumber)?.doubleValue
        else { return nil }
        return bucket(id: id, name: name, type: type, utilization: utilization, resetsAt: window["resets_at"])
    }

    private static func bucket(id: String, name: String, type: String, utilization: Double, resetsAt: Any?) -> QuotaBucket {
        QuotaBucket(
            resetTime: resetTime(resetsAt),
            tokenType: type,
            modelId: id,
            remainingFraction: max(0.0, min(1.0, (100.0 - utilization) / 100.0)),
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: name
        )
    }

    /// Reset times arrive as ISO 8601 strings on the windows and as epoch seconds on scoped limits.
    private static func resetTime(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let number = (value as? NSNumber)?.doubleValue, number.isFinite, number > 0 {
            let seconds = number > 1e11 ? number / 1000 : number
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
        }
        return nil
    }

    private static func slug(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    }
}
