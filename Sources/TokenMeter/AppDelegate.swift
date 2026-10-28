import Cocoa
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let menuBuilder = StatusMenuBuilder(settings: SettingsManager.shared)
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        if let button = statusItem.button,
           let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "TokenMeter") {
            image.isTemplate = true
            button.image = image
        }

        Publishers.CombineLatest3(QuotaService.shared.$buckets, SettingsManager.shared.$toolbarDisplayModelId, SettingsManager.shared.$usePaceMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (buckets, displayModelId, _) in
                self?.updateMenuBarDisplay(buckets: buckets, displayModelId: displayModelId)
            }
            .store(in: &cancellables)
    }

    // The menu is rebuilt from the latest data each time it is about to open
    func menuNeedsUpdate(_ menu: NSMenu) {
        menuBuilder.populate(menu, buckets: QuotaService.shared.buckets, errorMessage: QuotaService.shared.errorMessage)
    }

    private func updateMenuBarDisplay(buckets: [QuotaBucket], displayModelId: String) {
        guard let button = statusItem.button else { return }
        let targetId = displayModelId.isEmpty ? "auto" : displayModelId

        guard targetId != "none", !buckets.isEmpty else {
            showIconOnly(button)
            return
        }

        let paceMode = SettingsManager.shared.usePaceMode
        var selectedBucket: QuotaBucket?
        if targetId == "auto" {
            // Pick the most at-risk window, ignoring greyed-out placeholders:
            // most quota used, or fastest burn rate in burn-rate mode
            let candidates = buckets.filter { $0.unavailableReason == nil }
            if paceMode {
                selectedBucket = candidates.max(by: { $0.effectivePacePercentage < $1.effectivePacePercentage })
            } else {
                selectedBucket = candidates.max(by: { $0.usedPercentage < $1.usedPercentage })
            }
        } else {
            selectedBucket = buckets.first(where: { $0.modelId == targetId })
        }

        guard let bucket = selectedBucket else {
            showIconOnly(button)
            return
        }
        button.title = paceMode ? " \(bucket.effectivePacePercentage)%" : " \(bucket.usedPercentage)%"
        if let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: bucket.displayName) {
            image.isTemplate = true
            button.image = image
        }
        button.imagePosition = .imageLeft
    }

    private func showIconOnly(_ button: NSStatusBarButton) {
        button.title = ""
        if let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "TokenMeter") {
            image.isTemplate = true
            button.image = image
        }
        button.imagePosition = .imageOnly
    }
}
