import Foundation

/// The number shown for a quota window: percent left, or the burn rate when that mode is on.
enum QuotaDisplay {
    static func percentText(for bucket: QuotaBucket, paceMode: Bool) -> String {
        if bucket.unavailableReason != nil { return "—" }
        return paceMode ? "\(bucket.effectivePacePercentage)%" : "\(bucket.remainingPercentage)%"
    }

    /// The countdown to the window's reset, with the share of the window still ahead when its
    /// length is known.
    static func resetText(for bucket: QuotaBucket, now: Date) -> String {
        guard let reset = bucket.resetDate else { return "Reset time unknown" }
        let remaining = reset.timeIntervalSince(now)
        guard remaining > 0 else { return "Resetting now" }
        var text = "Resets in \(format(remaining))"
        if let duration = bucket.windowDuration {
            let percent = Int((min(1, remaining / duration) * 100).rounded())
            text += " (\(percent)%)"
        }
        return text
    }

    private static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
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
