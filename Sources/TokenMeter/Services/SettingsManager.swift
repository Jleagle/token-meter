import Foundation
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults: UserDefaults

    @Published var toolbarDisplayModelId: String {
        didSet { defaults.set(toolbarDisplayModelId, forKey: "toolbarDisplayModelId") }
    }

    @Published var usePaceMode: Bool {
        didSet { defaults.set(usePaceMode, forKey: "usePaceMode") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.toolbarDisplayModelId = defaults.string(forKey: "toolbarDisplayModelId") ?? "auto"
        self.usePaceMode = defaults.bool(forKey: "usePaceMode")
    }
}
