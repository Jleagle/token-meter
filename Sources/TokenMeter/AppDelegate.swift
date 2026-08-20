import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    private var popoverTopEdge: CGFloat?
    private var popoverLeftEdge: CGFloat?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSPopover keeps its bottom edge fixed when the hosted content resizes,
        // growing upward over the menu bar; re-pin the top edge on every resize
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverWindowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: nil
        )

        // Initialize Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 330, height: 500)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverRootView())

        // Hide the anchor arrow for a native menu-extra look (private API, guarded)
        if popover.responds(to: NSSelectorFromString("setShouldHideAnchor:")) {
            popover.setValue(true, forKey: "shouldHideAnchor")
        }
        
        // Initialize Menu Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "TokenMeter") {
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
            if let image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "TokenMeter") {
                image.isTemplate = true
                button.image = image
            }
            button.imagePosition = .imageOnly
            return
        }
        
        var selectedBucket: QuotaBucket?
        if targetId == "auto" {
            // Find lowest percentage bucket, ignoring greyed-out placeholders
            selectedBucket = buckets
                .filter { $0.unavailableReason == nil }
                .min(by: { $0.remainingPercentage < $1.remainingPercentage })
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
            // Tell the SwiftUI content how much vertical space exists below the
            // menu bar on the screen the status item actually lives on
            if let buttonWindow = button.window, let screen = buttonWindow.screen {
                PopoverSizing.shared.maxTotalHeight = buttonWindow.frame.minY - screen.visibleFrame.minY - 12
            }

            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            button.highlight(true)

            if let contentView = popover.contentViewController?.view,
               let window = contentView.window,
               let buttonWindow = button.window,
               let screen = buttonWindow.screen {
                // The popover window is larger than its visible body (arrow area +
                // chrome); measure the insets so the body can be positioned exactly
                let contentRect = window.convertToScreen(contentView.convert(contentView.bounds, to: nil))
                let topInset = window.frame.maxY - contentRect.maxY
                let leftInset = contentRect.minX - window.frame.minX

                let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
                let menuBarBottom = buttonWindow.frame.minY

                // Native menu-extra placement: body 5pt below the menu bar,
                // left-aligned with the icon, clamped to the screen edge
                let maxLeft = screen.visibleFrame.maxX - contentRect.width - 8
                let desiredContentLeft = min(buttonRect.minX, maxLeft)

                var frame = window.frame
                frame.origin.x = desiredContentLeft - leftInset
                frame.origin.y = (menuBarBottom - 5 + topInset) - frame.height
                window.setFrame(frame, display: true)

                popoverTopEdge = frame.maxY
                popoverLeftEdge = frame.origin.x
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }

    @objc private func popoverWindowDidResize(_ notification: Notification) {
        guard popover.isShown,
              let window = notification.object as? NSWindow,
              window === popover.contentViewController?.view.window,
              let topEdge = popoverTopEdge else { return }

        var frame = window.frame
        let desiredOriginY = topEdge - frame.height
        let desiredOriginX = popoverLeftEdge ?? frame.origin.x
        guard abs(frame.origin.y - desiredOriginY) > 0.5 || abs(frame.origin.x - desiredOriginX) > 0.5 else { return }
        frame.origin.y = desiredOriginY
        frame.origin.x = desiredOriginX
        window.setFrame(frame, display: true)
    }
    
    @objc func openSettingsWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }
        if let window = settingsWindow {
            window.setFrame(NSRect(x: window.frame.minX, y: window.frame.minY, width: 540, height: 480), display: true)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TokenMeter Settings"
        window.center()
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
