import Cocoa
import IOKit.ps

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

    private let stoppedFile = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/PowerSaver/stopped_items.txt")

    private let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.rafli.PowerSaver",
        "com.objective-see.lulu.app",
        "com.microsoft.VSCode",
        "com.google.antigravity",
        "com.google.antigravity-ide"
    ]

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }

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

    private func batterySummary() -> (percent: Int?, isCharging: Bool, timeMinutes: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false, nil)
        }
        for ps in list {
            if let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] {
                let pct = desc[kIOPSCurrentCapacityKey] as? Int
                let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
                let tte = desc[kIOPSTimeToEmptyKey] as? Int
                let ttf = desc[kIOPSTimeToFullChargeKey] as? Int
                let mins = charging ? ttf : tte
                let validMins = (mins != nil && mins! > 0) ? mins : nil
                return (pct, charging, validMins)
            }
        }
        return (nil, false, nil)
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
                  let bid = app.bundleIdentifier,
                  !protectedBundleIDs.contains(bid) else {
                return false
            }
            return !openWindowPIDs.contains(app.processIdentifier)
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
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
        isPowerSaverActive = active
        defaults.set(active, forKey: keyManualOverrideActive)
        isBusy = true
        let useExtreme = extremeModeEnabled
        var closedIdleCount = 0
        if active && autoCloseIdleAppsEnabled && reason != "extreme_toggled" {
            closedIdleCount = closeWindowlessIdleApps()
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
                    let idleNote = closedIdleCount > 0 ? " + \(closedIdleCount) idle apps" : ""
                    self.lastActionSummary = "Enabled at \(timestamp)\(idleNote)"
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
        let pctStr = batt.percent.map { "\($0)%" } ?? "?"
        let timeStr = batt.timeMinutes.map { " • Est. \(formatMinutes($0))" } ?? ""
        let powerSourceStr = onBattery
            ? "Battery \(pctStr)\(timeStr)"
            : "AC Power • Battery \(pctStr)"

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

        let extremeItem = NSMenuItem(title: "Extreme Mode (Quit Menu Bar Utilities)", action: #selector(toggleExtremeMode), keyEquivalent: "e")
        extremeItem.target = self
        extremeItem.state = extremeModeEnabled ? .on : .off
        mainMenu.addItem(extremeItem)

        mainMenu.addItem(NSMenuItem.separator())

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
                let appItem = NSMenuItem(title: "Quit \(name)", action: #selector(closeSpecificApp(_:)), keyEquivalent: "")
                appItem.target = self
                appItem.representedObject = app
                idleMenu.addItem(appItem)
            }
        }
        let idleParent = NSMenuItem(title: "Windowless Idle Apps (\(idleApps.count))", action: nil, keyEquivalent: "")
        idleParent.submenu = idleMenu
        mainMenu.addItem(idleParent)

        let stopped = stoppedItemsList()
        if !stopped.isEmpty {
            let stoppedMenu = NSMenu()
            for entry in stopped {
                let cleanName = entry
                    .replacingOccurrences(of: "agent:", with: "Agent: ")
                    .replacingOccurrences(of: "app:", with: "App: ")
                addDisabledInfo(cleanName, to: stoppedMenu)
            }
            let stoppedParent = NSMenuItem(title: "Suspended Items (\(stopped.count))", action: nil, keyEquivalent: "")
            stoppedParent.submenu = stoppedMenu
            mainMenu.addItem(stoppedParent)
        }

        let cleanNowItem = NSMenuItem(title: "Clean Background Now", action: #selector(runCleanNow), keyEquivalent: "r")
        cleanNowItem.target = self
        mainMenu.addItem(cleanNowItem)

        mainMenu.addItem(NSMenuItem.separator())

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
