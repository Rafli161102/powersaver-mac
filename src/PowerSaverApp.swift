import Cocoa
import IOKit.ps

struct PowerSaverConfig: Codable {
    var protectedBundleIDs: [String]
    var suspendAgentLabels: [String]
    var autoSuspendCommonUpdaters: Bool
    var autoCleanCommonHelpers: Bool
    var extremeModeApps: [String]

    static func defaultConfig() -> PowerSaverConfig {
        return PowerSaverConfig(
            protectedBundleIDs: [
                "com.apple.finder",
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "dev.warp.Warp-Stable",
                "com.mitchellh.ghostty",
                "net.kovidgoyal.kitty",
                "org.alacritty",
                "com.apple.dt.Xcode",
                "com.microsoft.VSCode",
                "com.todesktop.230313mzl4w4u92",
                "dev.zed.Zed",
                "com.objective-see.lulu.app",
                "com.rafli.PowerSaver"
            ],
            suspendAgentLabels: [],
            autoSuspendCommonUpdaters: true,
            autoCleanCommonHelpers: true,
            extremeModeApps: [
                "Ollama",
                "LM Studio",
                "Docker Desktop",
                "Steam",
                "Discord",
                "Slack",
                "Spotify"
            ]
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var mainMenu = NSMenu()
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var sigtermSource: DispatchSourceSignal?
    private let scriptQueue = DispatchQueue(label: "com.rafli.powersaver.script", qos: .utility)

    private let defaults = UserDefaults.standard
    private let keyAutoSwitch = "autoSwitchOnBattery"
    private let keyExtremeMode = "extremeMode"
    private let keyAutoCloseIdleApps = "autoCloseIdleAppsOnBattery"
    private let keyManualOverrideActive = "powerSaverActive"

    private var lastPowerType: String = ""
    private var isPowerSaverActive: Bool = false
    private var isBusy: Bool = false
    private var lastActionSummary: String = ""
    private var config: PowerSaverConfig = PowerSaverConfig.defaultConfig()

    private let supportDir = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/PowerSaver")
    private var configFile: String { (supportDir as NSString).appendingPathComponent("config.json") }
    private var stoppedFile: String { (supportDir as NSString).appendingPathComponent("stopped_items.txt") }

    private var autoSwitchEnabled: Bool {
        get { defaults.object(forKey: keyAutoSwitch) == nil ? true : defaults.bool(forKey: keyAutoSwitch) }
        set { defaults.set(newValue, forKey: keyAutoSwitch) }
    }

    private var extremeModeEnabled: Bool {
        get { defaults.bool(forKey: keyExtremeMode) }
        set { defaults.set(newValue, forKey: keyExtremeMode) }
    }

    private var autoCloseIdleAppsEnabled: Bool {
        get { defaults.object(forKey: keyAutoCloseIdleApps) == nil ? true : defaults.bool(forKey: keyAutoCloseIdleApps) }
        set { defaults.set(newValue, forKey: keyAutoCloseIdleApps) }
    }

    private func resolveScriptPath(_ name: String) -> String {
        if let resourcePath = Bundle.main.resourcePath {
            let bundled = (resourcePath as NSString).appendingPathComponent("scripts/\(name)")
            if FileManager.default.isExecutableFile(atPath: bundled) {
                return bundled
            }
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent("bin/\(name)")
    }

    private func loadOrCreateConfig() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        if let data = fm.contents(atPath: configFile),
           let decoded = try? JSONDecoder().decode(PowerSaverConfig.self, from: data) {
            config = decoded
        } else {
            config = PowerSaverConfig.defaultConfig()
            saveConfig()
        }
    }

    private func saveConfig() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: URL(fileURLWithPath: configFile))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }

        loadOrCreateConfig()
        setupSigtermHandler()
        setupStatusBar()

        let currentPower = currentPowerSourceType()
        lastPowerType = currentPower
        if autoSwitchEnabled {
            let onBattery = (currentPower == kIOPSBatteryPowerValue)
            if onBattery || FileManager.default.fileExists(atPath: stoppedFile) {
                applyMode(active: onBattery, reason: "startup")
            } else {
                isPowerSaverActive = false
                defaults.set(false, forKey: keyManualOverrideActive)
                updateButtonAppearance()
            }
        } else {
            isPowerSaverActive = defaults.bool(forKey: keyManualOverrideActive)
            updateButtonAppearance()
        }

        startPowerSourceObserver()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let src = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSourceRunLoopSource = nil
        }
    }

    private func setupSigtermHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApp.terminate(nil)
        }
        source.resume()
        sigtermSource = source
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        mainMenu.delegate = self
        statusItem.menu = mainMenu
        updateButtonAppearance()
    }

    private func currentPowerSourceType() -> String {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else {
            return kIOPSACPowerValue
        }
        return type
    }

    private func batterySummary() -> (hasBattery: Bool, percent: Int?, isCharging: Bool, timeMinutes: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              !list.isEmpty else {
            return (false, nil, false, nil)
        }
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] {
                let pct = desc[kIOPSCurrentCapacityKey] as? Int
                let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
                let tte = desc[kIOPSTimeToEmptyKey] as? Int
                let ttf = desc[kIOPSTimeToFullChargeKey] as? Int
                let mins = charging ? ttf : tte
                let validMins = (mins != nil && mins! > 0) ? mins : nil
                return (true, pct, charging, validMins)
            }
        }
        return (false, nil, false, nil)
    }

    private func formatMinutes(_ mins: Int) -> String {
        let h = mins / 60
        let m = mins % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func startPowerSourceObserver() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx = ctx else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                delegate.handlePowerSourceChange()
            }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSourceRunLoopSource = source
        }
    }

    private func handlePowerSourceChange() {
        let newPower = currentPowerSourceType()
        guard newPower != lastPowerType else { return }
        lastPowerType = newPower

        if autoSwitchEnabled {
            applyMode(active: newPower == kIOPSBatteryPowerValue, reason: "power_change")
        } else {
            updateButtonAppearance()
        }
    }

    private func isProtected(_ app: NSRunningApplication) -> Bool {
        if let myBundle = Bundle.main.bundleIdentifier, app.bundleIdentifier == myBundle {
            return true
        }
        guard let bid = app.bundleIdentifier else { return false }
        return config.protectedBundleIDs.contains(bid)
    }

    private func windowlessIdleApps() -> [NSRunningApplication] {
        var openWindowPIDs = Set<pid_t>()
        if let windowList = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for w in windowList {
                let layer = (w[kCGWindowLayer as String] as? Int) ?? -1
                guard layer == 0,
                      let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                      let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: boundsDict),
                      rect.width >= 80, rect.height >= 80 else {
                    continue
                }
                openWindowPIDs.insert(pid)
            }
        }

        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular,
                  !app.isActive,
                  !app.isTerminated,
                  !isProtected(app) else {
                return false
            }
            return !openWindowPIDs.contains(app.processIdentifier)
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func recordStoppedItem(_ entry: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        var lines = stoppedItemsList()
        if !lines.contains(entry) {
            lines.append(entry)
            let payload = lines.joined(separator: "\n") + "\n"
            try? payload.write(toFile: stoppedFile, atomically: true, encoding: .utf8)
        }
    }

    private func closeWindowlessIdleApps() -> Int {
        let idleApps = windowlessIdleApps()
        var count = 0
        for app in idleApps {
            if app.terminate() {
                count += 1
            }
        }
        return count
    }

    private func closeExtremeModeApps() -> Int {
        let targets = Set(config.extremeModeApps.map { $0.lowercased() })
        guard !targets.isEmpty else { return 0 }
        var count = 0
        for app in NSWorkspace.shared.runningApplications {
            guard !app.isTerminated, !isProtected(app) else { continue }
            let name = (app.localizedName ?? "").lowercased()
            let bid = (app.bundleIdentifier ?? "").lowercased()
            let matches = targets.contains(name) || targets.contains(bid)
            if matches {
                if let url = app.bundleURL {
                    recordStoppedItem("apppath:\(url.path)")
                }
                if app.terminate() {
                    count += 1
                }
            }
        }
        return count
    }

    private func discoveredUserLaunchAgents() -> [(label: String, path: String)] {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
            return []
        }
        var results: [(String, String)] = []
        for file in files where file.hasSuffix(".plist") {
            let fullPath = (dir as NSString).appendingPathComponent(file)
            if let data = FileManager.default.contents(atPath: fullPath),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let label = plist["Label"] as? String {
                if label == "com.rafli.powersaver" || label == "com.user.superirit" {
                    continue
                }
                results.append((label, fullPath))
            }
        }
        return results.sorted { $0.0 < $1.0 }
    }

    private func stoppedItemsList() -> [String] {
        guard let content = try? String(contentsOfFile: stoppedFile, encoding: .utf8) else {
            return []
        }
        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func applyMode(active: Bool, reason: String) {
        loadOrCreateConfig()
        isPowerSaverActive = active
        defaults.set(active, forKey: keyManualOverrideActive)
        isBusy = true
        let useExtreme = extremeModeEnabled
        var closedIdleCount = 0
        var closedExtremeCount = 0

        if active {
            if autoCloseIdleAppsEnabled && reason != "extreme_toggled" {
                closedIdleCount = closeWindowlessIdleApps()
            }
            if useExtreme {
                closedExtremeCount = closeExtremeModeApps()
            }
        }
        updateButtonAppearance()

        let scriptPath: String
        var args: [String] = []
        if active {
            scriptPath = resolveScriptPath("power-saver.sh")
            if useExtreme {
                args.append("--extreme")
            }
        } else {
            scriptPath = resolveScriptPath("normal-mode.sh")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timestamp = formatter.string(from: Date())

        scriptQueue.async { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = [scriptPath] + args
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isBusy = false
                if active {
                    let totalClosed = closedIdleCount + closedExtremeCount
                    let note = totalClosed > 0 ? " + \(totalClosed) apps closed" : ""
                    self.lastActionSummary = "Enabled at \(timestamp)\(note)"
                } else {
                    self.lastActionSummary = "Restored at \(timestamp)"
                }
                self.updateButtonAppearance()
            }
        }
    }

    private func updateButtonAppearance() {
        guard let button = statusItem.button else { return }
        let symbolName = isPowerSaverActive ? "leaf.fill" : "bolt.fill"
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "PowerSaver") {
            img.isTemplate = true
            button.image = img
            button.title = ""
        } else {
            button.title = isPowerSaverActive ? "Saver" : "Normal"
        }
        button.toolTip = isPowerSaverActive ? "Power Saver Mode: ON" : "Power Saver Mode: OFF"
    }

    func menuWillOpen(_ menu: NSMenu) {
        loadOrCreateConfig()
        rebuildMenu()
    }

    private func addDisabledInfo(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func rebuildMenu() {
        mainMenu.removeAllItems()

        let onBattery = (currentPowerSourceType() == kIOPSBatteryPowerValue)
        let batt = batterySummary()
        let powerSourceStr: String
        if !batt.hasBattery {
            powerSourceStr = "AC Power (Desktop Mac)"
        } else {
            let pctStr = batt.percent.map { "\($0)%" } ?? "?"
            let timeStr = batt.timeMinutes.map { " • Est. \(formatMinutes($0))" } ?? ""
            powerSourceStr = onBattery
                ? "Battery \(pctStr)\(timeStr)"
                : "AC Power • Battery \(pctStr)"
        }

        let lpmStr = ProcessInfo.processInfo.isLowPowerModeEnabled ? "Low Power: ON" : "Low Power: OFF"
        let statusStr = isBusy
            ? "Status: Applying..."
            : (isPowerSaverActive ? "Mode: Power Saver ON (\(lpmStr))" : "Mode: Normal (\(lpmStr))")

        addDisabledInfo(powerSourceStr, to: mainMenu)
        addDisabledInfo(statusStr, to: mainMenu)
        if !lastActionSummary.isEmpty {
            addDisabledInfo(lastActionSummary, to: mainMenu)
        }

        mainMenu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: "Power Saver Mode", action: #selector(togglePowerSaver), keyEquivalent: "i")
        toggleItem.target = self
        toggleItem.state = isPowerSaverActive ? .on : .off
        mainMenu.addItem(toggleItem)

        let autoItem = NSMenuItem(title: "Auto-Switch on Unplug", action: #selector(toggleAutoSwitch), keyEquivalent: "a")
        autoItem.target = self
        autoItem.state = autoSwitchEnabled ? .on : .off
        mainMenu.addItem(autoItem)

        let autoIdleItem = NSMenuItem(title: "Auto-Close Windowless Apps", action: #selector(toggleAutoCloseIdle), keyEquivalent: "w")
        autoIdleItem.target = self
        autoIdleItem.state = autoCloseIdleAppsEnabled ? .on : .off
        mainMenu.addItem(autoIdleItem)

        let extremeItem = NSMenuItem(title: "Extreme Mode (Quit Configured Apps)", action: #selector(toggleExtremeMode), keyEquivalent: "e")
        extremeItem.target = self
        extremeItem.state = extremeModeEnabled ? .on : .off
        mainMenu.addItem(extremeItem)

        mainMenu.addItem(NSMenuItem.separator())

        // Submenu: Windowless idle apps
        let idleApps = windowlessIdleApps()
        let idleMenu = NSMenu()
        if idleApps.isEmpty {
            addDisabledInfo("No windowless idle apps", to: idleMenu)
        } else {
            let closeAll = NSMenuItem(title: "Close All (\(idleApps.count) apps)", action: #selector(closeAllIdleNow), keyEquivalent: "")
            closeAll.target = self
            idleMenu.addItem(closeAll)
            idleMenu.addItem(NSMenuItem.separator())
            for app in idleApps {
                let name = app.localizedName ?? app.bundleIdentifier ?? "App"
                let quitOne = NSMenuItem(title: "Quit \(name)", action: #selector(closeSpecificApp(_:)), keyEquivalent: "")
                quitOne.target = self
                quitOne.representedObject = app
                idleMenu.addItem(quitOne)

                if let bid = app.bundleIdentifier {
                    let protectOne = NSMenuItem(title: "  ↳ Protect \(name) (Never Auto-Close)", action: #selector(protectApp(_:)), keyEquivalent: "")
                    protectOne.target = self
                    protectOne.representedObject = bid
                    idleMenu.addItem(protectOne)
                }
            }
        }
        let idleParent = NSMenuItem(title: "Windowless Idle Apps (\(idleApps.count))", action: nil, keyEquivalent: "")
        idleParent.submenu = idleMenu
        mainMenu.addItem(idleParent)

        // Submenu: Dynamic User LaunchAgents discovery
        let agents = discoveredUserLaunchAgents()
        let agentsMenu = NSMenu()
        let updaterToggle = NSMenuItem(title: "Auto-Suspend Known Updaters", action: #selector(toggleCommonUpdaters), keyEquivalent: "")
        updaterToggle.target = self
        updaterToggle.state = config.autoSuspendCommonUpdaters ? .on : .off
        agentsMenu.addItem(updaterToggle)

        let helperToggle = NSMenuItem(title: "Auto-Clean Idle Background Helpers", action: #selector(toggleCommonHelpers), keyEquivalent: "")
        helperToggle.target = self
        helperToggle.state = config.autoCleanCommonHelpers ? .on : .off
        agentsMenu.addItem(helperToggle)

        if !agents.isEmpty {
            agentsMenu.addItem(NSMenuItem.separator())
            addDisabledInfo("Pause on Battery:", to: agentsMenu)
            for agent in agents {
                let item = NSMenuItem(title: agent.label, action: #selector(toggleAgentLabel(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = agent.label
                item.state = config.suspendAgentLabels.contains(agent.label) ? .on : .off
                agentsMenu.addItem(item)
            }
        }
        let agentsParent = NSMenuItem(title: "Background Agents (\(agents.count))", action: nil, keyEquivalent: "")
        agentsParent.submenu = agentsMenu
        mainMenu.addItem(agentsParent)

        // Submenu: Extreme mode app selection (dynamic from running apps + configured list)
        let extremeMenu = NSMenu()
        var knownNames = Set(config.extremeModeApps)
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !isProtected(app) {
            if let name = app.localizedName, !name.isEmpty {
                knownNames.insert(name)
            }
        }
        for appName in knownNames.sorted() {
            let item = NSMenuItem(title: appName, action: #selector(toggleExtremeApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = appName
            item.state = config.extremeModeApps.contains(where: { $0.caseInsensitiveCompare(appName) == .orderedSame }) ? .on : .off
            extremeMenu.addItem(item)
        }
        let extremeParent = NSMenuItem(title: "Extreme Mode Apps (\(config.extremeModeApps.count))", action: nil, keyEquivalent: "")
        extremeParent.submenu = extremeMenu
        mainMenu.addItem(extremeParent)

        // Submenu: Protected apps
        let protMenu = NSMenu()
        for bid in config.protectedBundleIDs.sorted() {
            let item = NSMenuItem(title: bid, action: #selector(unprotectApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bid
            item.state = .on
            protMenu.addItem(item)
        }
        let protParent = NSMenuItem(title: "Protected Apps (\(config.protectedBundleIDs.count))", action: nil, keyEquivalent: "")
        protParent.submenu = protMenu
        mainMenu.addItem(protParent)

        // Submenu: Currently suspended items
        let stopped = stoppedItemsList()
        if !stopped.isEmpty {
            let stoppedMenu = NSMenu()
            for entry in stopped {
                let cleanName = entry
                    .replacingOccurrences(of: "agent:", with: "Agent: ")
                    .replacingOccurrences(of: "apppath:", with: "App: ")
                    .replacingOccurrences(of: "app:", with: "App: ")
                addDisabledInfo(cleanName, to: stoppedMenu)
            }
            let stoppedParent = NSMenuItem(title: "Suspended Items (\(stopped.count))", action: nil, keyEquivalent: "")
            stoppedParent.submenu = stoppedMenu
            mainMenu.addItem(stoppedParent)
        }

        mainMenu.addItem(NSMenuItem.separator())

        let cleanNowItem = NSMenuItem(title: "Clean Background Now", action: #selector(runCleanNow), keyEquivalent: "r")
        cleanNowItem.target = self
        mainMenu.addItem(cleanNowItem)

        let openCfgItem = NSMenuItem(title: "Open Config (JSON)...", action: #selector(openConfigFile), keyEquivalent: ",")
        openCfgItem.target = self
        mainMenu.addItem(openCfgItem)

        let resetCfgItem = NSMenuItem(title: "Reset Default Config", action: #selector(resetDefaultConfig), keyEquivalent: "")
        resetCfgItem.target = self
        mainMenu.addItem(resetCfgItem)

        let sysOptItem = NSMenuItem(
            title: "Apply Battery pmset Optimization (sudo)...",
            action: #selector(runSystemOptimization),
            keyEquivalent: ""
        )
        sysOptItem.target = self
        mainMenu.addItem(sysOptItem)

        mainMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit PowerSaver", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        mainMenu.addItem(quitItem)
    }

    @objc private func togglePowerSaver() {
        applyMode(active: !isPowerSaverActive, reason: "manual_toggle")
    }

    @objc private func toggleAutoSwitch() {
        autoSwitchEnabled.toggle()
        if autoSwitchEnabled {
            let onBattery = (currentPowerSourceType() == kIOPSBatteryPowerValue)
            if onBattery != isPowerSaverActive {
                applyMode(active: onBattery, reason: "auto_enabled")
                return
            }
        }
        updateButtonAppearance()
    }

    @objc private func toggleAutoCloseIdle() {
        autoCloseIdleAppsEnabled.toggle()
    }

    @objc private func toggleExtremeMode() {
        extremeModeEnabled.toggle()
        if isPowerSaverActive {
            applyMode(active: true, reason: "extreme_toggled")
        }
    }

    @objc private func toggleCommonUpdaters() {
        config.autoSuspendCommonUpdaters.toggle()
        saveConfig()
    }

    @objc private func toggleCommonHelpers() {
        config.autoCleanCommonHelpers.toggle()
        saveConfig()
    }

    @objc private func toggleAgentLabel(_ sender: NSMenuItem) {
        guard let label = sender.representedObject as? String else { return }
        if let idx = config.suspendAgentLabels.firstIndex(of: label) {
            config.suspendAgentLabels.remove(at: idx)
        } else {
            config.suspendAgentLabels.append(label)
        }
        saveConfig()
    }

    @objc private func toggleExtremeApp(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        if let idx = config.extremeModeApps.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            config.extremeModeApps.remove(at: idx)
        } else {
            config.extremeModeApps.append(name)
        }
        saveConfig()
    }

    @objc private func protectApp(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        if !config.protectedBundleIDs.contains(bid) {
            config.protectedBundleIDs.append(bid)
            saveConfig()
        }
    }

    @objc private func unprotectApp(_ sender: NSMenuItem) {
        guard let bid = sender.representedObject as? String else { return }
        if bid == Bundle.main.bundleIdentifier || bid == "com.apple.finder" {
            return
        }
        config.protectedBundleIDs.removeAll { $0 == bid }
        saveConfig()
    }

    @objc private func closeAllIdleNow() {
        let count = closeWindowlessIdleApps()
        if count > 0 {
            lastActionSummary = "Closed \(count) idle apps"
        }
    }

    @objc private func closeSpecificApp(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? NSRunningApplication {
            _ = app.terminate()
            if let name = app.localizedName {
                lastActionSummary = "Closed \(name)"
            }
        }
    }

    @objc private func runCleanNow() {
        applyMode(active: true, reason: "clean_now")
    }

    @objc private func openConfigFile() {
        loadOrCreateConfig()
        NSWorkspace.shared.open(URL(fileURLWithPath: configFile))
    }

    @objc private func resetDefaultConfig() {
        config = PowerSaverConfig.defaultConfig()
        saveConfig()
        lastActionSummary = "Config reset to defaults"
    }

    @objc private func runSystemOptimization() {
        let scriptPath = resolveScriptPath("system-optimize.sh")
        isBusy = true
        updateButtonAppearance()
        scriptQueue.async { [weak self] in
            let source = "do shell script \"/bin/zsh '\(scriptPath)'\" with administrator privileges"
            var errInfo: NSDictionary?
            if let appleScript = NSAppleScript(source: source) {
                appleScript.executeAndReturnError(&errInfo)
            }
            DispatchQueue.main.async {
                self?.isBusy = false
                if errInfo == nil {
                    self?.lastActionSummary = "System optimization applied"
                }
                self?.updateButtonAppearance()
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
