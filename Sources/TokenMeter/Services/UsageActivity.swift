import Foundation

/// Which window consumed quota between two refreshes.
enum UsageActivity {
    /// The model id of the window that dropped the most since the previous refresh, nil when none dropped.
    static func reducedWindow(from previous: [QuotaBucket], to current: [QuotaBucket]) -> String? {
        let before = Dictionary(
            previous.compactMap { bucket in bucket.remainingFraction.map { (bucket.modelId, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let drops: [(modelId: String, drop: Double)] = current.compactMap { bucket in
            guard bucket.unavailableReason == nil,
                  let now = bucket.remainingFraction,
                  let earlier = before[bucket.modelId],
                  now < earlier else { return nil }
            return (bucket.modelId, earlier - now)
        }
        return drops.max(by: { $0.drop < $1.drop })?.modelId
    }
}
