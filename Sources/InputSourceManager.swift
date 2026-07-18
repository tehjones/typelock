import Carbon
import Combine
import AppKit

struct ExcludedApp: Codable, Identifiable, Hashable {
    let bundleID: String
    let name: String
    var inputSourceID: String?
    var id: String { bundleID }
}

final class InputSourceManager: ObservableObject {
    @Published var availableSources: [(id: String, name: String)] = []
    @Published var lockedSourceID: String?
    @Published var excludedApps: [ExcludedApp] = []

    private var observer: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var isHandlingChange = false
    private var debounceWorkItem: DispatchWorkItem?
    private var recheckWorkItem: DispatchWorkItem?
    private var startupRetryWorkItem: DispatchWorkItem?
    private var isStarted = false
    private var currentFrontmostBundleID: String?
    private var excludedBundleIDs: Set<String> = []
    private var excludedAppInputSources: [String: String] = [:]  // bundleID -> inputSourceID
    private var focusTimer: DispatchSourceTimer?
    private var focusActivity: NSObjectProtocol?
    private let systemWideElement = AXUIElementCreateSystemWide()

    deinit { stop() }

    private static let lockedSourceKey = "lockedSourceID"
    private static let excludedAppsKey = "excludedApps"

    var isLocked: Bool { lockedSourceID != nil }

    var lockedSourceName: String? {
        guard let id = lockedSourceID else { return nil }
        return availableSources.first(where: { $0.id == id })?.name
    }

    var currentSourceID: String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return source.id
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        loadExcludedApps()
        refreshSources()
        currentFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let saved = UserDefaults.standard.string(forKey: Self.lockedSourceKey) {
            lockedSourceID = saved
            let startupSourceID = startupSource(globalLock: saved)
            if let sourceID = startupSourceID, availableSources.contains(where: { $0.id == sourceID }) {
                selectSource(sourceID)
            } else if !availableSources.contains(where: { $0.id == saved }) {
                // Third-party input method may not be loaded yet after reboot
                let retry = DispatchWorkItem { [weak self] in
                    guard let self, self.isStarted else { return }
                    self.startupRetryWorkItem = nil
                    self.retryLock()
                }
                startupRetryWorkItem = retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: retry)
            }
        }
        startMonitoring()
        startAppActivationObserver()
        startFocusPolling()
    }

    /// Determine the correct input source to apply at startup based on the frontmost app.
    private func startupSource(globalLock: String) -> String? {
        let bid = currentFrontmostBundleID ?? ""
        if excludedBundleIDs.contains(bid) {
            return excludedAppInputSources[bid]  // nil if no assignment → no enforcement
        }
        return globalLock
    }

    private func retryLock() {
        refreshSources()
        guard let lockedID = lockedSourceID else { return }
        let sourceID = startupSource(globalLock: lockedID)
        if let sourceID, availableSources.contains(where: { $0.id == sourceID }) {
            selectSource(sourceID)
        }
    }

    func stop() {
        isStarted = false
        stopMonitoring()
        stopAppActivationObserver()
        stopFocusPolling()
        startupRetryWorkItem?.cancel()
        startupRetryWorkItem = nil
        recheckWorkItem?.cancel()
        recheckWorkItem = nil
        isHandlingChange = false
    }

    // MARK: - Sources

    func refreshSources() {
        guard let cfList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            if !availableSources.isEmpty { availableSources = [] }
            return
        }

        let newSources: [(id: String, name: String)] = cfList
            .filter { source in
                source.isEnabled
                && source.isSelectCapable
                && source.category == kTISCategoryKeyboardInputSource as String
            }
            .compactMap { source in
                guard let id = source.id, let name = source.localizedName else { return nil }
                return (id: id, name: name)
            }

        if newSources.map(\.id) != availableSources.map(\.id) {
            availableSources = newSources
        }
    }

    func lockTo(_ sourceID: String) {
        lockedSourceID = sourceID
        UserDefaults.standard.set(sourceID, forKey: Self.lockedSourceKey)
        selectSource(sourceID)
        startFocusPolling()
    }

    func unlock() {
        lockedSourceID = nil
        UserDefaults.standard.removeObject(forKey: Self.lockedSourceKey)
        stopFocusPolling()
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleInputSourceChange()
        }
    }

    private func stopMonitoring() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
        debounceWorkItem?.cancel()
    }

    private func handleInputSourceChange() {
        guard !isHandlingChange else { return }
        guard lockedSourceID != nil else { return }

        if let bundleID = currentFrontmostBundleID, excludedBundleIDs.contains(bundleID) {
            // Excluded app with an assigned input source: enforce that source
            guard let targetID = excludedAppInputSources[bundleID] else { return }
            debounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.lockedSourceID != nil else { return }
                // Verify still in the same excluded app
                guard self.currentFrontmostBundleID == bundleID else { return }
                guard let currentID = self.currentSourceID, currentID != targetID else { return }
                self.selectSource(targetID)
            }
            debounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
            return
        }

        guard let lockedID = lockedSourceID else { return }
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lockedSourceID == lockedID else { return }
            // Verify still in a non-excluded app
            let bid = self.currentFrontmostBundleID ?? ""
            guard !self.excludedBundleIDs.contains(bid) else { return }
            self.enforceLockedSource(lockedID)
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func enforceLockedSource(_ lockedID: String) {
        guard let currentID = currentSourceID, currentID != lockedID else { return }
        selectSource(lockedID)
    }

    private func selectSource(_ sourceID: String) {
        guard isStarted else { return }
        guard let cfList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return }
        guard let target = cfList.first(where: { $0.id == sourceID }) else { return }

        isHandlingChange = true
        TISSelectInputSource(target)

        recheckWorkItem?.cancel()
        let recheck = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isHandlingChange = false
            // Re-check in case an external switch arrived during the guard window
            guard self.lockedSourceID != nil else { return }
            let bundleID = self.currentFrontmostBundleID ?? ""
            if self.excludedBundleIDs.contains(bundleID) {
                if let targetID = self.excludedAppInputSources[bundleID],
                   let currentID = self.currentSourceID, currentID != targetID {
                    self.selectSource(targetID)
                }
            } else if let lockedID = self.lockedSourceID {
                self.enforceLockedSource(lockedID)
            }
        }
        recheckWorkItem = recheck
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: recheck)
    }

    // MARK: - App Activation Observer

    private func startAppActivationObserver() {
        currentFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleID = app.bundleIdentifier ?? ""
            self.currentFrontmostBundleID = bundleID

            guard let lockedID = self.lockedSourceID else { return }

            if self.excludedBundleIDs.contains(bundleID) {
                // Excluded app: switch to its assigned input source if configured
                if let targetSourceID = self.excludedAppInputSources[bundleID],
                   self.currentSourceID != targetSourceID {
                    self.selectSource(targetSourceID)
                }
            } else {
                // Normal app: enforce the global lock
                self.enforceLockedSource(lockedID)
            }
        }
    }

    private func stopAppActivationObserver() {
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        appActivationObserver = nil
    }

    // MARK: - Focus Polling (non-activating panel detection)

    private func startFocusPolling() {
        stopFocusPolling()
        guard isLocked, !excludedBundleIDs.isEmpty else { return }

        focusActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Monitoring focused app for input source enforcement"
        )

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.pollFocusedApp()
        }
        timer.resume()
        focusTimer = timer
    }

    private func stopFocusPolling() {
        focusTimer?.cancel()
        focusTimer = nil
        if let activity = focusActivity {
            ProcessInfo.processInfo.endActivity(activity)
            focusActivity = nil
        }
    }

    private func pollFocusedApp() {
        guard !isHandlingChange else { return }

        guard let bundleID = resolvedFocusedBundleID() else { return }

        currentFrontmostBundleID = bundleID

        guard let lockedID = lockedSourceID else { return }

        if excludedBundleIDs.contains(bundleID) {
            if let targetSourceID = excludedAppInputSources[bundleID],
               currentSourceID != targetSourceID {
                selectSource(targetSourceID)
            }
        } else {
            enforceLockedSource(lockedID)
        }
    }

    private func resolvedFocusedBundleID() -> String? {
        // Prefer window/app ownership over the focused control. IMEs can temporarily
        // own the focused UI element, which misidentifies Raycast as the input method.
        focusedBundleID(for: kAXFocusedWindowAttribute as CFString)
        ?? focusedBundleID(for: kAXFocusedApplicationAttribute as CFString)
        ?? focusedBundleID(for: kAXFocusedUIElementAttribute as CFString)
        ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private func focusedBundleID(for attribute: CFString) -> String? {
        var rawElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWideElement, attribute, &rawElement) == .success,
              let element = rawElement else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element as! AXUIElement, &pid) == .success else { return nil }

        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    // MARK: - Excluded Apps

    private func loadExcludedApps() {
        guard let data = UserDefaults.standard.data(forKey: Self.excludedAppsKey),
              let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) else {
            return
        }
        excludedApps = apps
        rebuildExcludedCaches()
    }

    private func saveExcludedApps() {
        guard let data = try? JSONEncoder().encode(excludedApps) else { return }
        UserDefaults.standard.set(data, forKey: Self.excludedAppsKey)
        rebuildExcludedCaches()
        startFocusPolling()
    }

    private func rebuildExcludedCaches() {
        excludedBundleIDs = Set(excludedApps.map(\.bundleID))
        excludedAppInputSources = excludedApps.reduce(into: [:]) { dict, app in
            if let sourceID = app.inputSourceID {
                dict[app.bundleID] = sourceID
            }
        }
    }

    func addExcludedApp(bundleID: String, name: String) {
        guard !excludedBundleIDs.contains(bundleID) else { return }
        excludedApps.append(ExcludedApp(bundleID: bundleID, name: name))
        saveExcludedApps()
    }

    func removeExcludedApp(bundleID: String) {
        excludedApps.removeAll { $0.bundleID == bundleID }
        saveExcludedApps()
    }

    func updateExcludedApp(bundleID: String, inputSourceID: String?) {
        guard let index = excludedApps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        excludedApps[index].inputSourceID = inputSourceID
        saveExcludedApps()
    }
}
