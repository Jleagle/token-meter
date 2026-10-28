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
        guard let title = QuotaDisplay.menuBarTitle(buckets: buckets, selection: displayModelId, paceMode: SettingsManager.shared.usePaceMode) else {
            showIconOnly(button)
            return
        }
        button.title = " \(title)"
        if let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "TokenMeter") {
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
