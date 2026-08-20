import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var quotaService = QuotaService.shared
    @Environment(\.presentationMode) var presentationMode
    
    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 0.85, green: 0.45, blue: 0.3)) // Anthropic warm orange/terracotta
                    .frame(width: 40, height: 40)
                    .shadow(color: Color(red: 0.85, green: 0.45, blue: 0.3).opacity(0.4), radius: 6, x: 0, y: 2)
                
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("TokenMeter Settings")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                }
                Text("Configure menu bar display & refresh rate")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
    
    private var menuBarPicker: some View {
        Picker("", selection: $settings.toolbarDisplayModelId) {
            Text("⚡️ Auto (Lowest Available Quota)").tag("auto")
            Text("❌ Icon Only (No Percentage)").tag("none")
            if !quotaService.buckets.isEmpty {
                Divider()
                ForEach(quotaService.buckets) { bucket in
                    Text("\(bucket.displayName) (\(bucket.remainingPercentage)%)").tag(bucket.modelId)
                }
            } else {
                Divider()
                Text("Gemini • 5-Hour Limit").tag("gemini-pro-5h")
                Text("Gemini • Weekly Limit").tag("gemini-ultra-weekly")
                Text("Claude • 5-Hour Limit").tag("official-claude-cli-5h")
                Text("Claude • Weekly Limit").tag("official-claude-weekly")
                Text("Codex / OpenAI • 5-Hour Limit").tag("official-codex-cli-5h")
            }
        }
        .labelsHidden()
        .pickerStyle(MenuPickerStyle())
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var menuBarDisplaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MENU BAR ICON & PERCENTAGE")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(NSColor.systemBlue))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Show Remaining Percentage For:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                menuBarPicker
            }
            
            Text("Displays a live percentage right next to your menu bar icon so you can track usage without clicking.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    private var refreshRatePicker: some View {
        Picker("", selection: $settings.pollingRateSeconds) {
            Text("⚡️ 15 Seconds (Very Fast)").tag(15)
            Text("🚀 30 Seconds (Fast)").tag(30)
            Text("⏱️ 1 Minute (Standard • 60s)").tag(60)
            Text("🕒 2 Minutes (120s)").tag(120)
            Text("🕔 5 Minutes (300s)").tag(300)
            Text("🕙 10 Minutes (600s)").tag(600)
            Text("🕠 30 Minutes (1800s)").tag(1800)
        }
        .labelsHidden()
        .pickerStyle(MenuPickerStyle())
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var refreshRateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("REFRESH & POLLING RATE")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(NSColor.systemBlue))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Automatic Quota Polling Interval:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                refreshRatePicker
            }
            
            Text("Controls how frequently the app queries local IDE servers and APIs in the background to update your progress bars and percentage badge.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    private var buttonsSection: some View {
        HStack {
            Button("Close") {
                if let window = NSApplication.shared.windows.first(where: { $0.title == "TokenMeter Settings" }) {
                    window.close()
                }
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            Button("Save & Refresh Quota") {
                Task {
                    await QuotaService.shared.refresh()
                }
                if let window = NSApplication.shared.windows.first(where: { $0.title == "TokenMeter Settings" }) {
                    window.close()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                headerSection
                
                Divider()
                
                menuBarDisplaySection

                refreshRateSection

                Spacer(minLength: 4)
                
                Divider()
                
                buttonsSection
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
