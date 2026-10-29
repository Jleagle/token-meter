import SwiftUI
import Combine

/// One quota line in the status menu: provider icon, window name, percent used,
/// a thin bar, and the time until the window resets.
struct QuotaRowView: View {
    let bucket: QuotaBucket
    @ObservedObject var settings: SettingsManager
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isUnavailable: Bool { bucket.unavailableReason != nil }

    private var percentText: String {
        QuotaDisplay.percentText(for: bucket, paceMode: settings.usePaceMode)
    }

    private var accent: Color {
        if isUnavailable { return .secondary }
        if settings.usePaceMode { return QuotaBucket.paceColor(for: bucket.effectivePacePercentage) }
        return bucket.progressColor
    }

    // The bar shows what is left, matching the number beside it
    private var remainingFraction: CGFloat {
        if isUnavailable { return 0 }
        let remaining = bucket.remainingFraction ?? Double(bucket.remainingPercentage) / 100
        return CGFloat(min(1, max(0, remaining)))
    }

    private var detailText: String {
        if let reason = bucket.unavailableReason { return reason }
        if let note = bucket.staleNote { return note }
        return QuotaDisplay.resetText(for: bucket, now: now)
    }

    private var detailColor: Color {
        bucket.staleNote != nil && !isUnavailable ? Color(NSColor.systemOrange) : .secondary
    }

    @ViewBuilder
    private var icon: some View {
        let provider = QuotaProvider.of(bucket)
        if let logo = ProviderLogo.image(for: provider) {
            Image(nsImage: logo)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
        } else {
            Image(systemName: provider.symbolName)
                .font(.system(size: 12, weight: .semibold))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                icon
                    .foregroundColor(accent)
                    .frame(width: 16)
                Text(QuotaProvider.shortName(for: bucket))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(percentText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    if remainingFraction > 0 {
                        Capsule()
                            .fill(accent)
                            .frame(width: max(6, geometry.size.width * remainingFraction))
                    }
                }
            }
            .frame(height: 6)
            Text(detailText)
                .font(.system(size: 11))
                .foregroundColor(detailColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: StatusMenuBuilder.rowWidth, alignment: .leading)
        .opacity(isUnavailable ? 0.7 : 1)
        .onReceive(ticker) { now = $0 }
    }
}
