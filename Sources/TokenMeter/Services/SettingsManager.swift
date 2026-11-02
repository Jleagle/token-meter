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

    /// The providers shown in the menu and polled for usage.
    @Published var enabledProviders: Set<QuotaProvider> {
        didSet { defaults.set(enabledProviders.map(\.rawValue).sorted(), forKey: "enabledProviders") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.toolbarDisplayModelId = defaults.string(forKey: "toolbarDisplayModelId") ?? QuotaDisplay.defaultSelection
        self.usePaceMode = defaults.bool(forKey: "usePaceMode")
        self.lastUsedProvider = defaults.string(forKey: "lastUsedProvider").flatMap(QuotaProvider.init(rawValue:))
        self.enabledProviders = defaults.stringArray(forKey: "enabledProviders")
            .map { Set($0.compactMap(QuotaProvider.init(rawValue:))) }
            ?? Set(QuotaProvider.allCases)
    }
}
