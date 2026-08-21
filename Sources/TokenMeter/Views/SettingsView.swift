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
                Text("Configure menu bar display & percentage mode")
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
                ForEach(quotaService.buckets.filter { $0.unavailableReason == nil }) { bucket in
                    Text("\(bucket.displayName) (\(bucket.remainingPercentage)%)").tag(bucket.modelId)
                }
            } else {
                Divider()
                Text("Gemini - 5 Hour").tag("gemini-pro-5h")
                Text("Gemini - Weekly").tag("gemini-ultra-weekly")
                Text("Claude - 5 Hour").tag("official-claude-cli-5h")
                Text("Claude - Weekly").tag("official-claude-weekly")
                Text("Codex - 5 Hour").tag("official-codex-cli-5h")
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
    
    private var paceModeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PERCENTAGE MODE")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(NSColor.systemBlue))

            Toggle(isOn: $settings.usePaceMode) {
                Text("Show burn rate instead of remaining quota")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .toggleStyle(SwitchToggleStyle())

            Text("Burn rate compares usage against how much of the window has elapsed: 100% means you're on pace to exactly use your quota, 200% means you're burning it twice as fast, and 50% means you're only using half of what the window allows. The Auto menu bar option shows the fastest-burning model.")
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

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                headerSection
                
                Divider()
                
                menuBarDisplaySection

                paceModeSection

                Spacer(minLength: 4)
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
