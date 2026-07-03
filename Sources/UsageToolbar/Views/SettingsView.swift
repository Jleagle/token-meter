import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var quotaService = QuotaService.shared
    @Environment(\.presentationMode) var presentationMode
    @State private var budgetString: String = ""
    @State private var openAiBudgetString: String = ""
    
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
            
            VStack(alignment: .leading, spacing: 3) {
                Text("UsageToolbar Settings")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Configure menu bar display, Anthropic CLI & API tracking")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
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
                Text("Claude Pro • 5-Hour Limit").tag("official-claude-cli-5h")
                Text("Anthropic API • USD Budget").tag("official-anthropic-api")
                Text("Codex / OpenAI • 5-Hour Limit").tag("official-codex-cli-5h")
                Text("OpenAI API • USD Budget").tag("official-openai-api")
            }
        }
        .labelsHidden()
        .pickerStyle(MenuPickerStyle())
        .font(.system(size: 13))
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    
    private var menuBarDisplaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("MENU BAR ICON & PERCENTAGE")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.9))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Show Remaining Percentage For:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                
                menuBarPicker
            }
            
            Text("Displays a live percentage right next to your menu bar icon so you can track usage without clicking.")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    
    private var refreshRateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("REFRESH & POLLING RATE")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.9))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Automatic Quota Polling Interval:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                
                refreshRatePicker
            }
            
            Text("Controls how frequently the app queries local IDE servers and APIs in the background to update your progress bars and percentage badge.")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var claudeApiFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Anthropic API Key")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                
                SecureField("sk-ant-...", text: $settings.anthropicApiKey)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Monthly Dollar Budget ($ USD)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                
                TextField("50.00", text: $budgetString)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .onChange(of: budgetString) { val in
                        if let num = Double(val), num > 0 {
                            settings.monthlyBudget = num
                        }
                    }
            }
        }
    }
    
    private var claudeApiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CLAUDE DEVELOPER API")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(red: 0.9, green: 0.6, blue: 0.4))
            
            claudeApiFields
            
            Text("Queries console.anthropic.com to track your monthly API spend against your budget.")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var codexApiFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("OpenAI / Codex API Key")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                
                SecureField("sk-... or sk-proj-...", text: $settings.openAiApiKey)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Monthly Dollar Budget ($ USD)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                
                TextField("50.00", text: $openAiBudgetString)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13, design: .monospaced))
                    .padding(10)
                    .background(Color.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .onChange(of: openAiBudgetString) { val in
                        if let num = Double(val), num > 0 {
                            settings.openAiMonthlyBudget = num
                        }
                    }
            }
        }
    }
    
    private var codexApiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CODEX DEVELOPER API")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(red: 0.1, green: 0.75, blue: 0.55))
            
            codexApiFields
            
            Text("Queries platform.openai.com to track your monthly API spend against your budget.")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var buttonsSection: some View {
        HStack {
            Button("Close") {
                if let window = NSApplication.shared.windows.first(where: { $0.title == "UsageToolbar Settings" }) {
                    window.close()
                }
            }
            .buttonStyle(PlainButtonStyle())
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.gray)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Spacer()
            
            Button(action: {
                Task {
                    await QuotaService.shared.refresh()
                }
                if let window = NSApplication.shared.windows.first(where: { $0.title == "UsageToolbar Settings" }) {
                    window.close()
                }
            }) {
                Text("Save & Refresh Quota")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.9, green: 0.5, blue: 0.3), Color(red: 0.8, green: 0.35, blue: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color(red: 0.85, green: 0.45, blue: 0.3).opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                headerSection
                
                Divider().background(Color.white.opacity(0.15))
                
                menuBarDisplaySection
                
                refreshRateSection
                
                claudeApiSection
                
                codexApiSection
                
                Spacer(minLength: 4)
                
                Divider().background(Color.white.opacity(0.15))
                
                buttonsSection
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 600)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
        .onAppear {
            budgetString = String(format: "%.2f", settings.monthlyBudget)
            openAiBudgetString = String(format: "%.2f", settings.openAiMonthlyBudget)
        }
    }
}
