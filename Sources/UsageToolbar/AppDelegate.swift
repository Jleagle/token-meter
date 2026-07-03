import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 330, height: 500)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverRootView())
        
        // Initialize Menu Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "AI Usage Toolbar") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "AGY"
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // Observe QuotaService buckets and Settings toolbarDisplayModelId
        Publishers.CombineLatest(QuotaService.shared.$buckets, SettingsManager.shared.$toolbarDisplayModelId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (buckets, displayModelId) in
                self?.updateMenuBarDisplay(buckets: buckets, displayModelId: displayModelId)
            }
            .store(in: &cancellables)
    }
    
    private func updateMenuBarDisplay(buckets: [QuotaBucket], displayModelId: String) {
        guard let button = statusItem.button else { return }
        
        let targetId = displayModelId.isEmpty ? "auto" : displayModelId
        
        if targetId == "none" || buckets.isEmpty {
            button.title = ""
            if let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "AI Usage Toolbar") {
                image.isTemplate = true
                button.image = image
            }
            button.imagePosition = .imageOnly
            return
        }
        
        var selectedBucket: QuotaBucket?
        if targetId == "auto" {
            // Find lowest percentage bucket
            selectedBucket = buckets.min(by: { $0.remainingPercentage < $1.remainingPercentage })
        } else {
            selectedBucket = buckets.first(where: { $0.modelId == targetId })
        }
        
        if let bucket = selectedBucket {
            button.title = " \(bucket.remainingPercentage)%"
            
            let iconName = bucket.modelId.hasPrefix("official-") ? "sparkle" : "cpu"
            if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: bucket.displayName) {
                image.isTemplate = true
                button.image = image
            }
            button.imagePosition = .imageLeft
        } else {
            button.title = ""
            if let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Antigravity Usage") {
                image.isTemplate = true
                button.image = image
            }
            button.imagePosition = .imageOnly
        }
    }
    
    var settingsWindow: NSWindow?
    
    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    @objc func openSettingsWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }
        if let window = settingsWindow {
            window.setFrame(NSRect(x: window.frame.minX, y: window.frame.minY, width: 540, height: 640), display: true)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "UsageToolbar Settings"
        window.center()
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
