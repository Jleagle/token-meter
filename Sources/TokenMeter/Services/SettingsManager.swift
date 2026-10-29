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

    /// The provider last seen consuming quota, which the menu bar's Latest choice follows.
    @Published var lastUsedProvider: QuotaProvider? {
        didSet { defaults.set(lastUsedProvider?.rawValue, forKey: "lastUsedProvider") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.toolbarDisplayModelId = defaults.string(forKey: "toolbarDisplayModelId") ?? "auto"
        self.usePaceMode = defaults.bool(forKey: "usePaceMode")
        self.lastUsedProvider = defaults.string(forKey: "lastUsedProvider").flatMap(QuotaProvider.init(rawValue:))
    }
}
