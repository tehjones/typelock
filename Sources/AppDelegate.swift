import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let inputManager = InputSourceManager()
    private var statusItem: NSStatusItem!
    private var cancellable: AnyCancellable?
    private var isAccessibilityTrusted = false
    private var isInputManagerStarted = false
    private var permissionTimer: Timer?
    private var accessibilitySetupWindowController: AccessibilitySetupWindowController?
    private var excludedAppsWindow: NSWindow?

    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.sergey.typelock"

    private static let legacyLaunchAgentPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/LaunchAgents/\(bundleID).plist"
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NSApplication.shared.setActivationPolicy(.accessory)
        migrateLegacyLaunchAgent()
        isAccessibilityTrusted = AXIsProcessTrusted()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        rebuildMenu()

        cancellable = inputManager.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.updateInterface()
            }
        }

        Diagnostics.event("startup trusted=\(isAccessibilityTrusted) \(runtimeSummary)")
        startPermissionMonitoring()

        if isAccessibilityTrusted {
            startInputManager()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.showAccessibilitySetup()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        stopInputManager()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshAccessibilityPermission()
        updateInterface()
    }

    // MARK: - Status Item

    private func updateIcon() {
        let isEnforcing = isAccessibilityTrusted && inputManager.isLocked
        let resourceName = isEnforcing ? "menu-bar-locked" : "menu-bar-unlocked"
        let fallbackName = isEnforcing ? "lock.fill" : "lock.open"
        let image = Bundle.main.image(forResource: NSImage.Name(resourceName))
            ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: "TypeLock")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        statusItem.button?.image = image
        if !isAccessibilityTrusted {
            statusItem.button?.toolTip = "TypeLock needs Accessibility permission"
        } else if let sourceName = inputManager.lockedSourceName {
            statusItem.button?.toolTip = "TypeLock · \(sourceName)"
        } else {
            statusItem.button?.toolTip = "TypeLock"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if !isAccessibilityTrusted {
            let setupItem = NSMenuItem(
                title: "Set Up TypeLock…",
                action: #selector(showAccessibilitySetup),
                keyEquivalent: ""
            )
            setupItem.target = self
            setupItem.image = NSImage(
                systemSymbolName: "accessibility",
                accessibilityDescription: nil
            )
            menu.addItem(setupItem)
            menu.addItem(.separator())
            addAboutAndQuitItems(to: menu)
            statusItem.menu = menu
            return
        }

        inputManager.refreshSources()

        // Input source list
        for source in inputManager.availableSources {
            let item = NSMenuItem(title: source.name, action: #selector(lockToSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source.id
            item.state = inputManager.lockedSourceID == source.id ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // App Rules
        let excludedItem = NSMenuItem(title: "App Rules…", action: #selector(showExcludedApps), keyEquivalent: "")
        excludedItem.target = self
        menu.addItem(excludedItem)

        // Launch at Login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())

        addAboutAndQuitItems(to: menu)
        statusItem.menu = menu
    }

    private func addAboutAndQuitItems(to menu: NSMenu) {
        let about = NSMenuItem(title: "About TypeLock", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit TypeLock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: - Actions

    @objc private func lockToSource(_ sender: NSMenuItem) {
        guard let sourceID = sender.representedObject as? String else { return }
        inputManager.lockTo(sourceID)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered:
                try SMAppService.mainApp.register()
            case .notFound:
                let message = "macOS could not find TypeLock as a login item. Make sure TypeLock is installed in Applications, then try again."
                Diagnostics.event("launch-at-login-not-found")
                showLaunchAtLoginError(message)
            @unknown default:
                let message = "macOS returned an unknown Launch at Login status."
                Diagnostics.event("launch-at-login-unknown-status")
                showLaunchAtLoginError(message)
            }
        } catch {
            Diagnostics.event("launch-at-login-failed error=\(error)")
            showLaunchAtLoginError(error.localizedDescription)
        }
        rebuildMenu()
    }

    private func showLaunchAtLoginError(_ details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t Change Launch at Login"
        alert.informativeText = details
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func showAccessibilitySetup() {
        let view = makeAccessibilitySetupView()
        if let accessibilitySetupWindowController {
            accessibilitySetupWindowController.update(view: view)
        } else {
            accessibilitySetupWindowController = AccessibilitySetupWindowController(view: view)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        accessibilitySetupWindowController?.present()
    }

    @objc private func showExcludedApps() {
        if let window = excludedAppsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let view = ExcludedAppsView(inputManager: inputManager)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "App Rules"
        window.contentView = NSHostingView(rootView: view)
        window.contentMinSize = NSSize(width: 500, height: 340)
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("TypeLockAppRulesWindow")
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

    // MARK: - Accessibility

    private func startPermissionMonitoring() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshAccessibilityPermission()
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func refreshAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isAccessibilityTrusted else { return }

        isAccessibilityTrusted = trusted
        Diagnostics.event("accessibility-changed trusted=\(trusted) \(runtimeSummary)")

        if trusted {
            startInputManager()
        } else {
            stopInputManager()
        }
        updateInterface()
    }

    private func makeAccessibilitySetupView() -> AccessibilitySetupView {
        AccessibilitySetupView(
            isAllowed: isAccessibilityTrusted,
            onRequestAccessibility: { [weak self] in
                self?.requestAccessibilityPermission()
            },
            onOpenSettings: { [weak self] in
                self?.openAccessibilitySettings()
            },
            onClose: { [weak self] in
                self?.accessibilitySetupWindowController?.close()
            }
        )
    }

    private func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Diagnostics.event("accessibility-requested trusted=\(trusted) \(runtimeSummary)")

        if trusted != isAccessibilityTrusted {
            refreshAccessibilityPermission()
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }

        Diagnostics.event("accessibility-settings-opened \(runtimeSummary)")
        NSWorkspace.shared.open(url)
    }

    private func startInputManager() {
        guard !isInputManagerStarted else { return }
        inputManager.start()
        isInputManagerStarted = true
    }

    private func stopInputManager() {
        guard isInputManagerStarted else { return }
        inputManager.stop()
        isInputManagerStarted = false
    }

    private func updateInterface() {
        updateIcon()
        rebuildMenu()
        accessibilitySetupWindowController?.update(view: makeAccessibilitySetupView())
    }

    // MARK: - Launch at Login

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func migrateLegacyLaunchAgent() {
        let path = Self.legacyLaunchAgentPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        let service = SMAppService.mainApp
        let legacyStatus = SMAppService.statusForLegacyPlist(at: url)

        do {
            if service.status == .enabled {
                try FileManager.default.removeItem(at: url)
                Diagnostics.event("launch-at-login-migrated")
                return
            }

            guard legacyStatus == .enabled else {
                Diagnostics.event("launch-at-login-migration-skipped legacy-status=\(legacyStatus)")
                return
            }

            switch service.status {
            case .enabled:
                break
            case .notRegistered:
                try service.register()
            case .requiresApproval:
                Diagnostics.event("launch-at-login-migration-pending-approval")
                return
            case .notFound:
                Diagnostics.event("launch-at-login-migration-skipped status=not-found")
                return
            @unknown default:
                Diagnostics.event("launch-at-login-migration-skipped status=unknown")
                return
            }

            guard service.status == .enabled else {
                Diagnostics.event("launch-at-login-migration-waiting status=\(service.status)")
                return
            }

            try FileManager.default.removeItem(at: url)
            Diagnostics.event("launch-at-login-migrated")
        } catch {
            Diagnostics.event("launch-at-login-migration-failed error=\(error)")
        }
    }

    private var runtimeSummary: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "debug"
        return "version=\(version) pid=\(ProcessInfo.processInfo.processIdentifier) bundleURL=\(Bundle.main.bundleURL.path)"
    }
}
