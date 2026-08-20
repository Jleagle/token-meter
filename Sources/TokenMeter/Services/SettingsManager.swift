import Foundation
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var toolbarDisplayModelId: String {
        didSet { UserDefaults.standard.set(toolbarDisplayModelId, forKey: "toolbarDisplayModelId") }
    }
    
    @Published var pollingRateSeconds: Int {
        didSet { UserDefaults.standard.set(pollingRateSeconds, forKey: "pollingRateSeconds") }
    }
    
    private init() {
        self.toolbarDisplayModelId = UserDefaults.standard.string(forKey: "toolbarDisplayModelId") ?? "auto"
        let savedRate = UserDefaults.standard.integer(forKey: "pollingRateSeconds")
        self.pollingRateSeconds = savedRate > 0 ? savedRate : 60
    }
}
