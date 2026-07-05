import SwiftUI

struct PopoverRootView: View {
    @StateObject private var service = QuotaService.shared
    
    private var antigravityBuckets: [QuotaBucket] {
        service.buckets
            .filter { !$0.modelId.hasPrefix("official-") }
            .sorted {
                if $0.remainingPercentage == $1.remainingPercentage {
                    return $0.displayName < $1.displayName
                }
                return $0.remainingPercentage < $1.remainingPercentage
            }
    }
    
    private var officialClaudeBuckets: [QuotaBucket] {
        service.buckets
            .filter { $0.modelId.hasPrefix("official-claude") || $0.modelId == "official-anthropic-api" }
            .sorted {
                if $0.remainingPercentage == $1.remainingPercentage {
                    return $0.displayName < $1.displayName
                }
                return $0.remainingPercentage < $1.remainingPercentage
            }
    }
    
    private var officialCodexBuckets: [QuotaBucket] {
        service.buckets
            .filter { $0.modelId.hasPrefix("official-codex") || $0.modelId == "official-openai-api" }
            .sorted {
                if $0.remainingPercentage == $1.remainingPercentage {
                    return $0.displayName < $1.displayName
                }
                return $0.remainingPercentage < $1.remainingPercentage
            }
    }
    
    private var errorStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.red)
            
            Text("Connection Error")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            
            if let err = service.errorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            
            Button(action: {
                Task {
                    await service.refresh()
                }
            }) {
                Text("Retry Connection")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 4)
        }
        .padding(.vertical, 30)
    }
    
    private var loadingStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.9)
            
            Text("Fetching live usage & loading bars...")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 40)
    }
    
    @ViewBuilder
    private var bucketsListView: some View {
        if !antigravityBuckets.isEmpty {
            SectionHeaderView(
                title: "Antigravity",
                icon: "cpu.fill",
                color: Color(red: 0.0, green: 0.8, blue: 0.9)
            )
            
            ForEach(antigravityBuckets) { bucket in
                ModelCardView(bucket: bucket)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        
        if !officialClaudeBuckets.isEmpty {
            if !antigravityBuckets.isEmpty {
                Spacer().frame(height: 6)
            }
            
            SectionHeaderView(
                title: "Claude",
                icon: "sparkle",
                color: Color(red: 0.85, green: 0.45, blue: 0.3)
            )
            
            ForEach(officialClaudeBuckets) { bucket in
                ModelCardView(bucket: bucket)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        
        if !officialCodexBuckets.isEmpty {
            if !antigravityBuckets.isEmpty || !officialClaudeBuckets.isEmpty {
                Spacer().frame(height: 6)
            }
            
            SectionHeaderView(
                title: "Codex",
                icon: "bolt.shield.fill",
                color: Color(red: 0.1, green: 0.75, blue: 0.55)
            )
            
            ForEach(officialCodexBuckets) { bucket in
                ModelCardView(bucket: bucket)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }
    
    private var maxContentHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return max(400, screenHeight - 140)
    }
    
    private var contentArea: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                if service.errorMessage != nil && service.buckets.isEmpty {
                    errorStateView
                } else if service.buckets.isEmpty {
                    loadingStateView
                } else {
                    bucketsListView
                }
            }
            .padding(14)
        }
        .frame(maxHeight: maxContentHeight)
    }
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)
                .edgesIgnoringSafeArea(.all)
            
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                HeaderView(service: service)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                contentArea
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                FooterView(service: service)
            }
        }
        .frame(width: 330)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

struct SectionHeaderView: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
            
            VStack {
                Divider().background(color.opacity(0.35))
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
        .padding(.horizontal, 4)
    }
}
