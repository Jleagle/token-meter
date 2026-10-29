import Foundation

/// Which provider consumed quota between two refreshes.
enum UsageActivity {
    /// The provider whose window dropped the most since the previous refresh, nil when none dropped.
    static func reducedProvider(from previous: [QuotaBucket], to current: [QuotaBucket]) -> QuotaProvider? {
        let before = Dictionary(
            previous.compactMap { bucket in bucket.remainingFraction.map { (bucket.modelId, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let drops: [(provider: QuotaProvider, drop: Double)] = current.compactMap { bucket in
            guard bucket.unavailableReason == nil,
                  let now = bucket.remainingFraction,
                  let earlier = before[bucket.modelId],
                  now < earlier else { return nil }
            return (QuotaProvider.of(bucket), earlier - now)
        }
        return drops.max(by: { $0.drop < $1.drop })?.provider
    }
}
