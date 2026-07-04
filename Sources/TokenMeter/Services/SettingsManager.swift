import Foundation
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var anthropicApiKey: String {
        didSet { UserDefaults.standard.set(anthropicApiKey, forKey: "anthropicApiKey") }
    }
    
    @Published var monthlyBudget: Double {
        didSet { UserDefaults.standard.set(monthlyBudget, forKey: "monthlyBudget") }
    }
    
    @Published var openAiApiKey: String {
        didSet { UserDefaults.standard.set(openAiApiKey, forKey: "openAiApiKey") }
    }
    
    @Published var openAiMonthlyBudget: Double {
        didSet { UserDefaults.standard.set(openAiMonthlyBudget, forKey: "openAiMonthlyBudget") }
    }
    
    @Published var toolbarDisplayModelId: String {
        didSet { UserDefaults.standard.set(toolbarDisplayModelId, forKey: "toolbarDisplayModelId") }
    }
    
    @Published var pollingRateSeconds: Int {
        didSet { UserDefaults.standard.set(pollingRateSeconds, forKey: "pollingRateSeconds") }
    }
    
    private init() {
        self.anthropicApiKey = UserDefaults.standard.string(forKey: "anthropicApiKey") ?? ""
        let savedBudget = UserDefaults.standard.double(forKey: "monthlyBudget")
        self.monthlyBudget = savedBudget > 0 ? savedBudget : 50.0
        self.openAiApiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? ""
        let savedOpenAiBudget = UserDefaults.standard.double(forKey: "openAiMonthlyBudget")
        self.openAiMonthlyBudget = savedOpenAiBudget > 0 ? savedOpenAiBudget : 50.0
        self.toolbarDisplayModelId = UserDefaults.standard.string(forKey: "toolbarDisplayModelId") ?? "auto"
        let savedRate = UserDefaults.standard.integer(forKey: "pollingRateSeconds")
        self.pollingRateSeconds = savedRate > 0 ? savedRate : 60
    }
}
