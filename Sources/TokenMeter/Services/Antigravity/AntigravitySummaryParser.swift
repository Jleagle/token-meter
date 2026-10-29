import Foundation

/// Turns `RetrieveUserQuotaSummary` responses into Gemini quota cards. The shared Gemini pool is
/// matched by exact bucket ID so a future bucket never silently joins it; the separate
/// "Gemini 4 Argon" group contributes its single weekly bucket when the plan reports one.
/// Antigravity's non-Gemini pool (`3p-5h`, `3p-weekly`) is ignored.
enum AntigravitySummaryParser {
    private struct GeminiBucket {
        let id: String
        let name: String
        let window: String
    }

    private static let geminiBuckets = [
        GeminiBucket(id: "gemini-5h", name: "Gemini - 5 Hour", window: "5h"),
        GeminiBucket(id: "gemini-weekly", name: "Gemini - Weekly", window: "weekly"),
    ]
    private static let argonGroupName = "Gemini 4 Argon"

    /// Merges one body per host, first usable bucket per ID wins. Nil when no body is a quota
    /// summary at all; an empty array when the summaries carry no usable Gemini buckets.
    static func buckets(from bodies: [Data]) -> [QuotaBucket]? {
        let groupSets = bodies.compactMap(groups(in:))
        guard !groupSets.isEmpty else { return nil }

        var pooled: [String: QuotaSummaryBucket] = [:]
        var argon: QuotaSummaryBucket?
        for groups in groupSets {
            for group in groups {
                if group.displayName == argonGroupName {
                    if argon == nil { argon = argonWeekly(in: group) }
                    continue
                }
                for bucket in group.buckets ?? [] {
                    guard let id = bucket.bucketId,
                          geminiBuckets.contains(where: { $0.id == id }),
                          pooled[id] == nil,
                          let fraction = bucket.remainingFraction, fraction.isFinite
                    else { continue }
                    pooled[id] = bucket
                }
            }
        }

        var result: [QuotaBucket] = []
        for spec in geminiBuckets {
            if let bucket = pooled[spec.id] {
                result.append(quotaBucket(bucket, name: spec.name, window: spec.window))
            }
        }
        if let argon {
            result.append(quotaBucket(argon, name: "Gemini - Argon Weekly", window: "weekly"))
        }
        return result
    }

    /// Group names with their bucket IDs, windows and fractions, for the diagnostics log.
    static func describe(_ bodies: [Data]) -> String {
        let groupSets = bodies.compactMap(groups(in:))
        guard !groupSets.isEmpty else { return "no quota summary in \(bodies.count) body(ies)" }
        return groupSets.flatMap { $0 }.map { group in
            let buckets = (group.buckets ?? []).map { bucket in
                "\(bucket.bucketId ?? "?")/\(bucket.window ?? "?")/\(bucket.remainingFraction.map { String($0) } ?? "nil")\(bucket.disabled == true ? "/disabled" : "")"
            }
            return "\(group.displayName ?? "?")[\(buckets.joined(separator: ", "))]"
        }.joined(separator: "; ")
    }

    /// Whether one body already carries a usable fraction for both Gemini buckets, so no other
    /// host's answer could change the result.
    static func isComplete(_ data: Data) -> Bool {
        guard let groups = groups(in: data) else { return false }
        let usable = Set(groups.filter { $0.displayName != argonGroupName }
            .flatMap { $0.buckets ?? [] }
            .compactMap { $0.remainingFraction?.isFinite == true ? $0.bucketId : nil })
        return geminiBuckets.allSatisfy { usable.contains($0.id) }
    }

    private static func groups(in data: Data) -> [QuotaSummaryGroup]? {
        guard let envelope = try? JSONDecoder().decode(QuotaSummaryEnvelope.self, from: data) else { return nil }
        return envelope.response?.groups ?? envelope.groups
    }

    private static func argonWeekly(in group: QuotaSummaryGroup) -> QuotaSummaryBucket? {
        let weekly = (group.buckets ?? []).filter { $0.window == "weekly" }
        guard weekly.count == 1, let bucket = weekly.first,
              let id = bucket.bucketId, !id.isEmpty,
              !geminiBuckets.contains(where: { $0.id == id }),
              bucket.disabled != true,
              let fraction = bucket.remainingFraction, fraction.isFinite
        else { return nil }
        return bucket
    }

    private static func quotaBucket(_ bucket: QuotaSummaryBucket, name: String, window: String) -> QuotaBucket {
        QuotaBucket(
            resetTime: bucket.resetTime,
            tokenType: window,
            modelId: bucket.bucketId ?? "",
            remainingFraction: bucket.remainingFraction,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: name
        )
    }
}
