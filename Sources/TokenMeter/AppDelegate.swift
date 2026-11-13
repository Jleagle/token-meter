import Cocoa
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let menuBuilder = StatusMenuBuilder(settings: SettingsManager.shared)
    private var cancellables = Set<AnyCancellable>()
    private var shownProvider: QuotaProvider?

    private let appIcon: NSImage? = {
        let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "TokenMeter")
        image?.isTemplate = true
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        statusItem.button?.image = appIcon

        Publishers.CombineLatest4(QuotaService.shared.$buckets, SettingsManager.shared.$toolbarDisplayModelId, SettingsManager.shared.$usePaceMode, SettingsManager.shared.$lastUsedModelId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (buckets, displayModelId, _, _) in
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
        let settings = SettingsManager.shared
        guard let bucket = QuotaDisplay.menuBarBucket(buckets: buckets, selection: displayModelId, paceMode: settings.usePaceMode, lastUsedModelId: settings.lastUsedModelId) else {
            showIconOnly(button)
            return
        }
        let title = " " + QuotaDisplay.percentText(for: bucket, paceMode: settings.usePaceMode)
        let provider = QuotaProvider.of(bucket)
        guard button.title != title || shownProvider != provider else { return }
        Diagnostics.log("menu bar: \(provider.name)\(title)")
        button.title = title
        button.image = ProviderLogo.menuBarImage(for: provider)
        button.imagePosition = .imageLeft
        shownProvider = provider
    }

    private func showIconOnly(_ button: NSStatusBarButton) {
        button.title = ""
        button.image = appIcon
        button.imagePosition = .imageOnly
        shownProvider = nil
    }
}
