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
            
            // 2. Fetch Official Claude Buckets (plan usage)
            let claudeBuckets = await fetchOfficialClaudeBuckets()
            
            // 3. Fetch Official Codex / OpenAI Buckets (plan usage)
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
        // Only plan accounts are supported: usage comes from the Claude Code
        // OAuth session, no bucket is shown when no logged-in plan is found
        guard let creds = loadClaudeOAuthCredentials(),
              let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 4.0

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let planName = claudePlanDisplayName(creds.plan)
        var buckets: [QuotaBucket] = []

        if let window = json["five_hour"] as? [String: Any],
           let utilization = (window["utilization"] as? NSNumber)?.doubleValue {
            buckets.append(QuotaBucket(
                resetTime: normalizeResetTime(window["resets_at"] as? String),
                tokenType: "5h",
                modelId: "official-claude-cli-5h",
                remainingFraction: max(0.0, min(1.0, (100.0 - utilization) / 100.0)),
                remainingAmount: nil,
                maxAmount: nil,
                customDisplayName: "\(planName) • 5-Hour Limit"
            ))
        }

        if let window = json["seven_day"] as? [String: Any],
           let utilization = (window["utilization"] as? NSNumber)?.doubleValue {
            buckets.append(QuotaBucket(
                resetTime: normalizeResetTime(window["resets_at"] as? String),
                tokenType: "weekly",
                modelId: "official-claude-weekly",
                remainingFraction: max(0.0, min(1.0, (100.0 - utilization) / 100.0)),
                remainingAmount: nil,
                maxAmount: nil,
                customDisplayName: "\(planName) • Weekly Limit"
            ))
        }

        return buckets
    }

    private func loadClaudeOAuthCredentials() -> (token: String, plan: String)? {
        // Claude Code stores its OAuth session in the login keychain on macOS,
        // with ~/.claude/.credentials.json as the fallback location
        var jsonData: Data?

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        if (try? process.run()) != nil {
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                jsonData = output
            }
        }

        if jsonData == nil {
            let credsPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
            jsonData = try? Data(contentsOf: credsPath)
        }

        guard let data = jsonData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = (oauth["accessToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }

        return (token, (oauth["subscriptionType"] as? String) ?? "")
    }

    private func claudePlanDisplayName(_ subscriptionType: String) -> String {
        switch subscriptionType.lowercased() {
        case "pro":
            return "Claude Pro"
        case "max":
            return "Claude Max"
        case "team":
            return "Claude Team"
        case "enterprise":
            return "Claude Enterprise"
        case "":
            return "Claude"
        default:
            return "Claude \(subscriptionType.capitalized)"
        }
    }

    private func normalizeResetTime(_ raw: String?) -> String {
        guard var value = raw, !value.isEmpty else { return "" }
        // The API returns microsecond precision, which ISO8601DateFormatter rejects
        if let dotRange = value.range(of: #"\.\d+"#, options: .regularExpression) {
            value.removeSubrange(dotRange)
        }
        return value
    }
    
    // MARK: - Official Codex / OpenAI Integration
    
    private func fetchOfficialCodexBuckets() async -> [QuotaBucket] {
        // Only plan accounts are supported: no bucket is shown unless the
        // Codex CLI is logged in and real usage was fetched
        guard let (fraction, resetTimeStr, planName) = await fetchCodexCliUsage() else { return [] }

        return [QuotaBucket(
            resetTime: resetTimeStr,
            tokenType: "5h",
            modelId: "official-codex-cli-5h",
            remainingFraction: fraction,
            remainingAmount: nil,
            maxAmount: nil,
            customDisplayName: planName
        )]
    }

    private func fetchCodexCliUsage() async -> (Double, String, String)? {
        let authPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: authPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String, !token.isEmpty else {
            return nil
        }

        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            return nil
        }

        var fraction = 1.0
        var resetTimeStr = calculateFiveHourResetTime()
        var planName = "Codex / OpenAI • 5-Hour Limit"

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 4.0

            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode),
                  let usageJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                return nil
            }

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
        } catch {
            return nil
        }

        return (fraction, resetTimeStr, planName)
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

                        // Only Gemini quotas are tracked; Antigravity also reports
                        // Claude/GPT buckets which are ignored
                        let haystack = "\(groupName) \(bId) \(customName)".lowercased()
                        let name = customName.lowercased()
                        guard haystack.contains("gemini"),
                              !name.contains("claude"),
                              !name.contains("gpt") else { continue }

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
