import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let inputManager = InputSourceManager()
    private var statusItem: NSStatusItem!
    private var cancellable: AnyCancellable?
    private var launchAtLogin = false
    private var excludedAppsWindow: NSWindow?

    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.sergey.typelock"

    private static let launchAgentPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(bundleID).plist"
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchAtLogin = FileManager.default.fileExists(atPath: Self.launchAgentPath)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        rebuildMenu()

        cancellable = inputManager.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.updateIcon()
                self?.rebuildMenu()
            }
        }

        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        inputManager.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        inputManager.stop()
    }

    // MARK: - Status Item

    private func updateIcon() {
        let name = inputManager.isLocked ? "lock" : "lock.open"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "TypeLock")
    }

    private func rebuildMenu() {
        inputManager.refreshSources()
        let menu = NSMenu()

        // Status line
        let statusTitle = inputManager.lockedSourceName.map { "Locked to \($0)" } ?? "Unlocked"
        let statusLabel = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        menu.addItem(statusLabel)
        menu.addItem(.separator())

        // Input source list
        for source in inputManager.availableSources {
            let indicator = inputManager.lockedSourceID == source.id ? "●" : "○"
            let item = NSMenuItem(title: "\(indicator) \(source.name)", action: #selector(lockToSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source.id
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // Unlock (only when locked)
        if inputManager.isLocked {
            let unlock = NSMenuItem(title: "Unlock", action: #selector(unlockSource), keyEquivalent: "")
            unlock.target = self
            menu.addItem(unlock)
            menu.addItem(.separator())
        }

        // Excluded Apps
        let excludedItem = NSMenuItem(title: "Excluded Apps...", action: #selector(showExcludedApps), keyEquivalent: "")
        excludedItem.target = self
        menu.addItem(excludedItem)

        // Launch at Login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLogin ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())

        // About
        let about = NSMenuItem(title: "About TypeLock", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        // Quit
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        self.statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func lockToSource(_ sender: NSMenuItem) {
        guard let sourceID = sender.representedObject as? String else { return }
        inputManager.lockTo(sourceID)
    }

    @objc private func unlockSource() {
        inputManager.unlock()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        setLaunchAtLogin(sender.state != .on)
        rebuildMenu()
    }

    @objc private func showExcludedApps() {
        if let window = excludedAppsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let view = ExcludedAppsView(inputManager: inputManager)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Excluded Apps"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        excludedAppsWindow = window
    }

    @objc private func showAbout() {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "TypeLock",
            .applicationVersion: shortVersion,
            .credits: NSAttributedString(
                string: "Lock your input method. Prevent unwanted switches.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            ),
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === excludedAppsWindow {
            excludedAppsWindow = nil
        }
    }

    // MARK: - Launch at Login

    private func setLaunchAtLogin(_ enabled: Bool) {
        let path = Self.launchAgentPath
        if enabled {
            let plist: [String: Any] = [
                "Label": Self.bundleID,
                "ProgramArguments": ["/usr/bin/open", "-b", Self.bundleID],
                "RunAtLoad": true,
            ]
            let url = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            (plist as NSDictionary).write(to: url, atomically: true)
        } else {
            try? FileManager.default.removeItem(atPath: path)
        }
        launchAtLogin = FileManager.default.fileExists(atPath: path)
    }
}
