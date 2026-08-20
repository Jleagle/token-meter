import Foundation
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var toolbarDisplayModelId: String {
        didSet { UserDefaults.standard.set(toolbarDisplayModelId, forKey: "toolbarDisplayModelId") }
    }
    
    @Published var usePaceMode: Bool {
        didSet { UserDefaults.standard.set(usePaceMode, forKey: "usePaceMode") }
    }
    
    private init() {
        self.toolbarDisplayModelId = UserDefaults.standard.string(forKey: "toolbarDisplayModelId") ?? "auto"
        self.usePaceMode = UserDefaults.standard.bool(forKey: "usePaceMode")
    }
}
