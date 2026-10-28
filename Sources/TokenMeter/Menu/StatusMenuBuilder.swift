import AppKit
import SwiftUI

/// The status item's dropdown: quota rows under provider headers, a Settings submenu, and Quit.
@MainActor
final class StatusMenuBuilder: NSObject {
    static let rowWidth: CGFloat = 280

    private let settings: SettingsManager

    init(settings: SettingsManager) {
        self.settings = settings
    }

    func makeMenu(buckets: [QuotaBucket], errorMessage: String?) -> NSMenu {
        let menu = NSMenu()
        populate(menu, buckets: buckets, errorMessage: errorMessage)
        return menu
    }

    /// Replaces the menu's items with the current state.
    func populate(_ menu: NSMenu, buckets: [QuotaBucket], errorMessage: String?) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        if buckets.isEmpty {
            menu.addItem(disabledItem(errorMessage ?? "Loading usage…"))
        } else {
            for group in QuotaProvider.grouped(buckets) {
                menu.addItem(header(group.provider.name))
                for bucket in group.buckets {
                    menu.addItem(rowItem(bucket))
                }
            }
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu(buckets: buckets)
        menu.addItem(settingsItem)

        let quit = NSMenuItem(title: "Quit TokenMeter", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Items

    private func header(_ title: String) -> NSMenuItem {
        let item: NSMenuItem
        if #available(macOS 14.0, *) {
            item = NSMenuItem.sectionHeader(title: title)
        } else {
            item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        }
        item.isEnabled = false
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func rowItem(_ bucket: QuotaBucket) -> NSMenuItem {
        let title = bucket.unavailableReason ?? QuotaProvider.shortName(for: bucket)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = bucket.unavailableReason == nil
        let host = NSHostingView(rootView: QuotaRowView(bucket: bucket, settings: settings))
        host.setFrameSize(NSSize(width: Self.rowWidth, height: host.fittingSize.height))
        item.view = host
        return item
    }

    private func settingsMenu(buckets: [QuotaBucket]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let burnRate = NSMenuItem(title: "Burn Rate", action: #selector(toggleBurnRate(_:)), keyEquivalent: "")
        burnRate.target = self
        burnRate.state = settings.usePaceMode ? .on : .off
        menu.addItem(burnRate)

        let show = NSMenuItem(title: "Show in Menu Bar", action: nil, keyEquivalent: "")
        show.submenu = showInMenuBarMenu(buckets: buckets)
        menu.addItem(show)
        return menu
    }

    private func showInMenuBarMenu(buckets: [QuotaBucket]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let current = settings.toolbarDisplayModelId.isEmpty ? "auto" : settings.toolbarDisplayModelId

        func option(_ title: String, id: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(selectMenuBarItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = id == current ? .on : .off
            return item
        }

        menu.addItem(option("Auto", id: "auto"))
        menu.addItem(.separator())
        for bucket in buckets where bucket.unavailableReason == nil {
            menu.addItem(option(bucket.displayName, id: bucket.modelId))
        }
        menu.addItem(.separator())
        menu.addItem(option("None", id: "none"))
        return menu
    }

    // MARK: - Actions

    @objc func toggleBurnRate(_ sender: NSMenuItem) {
        settings.usePaceMode.toggle()
    }

    @objc func selectMenuBarItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.toolbarDisplayModelId = id
    }

    @objc func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}
