import Foundation

/// The number shown for a quota window: percent left, or the burn rate when that mode is on.
enum QuotaDisplay {
    static func percentText(for bucket: QuotaBucket, paceMode: Bool) -> String {
        if bucket.unavailableReason != nil { return "—" }
        return paceMode ? "\(bucket.effectivePacePercentage)%" : "\(bucket.remainingPercentage)%"
    }

    /// The number for the menu bar. Nil shows the icon alone. "auto" follows the window most at
    /// risk: least left, or burning fastest in burn-rate mode.
    static func menuBarTitle(buckets: [QuotaBucket], selection: String, paceMode: Bool) -> String? {
        let target = selection.isEmpty ? "auto" : selection
        guard target != "none" else { return nil }
        let live = buckets.filter { $0.unavailableReason == nil }
        let chosen: QuotaBucket?
        if target == "auto" {
            chosen = paceMode
                ? live.max(by: { $0.effectivePacePercentage < $1.effectivePacePercentage })
                : live.min(by: { $0.remainingPercentage < $1.remainingPercentage })
        } else {
            chosen = live.first(where: { $0.modelId == target })
        }
        return chosen.map { percentText(for: $0, paceMode: paceMode) }
    }
}
