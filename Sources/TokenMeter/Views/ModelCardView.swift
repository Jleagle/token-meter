import SwiftUI
import Combine

struct ModelCardView: View {
    let bucket: QuotaBucket
    @State private var timeString: String = "Calculating..."
    @State private var timer: AnyCancellable?
    @State private var animatedProgress: CGFloat = 0.0
    
    private var topRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(bucket.progressColor)
                
                Text(bucket.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Text("\(bucket.remainingPercentage)%")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(bucket.progressColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(bucket.progressColor.opacity(0.15))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(bucket.progressColor.opacity(0.3), lineWidth: 0.5)
                )
        }
    }
    
    private var middleRow: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 8)
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                
                // Progress Fill
                Capsule()
                    .fill(bucket.progressGradient)
                    .frame(width: max(8, geometry.size.width * animatedProgress), height: 8)
                    .shadow(color: bucket.progressColor.opacity(0.5), radius: 4, x: 0, y: 0)
            }
        }
        .frame(height: 8)
        .onAppear {
            updateProgress()
        }
        .onChange(of: bucket.remainingPercentage) { _ in
            updateProgress()
        }
        .onChange(of: bucket.remainingFraction ?? 0.0) { _ in
            updateProgress()
        }
    }
    
    private var bottomRow: some View {
        HStack(spacing: 5) {
            if bucket.remainingPercentage == 100 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: 0.2, green: 0.85, blue: 0.5))
                
                Text(bucket.tokenType == "usd" ? "Within Monthly Budget" : "Full Quota Available")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("Resets in \(timeString)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let type = bucket.tokenType {
                Text(type == "usd" ? "USD Budget" : type.capitalized)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow
            middleRow
            bottomRow
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
        .onAppear {
            updateTimeString()
            startTimer()
        }
        .onDisappear {
            timer?.cancel()
        }
    }
    
    private func updateProgress() {
        withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) {
            var fraction = bucket.remainingFraction ?? (Double(bucket.remainingPercentage) / 100.0)
            if fraction > 0.0 && fraction < 0.06 {
                fraction = 0.06 // ensure at least a visible 6% sliver when there are positive credits
            }
            animatedProgress = CGFloat(min(max(fraction, 0.0), 1.0))
        }
    }
    
    private func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                updateTimeString()
            }
    }
    
    private func updateTimeString() {
        guard let resetDate = bucket.resetDate else {
            timeString = "Unknown"
            return
        }
        
        let now = Date()
        let diff = resetDate.timeIntervalSince(now)
        
        if diff <= 0 {
            timeString = "Ready to Reset"
            return
        }
        
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        let seconds = Int(diff) % 60
        
        if hours > 0 {
            timeString = String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            timeString = String(format: "%dm %ds", minutes, seconds)
        } else {
            timeString = String(format: "%ds", seconds)
        }
    }
}
