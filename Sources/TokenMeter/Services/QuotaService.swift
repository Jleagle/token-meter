import Foundation
import Combine
import SwiftUI

@MainActor
class QuotaService: ObservableObject {
    static let shared = QuotaService()
    
    @Published var buckets: [QuotaBucket] = []
    @Published var currentTierName: String = "Gemini Code Assist"
    @Published var isLoading: Bool = false
    @Published var lastUpdated: Date? = nil
    @Published var errorMessage: String? = nil
    @Published var autoRefreshRemaining: Int = 60
    
    private var timerCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    
    private init() {
        startAutoRefreshTimer()
        SettingsManager.shared.$pollingRateSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newRate in
                guard let self = self else { return }
                if self.autoRefreshRemaining > newRate {
                    self.autoRefreshRemaining = newRate
                }
            }
            .store(in: &cancellables)
            
        Task {
            await refresh()
        }
    }
    
    func startAutoRefreshTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.autoRefreshRemaining > 1 {
                    self.autoRefreshRemaining -= 1
                } else {
                    self.autoRefreshRemaining = SettingsManager.shared.pollingRateSeconds
                    Task {
                        await self.refresh()
                    }
                }
            }
    }
    
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            // 1. Try fetching Quota Summary from local Antigravity Language Server
            var agyBuckets: [QuotaBucket] = []
            if let summaryBuckets = await fetchFromLanguageServer(), !summaryBuckets.isEmpty {
                agyBuckets = summaryBuckets
            } else {
                // If local language server is dormant, wake it up and retry
                wakeUpLanguageServer()
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 sec
                
                if let summaryBuckets = await fetchFromLanguageServer(), !summaryBuckets.isEmpty {
                    agyBuckets = summaryBuckets
                }
            }
            
            // 2. Fetch Official Claude Buckets (CLI & API Key)
            let claudeBuckets = await fetchOfficialClaudeBuckets()
            
            // 3. Fetch Official Codex / OpenAI Buckets (CLI & API Key)
            let codexBuckets = await fetchOfficialCodexBuckets()
            
            let combined = agyBuckets + claudeBuckets + codexBuckets
            if combined.isEmpty {
                if agyBuckets.isEmpty {
                    throw NSError(domain: "QuotaService", code: -3, userInfo: [NSLocalizedDescriptionKey: "No local language server found running on port 4040/4041."])
                } else {
                    throw NSError(domain: "QuotaService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No quota usage data returned."])
                }
            }
            
            self.buckets = combined
            self.errorMessage = nil
            self.lastUpdated = Date()
            self.autoRefreshRemaining = SettingsManager.shared.pollingRateSeconds
            
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        self.isLoading = false
    }
    
    // MARK: - Official Claude Integration
    
    private func fetchOfficialClaudeBuckets() async -> [QuotaBucket] {
        var buckets: [QuotaBucket] = []
        let settings = SettingsManager.shared
        
        // 1. Official Claude CLI / Subscription (5-Hour Window)
        let cliBucket = QuotaBucket(
            resetTime: calculateFiveHourResetTime(),
            tokenType: "5h",
            modelId: "official-claude-cli-5h",
            remainingFraction: 1.0,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: "Claude Pro • 5-Hour Limit"
        )
        buckets.append(cliBucket)
        
        // 2. Official Anthropic API Key (Dollar Spend / Budget)
        let apiKey = settings.anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            let budget = settings.monthlyBudget > 0 ? settings.monthlyBudget : 50.0
            let spent = await fetchAnthropicApiSpend(apiKey: apiKey)
            let remaining = max(0.0, budget - spent)
            let fraction = max(0.0, min(1.0, remaining / budget))
            
            let spentStr = String(format: "$%.2f", spent)
            let budgetStr = String(format: "$%.2f", budget)
            
            let apiBucket = QuotaBucket(
                resetTime: calculateNextMonthResetTime(),
                tokenType: "usd",
                modelId: "official-anthropic-api",
                remainingFraction: fraction,
                remainingAmount: Int(remaining * 100),
                maxAmount: Int(budget * 100),
                customDisplayName: "Anthropic API • \(spentStr) / \(budgetStr)"
            )
            buckets.append(apiBucket)
        }
        
        return buckets
    }
    
    private func fetchAnthropicApiSpend(apiKey: String) async -> Double {
        guard let url = URL(string: "https://api.anthropic.com/v1/organizations/cost") else { return 0.0 }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.timeoutInterval = 4.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let totalCost = json["total_cost"] as? Double {
                    return totalCost
                }
            }
        } catch {
            // ignore
        }
        return 0.0
    }
    
    // MARK: - Official Codex / OpenAI Integration
    
    private func fetchOfficialCodexBuckets() async -> [QuotaBucket] {
        var buckets: [QuotaBucket] = []
        let settings = SettingsManager.shared
        
        // 1. Official Codex / OpenAI CLI & Pro (5-Hour Window)
        let (fraction, resetTimeStr, planName) = await fetchCodexCliUsage()
        let cliBucket = QuotaBucket(
            resetTime: resetTimeStr,
            tokenType: "5h",
            modelId: "official-codex-cli-5h",
            remainingFraction: fraction,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: planName
        )
        buckets.append(cliBucket)
        
        // 2. Official OpenAI / Codex API Key (Dollar Spend / Budget)
        let apiKey = settings.openAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            let budget = settings.openAiMonthlyBudget > 0 ? settings.openAiMonthlyBudget : 50.0
            let spent = await fetchOpenAiApiSpend(apiKey: apiKey)
            let remaining = max(0.0, budget - spent)
            let fraction = max(0.0, min(1.0, remaining / budget))
            
            let spentStr = String(format: "$%.2f", spent)
            let budgetStr = String(format: "$%.2f", budget)
            
            let apiBucket = QuotaBucket(
                resetTime: calculateNextMonthResetTime(),
                tokenType: "usd",
                modelId: "official-openai-api",
                remainingFraction: fraction,
                remainingAmount: Int(remaining * 100),
                maxAmount: Int(budget * 100),
                customDisplayName: "OpenAI API • \(spentStr) / \(budgetStr)"
            )
            buckets.append(apiBucket)
        }
        
        return buckets
    }
    
    private func fetchCodexCliUsage() async -> (Double, String, String) {
        var fraction = 1.0
        var resetTimeStr = calculateFiveHourResetTime()
        var planName = "Codex / OpenAI • 5-Hour Limit"
        
        let authPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty else {
            return (fraction, resetTimeStr, planName)
        }
        
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            return (fraction, resetTimeStr, planName)
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 4.0
            
            let (responseData, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                if let usageJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                    if let planType = usageJson["plan_type"] as? String {
                        if planType.lowercased() == "plus" {
                            planName = "Codex Plus • 5-Hour Limit"
                        } else if planType.lowercased() == "pro" {
                            planName = "Codex Pro • 5-Hour Limit"
                        } else if planType.lowercased() == "free" {
                            planName = "Codex Free • Limit"
                        }
                    }
                    
                    if let rateLimit = usageJson["rate_limit"] as? [String: Any] {
                        if let primary = rateLimit["primary_window"] as? [String: Any] {
                            if let usedPct = (primary["used_percent"] as? NSNumber)?.doubleValue {
                                fraction = max(0.0, min(1.0, (100.0 - usedPct) / 100.0))
                            }
                            if let resetAt = (primary["reset_at"] as? NSNumber)?.doubleValue, resetAt > 0 {
                                let resetDate = Date(timeIntervalSince1970: resetAt)
                                let formatter = ISO8601DateFormatter()
                                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                                resetTimeStr = formatter.string(from: resetDate)
                            }
                        }
                        if let secondary = rateLimit["secondary_window"] as? [String: Any] {
                            if let usedPct = (secondary["used_percent"] as? NSNumber)?.doubleValue {
                                let secFraction = max(0.0, min(1.0, (100.0 - usedPct) / 100.0))
                                if secFraction < fraction {
                                    fraction = secFraction
                                    if let resetAt = (secondary["reset_at"] as? NSNumber)?.doubleValue, resetAt > 0 {
                                        let resetDate = Date(timeIntervalSince1970: resetAt)
                                        let formatter = ISO8601DateFormatter()
                                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                                        resetTimeStr = formatter.string(from: resetDate)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            // ignore
        }
        
        return (fraction, resetTimeStr, planName)
    }
    
    private func fetchOpenAiApiSpend(apiKey: String) async -> Double {
        guard let url = URL(string: "https://api.openai.com/v1/dashboard/billing/usage") else { return 0.0 }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 4.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let totalUsage = json["total_usage"] as? Double {
                    return totalUsage / 100.0 // OpenAI dashboard reports in cents
                }
            }
        } catch {
            // ignore
        }
        return 0.0
    }
    
    private func calculateFiveHourResetTime() -> String {
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let currentHour = components.hour ?? 0
        let nextBlockHour = ((currentHour / 5) + 1) * 5
        
        if nextBlockHour >= 24 {
            components.day = (components.day ?? 0) + 1
            components.hour = nextBlockHour - 24
        } else {
            components.hour = nextBlockHour
        }
        components.minute = 0
        components.second = 0
        
        if let nextDate = calendar.date(from: components) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: nextDate)
        }
        return ""
    }
    
    private func calculateNextMonthResetTime() -> String {
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: now)
        components.month = (components.month ?? 1) + 1
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        if let nextMonth = calendar.date(from: components) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: nextMonth)
        }
        return ""
    }
    
    // MARK: - Local Language Server Integration
    
    private func fetchFromLanguageServer() async -> [QuotaBucket]? {
        let ports = findLanguageServerPorts()
        for port in ports {
            guard let url = URL(string: "http://localhost:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = "{\"forceRefresh\": true}".data(using: .utf8)
                request.timeoutInterval = 3.0
                
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                    if let buckets = parseSummaryResponse(data: data), !buckets.isEmpty {
                        return buckets
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
    
    private func parseSummaryResponse(data: Data) -> [QuotaBucket]? {
        do {
            let wrapper = try JSONDecoder().decode(QuotaSummaryResponseWrapper.self, from: data)
            guard let groups = wrapper.response?.groups else { return nil }
            
            var resultBuckets: [QuotaBucket] = []
            for group in groups {
                let rawName = group.displayName ?? "Models"
                let groupName = rawName.replacingOccurrences(of: " models", with: "")
                                       .replacingOccurrences(of: " Models", with: "")
                if let sumBuckets = group.buckets {
                    for sb in sumBuckets {
                        let bId = sb.bucketId ?? UUID().uuidString
                        let win = sb.window ?? ""
                        let winLabel = win == "weekly" ? "Weekly Limit" : (win == "5h" ? "5-Hour Limit" : "")
                        
                        var baseName = ""
                        if let bName = sb.displayName, !bName.isEmpty, bName.lowercased() != "default", bName.lowercased() != "models", bName.lowercased() != "gemini", bName.lowercased() != "gemini models" {
                            baseName = bName
                            if !baseName.lowercased().hasPrefix(groupName.lowercased()) && !baseName.lowercased().hasPrefix("gemini") && !baseName.lowercased().hasPrefix("claude") {
                                baseName = "\(groupName) \(baseName)"
                            }
                        } else {
                            let tempBucket = QuotaBucket(resetTime: nil, tokenType: nil, modelId: bId, remainingFraction: nil, remainingAmount: nil, maxAmount: nil, customDisplayName: nil)
                            baseName = tempBucket.displayName
                            baseName = baseName.replacingOccurrences(of: " 5H", with: "", options: .caseInsensitive)
                                               .replacingOccurrences(of: " Weekly", with: "", options: .caseInsensitive)
                        }
                        
                        var customName = baseName
                        if !winLabel.isEmpty {
                            customName = "\(baseName) • \(winLabel)"
                        } else if let bName = sb.displayName, !bName.isEmpty, baseName != bName {
                            customName = "\(baseName) (\(bName))"
                        }
                        
                        let bucket = QuotaBucket(
                            resetTime: sb.resetTime,
                            tokenType: win,
                            modelId: bId,
                            remainingFraction: sb.remainingFraction,
                            remainingAmount: nil,
                            maxAmount: nil,
                            customDisplayName: customName
                        )
                        resultBuckets.append(bucket)
                    }
                }
            }
            return resultBuckets
        } catch {
            return nil
        }
    }
    
    private func findLanguageServerPorts() -> [Int] {
        var ports: [Int] = []
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    if line.lowercased().contains("agy") || line.lowercased().contains("agentapi") {
                        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        for part in parts {
                            if part.contains(":") {
                                let subparts = part.components(separatedBy: ":")
                                if let last = subparts.last, let port = Int(last), port > 1024 {
                                    if !ports.contains(port) {
                                        ports.append(port)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            // Process run failed
        }
        
        for defaultPort in [53412, 51005, 53411, 51004] {
            if !ports.contains(defaultPort) {
                ports.append(defaultPort)
            }
        }
        
        return ports
    }
    
    private func wakeUpLanguageServer() {
        let process = Process()
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/agy") {
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/agy")
        } else if FileManager.default.fileExists(atPath: "/usr/local/bin/agy") {
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/agy")
        } else if let home = ProcessInfo.processInfo.environment["HOME"],
                  FileManager.default.fileExists(atPath: "\(home)/.gemini/antigravity-cli/bin/agentapi") {
            process.executableURL = URL(fileURLWithPath: "\(home)/.gemini/antigravity-cli/bin/agentapi")
        } else {
            return
        }
        process.arguments = ["models"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            // ignore
        }
    }
}
