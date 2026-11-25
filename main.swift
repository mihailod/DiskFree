// DiskFree — a menu bar item showing free shortSize on the startup disk.

import AppKit

/// Normal matches the other menu bar items: plain status item titles render at 13pt, although
/// menuBarFont reports 14 (measured). Big and Huge carry baseline shifts that center them in a
/// 31pt menu bar (measured).
enum FontSize: Int, CaseIterable {
    case normal, big, huge

    var title: String { ["Normal", "Big", "Huge"][rawValue] }
    var points: CGFloat { [13, 19, 24][rawValue] }
    var baselineOffset: CGFloat { [0, -2.75, -4.5][rawValue] }
}

/// Space that's safe to reclaim, grouped like Disk Diet's categories. Unused app languages are
/// left out: deleting them breaks the app's code signature.
enum Removable: CaseIterable {
    case caches, logs, temporary, trash

    var title: String {
        switch self {
        case .caches: "Caches"
        case .logs: "Logs"
        case .temporary: "Temporary Files"
        case .trash: "Trash"
        }
    }

    var folders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return switch self {
        case .caches: [home.appendingPathComponent("Library/Caches")]
        case .logs: [home.appendingPathComponent("Library/Logs"), URL(fileURLWithPath: "/Library/Logs"),
                     URL(fileURLWithPath: "/private/var/log")]
        case .temporary: [URL(fileURLWithPath: NSTemporaryDirectory())]
        case .trash: [home.appendingPathComponent(".Trash")]
        }
    }

    /// Bytes on disk across the readable folders, or nil when none can be read (Trash without
    /// Full Disk Access). Unreadable subfolders are skipped.
    func size() -> UInt64? {
        let protected = Set(Removable.protectedCaches.map { Removable.caches.folders[0].appendingPathComponent($0).path })
        let sizes = folders.compactMap { allocatedSize(of: $0, skipping: protected) }
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    /// What Delete removes: the items inside the folders this user owns, never the folders
    /// themselves. System logs belong to root and stay; Temporary Files keeps anything changed in
    /// the last day, since running apps may still be using it.
    func deletableItems() -> [URL] {
        let fm = FileManager.default
        let protected = Set(Removable.protectedCaches.map { Removable.caches.folders[0].appendingPathComponent($0).path })
        let dayAgo = Date().addingTimeInterval(-86_400)
        return folders.filter { fm.isWritableFile(atPath: $0.path) }
            .flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] }
            .filter { !protected.contains($0.path) }
            .filter { item in
                guard self == .temporary else { return true }
                let changed = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return (changed ?? .distantFuture) < dayAgo
            }
    }

    var deleteQuestion: String {
        switch self {
        case .caches: "Delete Caches?"
        case .logs: "Delete Logs?"
        case .temporary: "Delete Temporary Files?"
        case .trash: "Empty the Trash?"
        }
    }

    var deleteNote: String {
        switch self {
        case .caches: "Apps rebuild their caches when needed, so some may start more slowly the first time."
        case .logs: "Only your apps' logs in ~/Library/Logs; system logs need an administrator and stay."
        case .temporary: "Files changed in the last day stay, since running apps may still be using them."
        case .trash: "Same as Empty Trash in Finder."
        }
    }

    /// Cache folders macOS guards with privacy permissions. Merely opening one makes macOS ask the
    /// user for access (Apple Music, for com.apple.Music), so they're never entered.
    private static let protectedCaches: Set<String> = ["com.apple.Music", "com.apple.TV", "com.apple.Safari", "CloudKit"]
}

/// Where Claude (the desktop app, Claude Code and Cowork) keeps its data.
enum ClaudeData: CaseIterable {
    case code, settings, app, caches, logs, httpStorage, cowork

    var title: String {
        switch self {
        case .code: "~/.claude"
        case .settings: "~/.claude.json"
        case .app: "Application Support"
        case .caches: "Caches"
        case .logs: "Logs"
        case .httpStorage: "HTTP Storage"
        case .cowork: "~/Claude (Cowork)"
        }
    }

    var paths: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        /// Entries of `folder` whose names start with com.anthropic.
        func anthropic(_ folder: String) -> [URL] {
            let url = library.appendingPathComponent(folder)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            return names.filter { $0.hasPrefix("com.anthropic.") }.map { url.appendingPathComponent($0) }
        }
        return switch self {
        case .code: [home.appendingPathComponent(".claude")]
        case .settings: [home.appendingPathComponent(".claude.json"), home.appendingPathComponent(".claude.json.backup")]
        case .app: [library.appendingPathComponent("Application Support/Claude")]
        case .caches: [library.appendingPathComponent("Caches/Claude"), library.appendingPathComponent("Caches/claude-cli-nodejs")]
            + anthropic("Caches")
        case .logs: [library.appendingPathComponent("Logs/Claude")]
        case .httpStorage: anthropic("HTTPStorages")
        case .cowork: [home.appendingPathComponent("Claude")]
        }
    }

    /// Bytes on disk, or nil when none of the paths exist.
    func size() -> UInt64? {
        let sizes = paths.compactMap { allocatedSize(of: $0) }
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    /// Superseded copies of the Claude Code CLI bundled with the desktop app: every version folder
    /// except the newest. They're safe to delete once no session runs from them.
    static func oldVersions() -> [URL] {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code")
        let versions = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
        return Array(versions.dropLast())
    }

    /// Claude's local virtual machine images, several GB each. Shown in the menu only; some
    /// developers keep them on purpose.
    static func vmBundles() -> [URL] {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude")
        return ["vm_bundles", "claude-code-vm"].map { folder.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The old versions that a running process (a Claude Code session started before the last
    /// update) still executes from; deleting those could break the session.
    static func inUse(_ versions: [URL]) -> Set<URL> {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) * 2)
        let found = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        var executables: [String] = []
        for pid in pids.prefix(max(found, 0)) where proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            executables.append(String(cString: path))
        }
        return Set(versions.filter { version in executables.contains { $0.hasPrefix(version.path + "/") } })
    }

    /// Whether the Claude desktop app is installed anywhere Launch Services knows of.
    static var appInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil
    }
}

/// Bytes on disk taken by a file, or by everything inside a folder, or nil when it doesn't exist
/// or can't be read. Unreadable subfolders are skipped, and so are the folders in `skipping`
/// (full paths).
func allocatedSize(of url: URL, skipping: Set<String> = []) -> UInt64? {
    let fm = FileManager.default
    var isFolder: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isFolder) else { return nil }
    guard isFolder.boolValue else {
        return (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize.map(UInt64.init)
    }
    guard (try? fm.contentsOfDirectory(atPath: url.path)) != nil,
          let files = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                                    errorHandler: { _, _ in true }) else { return nil }
    var total: UInt64 = 0
    for case let file as URL in files {
        if skipping.contains(file.path) {
            files.skipDescendants()
            continue
        }
        total += UInt64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
    }
    return total
}

/// Decimal GB to one decimal place, like Finder, without the unit; a whole number drops the .0
/// (1GB, not 1.0GB).
func decimalGB(_ bytes: UInt64) -> String {
    let text = String(format: "%.1f", Double(bytes) / 1_000_000_000)
    return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
}

/// GB to one decimal like Finder, whole MB below 0.1GB (where GB would show 0.0), and whole KB
/// below 1MB (where MB would show 0). Nothing at all reads "(none)"; a few bytes round up to 1KB,
/// so nothing that exists shows as 0.
func shortSize(_ bytes: UInt64) -> String {
    bytes == 0 ? "(none)"
        : bytes < 1_000_000 ? "\(max(bytes / 1_000, 1))KB"
        : bytes < 100_000_000 ? "\(bytes / 1_000_000)MB" : decimalGB(bytes) + "GB"
}

/// Finder-style size with a fitting unit ("31.5 MB", "1.02 GB"), for dialogs where 0.0GB would hide
/// what's about to be deleted.
func finderSize(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Free space a macOS upgrade needs: Apple lists about 25GB for recent releases, plus 5GB of
    /// margin because part of the free space shown is purgeable and may not all be cleared.
    private static let upgradeGB = 30
    /// Claude's brand orange (#D97757), the color of the Claude app icon, on a dark menu bar. On a
    /// light one that's only 2.9:1 contrast, so it deepens to #B4532F (same hue, 4.6:1).
    private static let claudeColor = NSColor(name: "ClaudeOrange") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xB4 / 255.0, green: 0x53 / 255.0, blue: 0x2F / 255.0, alpha: 1)
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var swapItem: NSMenuItem!
    private var removableItem: NSMenuItem!
    private var removableItems: [Removable: NSMenuItem] = [:]
    /// Each Junk category's Delete submenu, attached only while it has something to delete.
    private var junkDeleteMenus: [Removable: NSMenu] = [:]
    private var claudeItem: NSMenuItem!
    private var claudeItems: [ClaudeData: NSMenuItem] = [:]
    private var claudeMenu: NSMenu!
    private var oldVersionsItem: NSMenuItem!
    /// Old Claude Code ▸ Delete, attached only while there are old versions.
    private var deleteOldVersionsMenu: NSMenu!
    private var vmBundlesItem: NSMenuItem!
    private var measuring = false
    /// Set when a measurement is asked for while one is running, so it runs again afterwards.
    private var measureAgain = false
    /// Last measured totals of Junk and Claude, and when; the menu bar shows them.
    private var removableBytes: UInt64?
    private var claudeBytes: UInt64?
    /// Whether there are old CLI versions to delete; the menu bar shows Claude in
    /// red. VM bundles don't count: some developers use them on purpose.
    private var claudeHasOldVersions = false
    private var removableMeasuredAt = Date.distantPast
    /// How long the last walk took; the next one waits at least 100× that, so Junk and Claude
    /// never take more than ~1% of the time however large the folders grow.
    private var removableWalkSeconds: TimeInterval = 0
    private var unitItem: NSMenuItem!
    private var swapToggle: NSMenuItem!
    private var removableToggle: NSMenuItem!
    private var claudeToggle: NSMenuItem!
    private var boldItem: NSMenuItem!
    private var bold: Bool {
        get { UserDefaults.standard.bool(forKey: "bold") }
        set { UserDefaults.standard.set(newValue, forKey: "bold") }
    }
    private var showUnit: Bool {
        get { UserDefaults.standard.bool(forKey: "showUnit") }
        set { UserDefaults.standard.set(newValue, forKey: "showUnit") }
    }
    private var showSwap: Bool {
        get { UserDefaults.standard.bool(forKey: "showSwap") }
        set { UserDefaults.standard.set(newValue, forKey: "showSwap") }
    }
    private var showRemovable: Bool {
        get { UserDefaults.standard.bool(forKey: "showRemovable") }
        set { UserDefaults.standard.set(newValue, forKey: "showRemovable") }
    }
    private var showClaude: Bool {
        get { UserDefaults.standard.bool(forKey: "showClaude") }
        set { UserDefaults.standard.set(newValue, forKey: "showClaude") }
    }
    private var fontSize: FontSize {
        get { FontSize(rawValue: UserDefaults.standard.integer(forKey: "fontSize")) ?? .huge }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "fontSize") }
    }
    /// Whether the all-clear state uses the menu bar's own text color instead of green.
    private var okUsesSystemColor: Bool {
        get { UserDefaults.standard.bool(forKey: "okUsesSystemColor") }
        set { UserDefaults.standard.set(newValue, forKey: "okUsesSystemColor") }
    }
    /// How often free space and swap are re-read. They cost microseconds, so even 1s is cheap.
    private static let refreshChoices = [1, 5, 10]
    private var refreshSeconds: Int {
        get { UserDefaults.standard.integer(forKey: "refreshSeconds") }
        set { UserDefaults.standard.set(newValue, forKey: "refreshSeconds") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["fontSize": FontSize.huge.rawValue, "bold": true, "refreshSeconds": 1])

        let menu = NSMenu()
        menu.delegate = self
        // Info lines have no action; keep them in normal text rather than greyed out.
        menu.autoenablesItems = false
        swapItem = menu.addItem(withTitle: "Swap: –", action: nil, keyEquivalent: "")
        removableItem = menu.addItem(withTitle: "Junk: –", action: nil, keyEquivalent: "")
        let removableMenu = NSMenu()
        removableMenu.autoenablesItems = false
        for category in Removable.allCases {
            removableItems[category] = removableMenu.addItem(withTitle: "\(category.title): –", action: nil, keyEquivalent: "")
            let deleteMenu = NSMenu()
            let deleteItem = deleteMenu.addItem(withTitle: "Delete", action: #selector(deleteJunk(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.tag = Removable.allCases.firstIndex(of: category)!
            junkDeleteMenus[category] = deleteMenu
        }
        removableItem.submenu = removableMenu
        claudeItem = menu.addItem(withTitle: "Claude: –", action: nil, keyEquivalent: "")
        claudeMenu = NSMenu()
        claudeMenu.autoenablesItems = false
        for category in ClaudeData.allCases {
            claudeItems[category] = claudeMenu.addItem(withTitle: "\(category.title): –", action: nil, keyEquivalent: "")
        }
        claudeMenu.addItem(.separator())
        oldVersionsItem = claudeMenu.addItem(withTitle: "Old Claude Code: –", action: nil, keyEquivalent: "")
        deleteOldVersionsMenu = NSMenu()
        deleteOldVersionsMenu.addItem(withTitle: "Delete", action: #selector(deleteOldVersions), keyEquivalent: "").target = self
        claudeMenu.addItem(.separator())
        vmBundlesItem = claudeMenu.addItem(withTitle: "VM Bundles: –", action: nil, keyEquivalent: "")
        claudeItem.submenu = claudeMenu
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "").target = self
        let everyMenu = NSMenu()
        for seconds in Self.refreshChoices {
            let everyItem = everyMenu.addItem(withTitle: seconds == 1 ? "1 Second" : "\(seconds) Seconds",
                                              action: #selector(pickRefreshInterval(_:)), keyEquivalent: "")
            everyItem.target = self
            everyItem.tag = seconds
            everyItem.state = seconds == refreshSeconds ? .on : .off
        }
        menu.addItem(withTitle: "Refresh Every", action: nil, keyEquivalent: "").submenu = everyMenu
        menu.addItem(.separator())
        unitItem = menu.addItem(withTitle: "Show GB", action: #selector(toggleUnit), keyEquivalent: "")
        unitItem.target = self
        unitItem.state = showUnit ? .on : .off
        menu.addItem(.separator())
        swapToggle = menu.addItem(withTitle: "Show Swap", action: #selector(toggleSwap), keyEquivalent: "")
        swapToggle.target = self
        swapToggle.state = showSwap ? .on : .off
        removableToggle = menu.addItem(withTitle: "Show Junk", action: #selector(toggleRemovable), keyEquivalent: "")
        removableToggle.target = self
        removableToggle.state = showRemovable ? .on : .off
        claudeToggle = menu.addItem(withTitle: "Show Claude", action: #selector(toggleClaude), keyEquivalent: "")
        claudeToggle.target = self
        claudeToggle.state = showClaude ? .on : .off
        menu.addItem(.separator())

        let sizeMenu = NSMenu()
        for size in FontSize.allCases {
            let sizeItem = sizeMenu.addItem(withTitle: size.title, action: #selector(pickFontSize(_:)), keyEquivalent: "")
            sizeItem.target = self
            sizeItem.tag = size.rawValue
            sizeItem.state = size == fontSize ? .on : .off
        }
        menu.addItem(withTitle: "Font Size", action: nil, keyEquivalent: "").submenu = sizeMenu
        boldItem = menu.addItem(withTitle: "Bold Font", action: #selector(toggleBold), keyEquivalent: "")
        boldItem.target = self
        boldItem.state = bold ? .on : .off

        let okMenu = NSMenu()
        for (tag, title) in ["Green", "System"].enumerated() {
            let okItem = okMenu.addItem(withTitle: title, action: #selector(pickOKColor(_:)), keyEquivalent: "")
            okItem.target = self
            okItem.tag = tag
            okItem.state = (tag == 1) == okUsesSystemColor ? .on : .off
        }
        menu.addItem(withTitle: "OK Color", action: nil, keyEquivalent: "").submenu = okMenu

        menu.addItem(.separator())
        menu.addItem(withTitle: "About DiskFree", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit DiskFree", action: #selector(quit), keyEquivalent: "").target = self
        item.menu = menu

        refresh()
        measureFolders()
        startTimer()

        // Refresh right away after waking, so the number isn't stale.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshNow()
    }

    @objc private func refreshNow() {
        refresh()
        measureFolders()
    }

    /// Walks the Junk and Claude folders off the main thread; the menu updates in place when done.
    private func measureFolders() {
        guard !measuring else {
            measureAgain = true
            return
        }
        measuring = true
        DispatchQueue.global(qos: .utility).async {
            let start = Date()
            let sizes = Dictionary(uniqueKeysWithValues: Removable.allCases.map { ($0, $0.size()) })
            let claudeSizes = Dictionary(uniqueKeysWithValues: ClaudeData.allCases.map { ($0, $0.size()) })
            let oldVersions = ClaudeData.oldVersions()
            let oldVersionsBytes = oldVersions.compactMap { allocatedSize(of: $0) }.reduce(0, +)
            let vmBundles = ClaudeData.vmBundles()
            let vmBundlesBytes = vmBundles.compactMap { allocatedSize(of: $0) }.reduce(0, +)
            let claudeInstalled = ClaudeData.appInstalled || claudeSizes.values.contains { $0 != nil }
            let seconds = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                self.measuring = false
                self.removableWalkSeconds = seconds
                for (category, size) in sizes {
                    self.removableItems[category]?.title =
                        "\(category.title): \(size.map(shortSize) ?? "needs Full Disk Access")"
                    self.removableItems[category]?.submenu = (size ?? 0) > 0 ? self.junkDeleteMenus[category] : nil
                }
                let total = sizes.values.compactMap { $0 }.reduce(0, +)
                self.removableItem.title = total == 0 ? "Junk: \(shortSize(0))" : "Junk: \(shortSize(total)) (Clean to reclaim)"
                self.removableBytes = total
                for (category, size) in claudeSizes {
                    self.claudeItems[category]?.title = "\(category.title): \(shortSize(size ?? 0))"
                }
                self.oldVersionsItem.title = oldVersions.isEmpty ? "Old Claude Code: (none)"
                    : "Old Claude Code: \(shortSize(oldVersionsBytes)) (\(oldVersions.map(\.lastPathComponent).joined(separator: ", ")))"
                self.oldVersionsItem.submenu = oldVersions.isEmpty ? nil : self.deleteOldVersionsMenu
                let claudeTotal = claudeSizes.values.compactMap { $0 }.reduce(0, +)
                // Nothing to break down when Claude isn't there, so no submenu then.
                self.claudeItem.title = claudeInstalled ? "Claude: \(shortSize(claudeTotal)) (Triage to reclaim)" : "Claude (Not installed)"
                self.claudeItem.submenu = claudeInstalled ? self.claudeMenu : nil
                self.claudeBytes = claudeInstalled ? claudeTotal : nil
                self.vmBundlesItem.title = vmBundles.isEmpty ? "VM Bundles: (none)"
                    : "VM Bundles: \(shortSize(vmBundlesBytes)) (\(vmBundles.map(\.lastPathComponent).joined(separator: ", ")))"
                self.claudeHasOldVersions = !oldVersions.isEmpty
                self.removableMeasuredAt = Date()
                self.refresh()
                if self.measureAgain {
                    self.measureAgain = false
                    self.measureFolders()
                }
            }
        }
    }

    /// Not wired straight to terminate(_:): macOS 26 gives that action an automatic icon, and
    /// the icon column it adds leaves an empty gap in front of every other item.
    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func showAbout() {
        // A menu bar app is never frontmost on its own, so bring the panel forward explicitly.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .version: "",  // hides the build number; the version comes from Info.plist
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "by Mihailo Despotovic, 2026",
        ])
    }

    @objc private func toggleUnit() {
        showUnit.toggle()
        unitItem.state = showUnit ? .on : .off
        refresh()
    }

    @objc private func toggleSwap() {
        showSwap.toggle()
        swapToggle.state = showSwap ? .on : .off
        refresh()
    }

    @objc private func toggleRemovable() {
        showRemovable.toggle()
        removableToggle.state = showRemovable ? .on : .off
        refresh()
    }

    /// Deletes one Junk category's contents (see Removable.deletableItems) after asking.
    @objc private func deleteJunk(_ sender: NSMenuItem) {
        let category = Removable.allCases[sender.tag]
        let items = category.deletableItems()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        guard !items.isEmpty else {
            alert.messageText = "Nothing to delete"
            alert.informativeText = category.deleteNote
            alert.runModal()
            return measureFolders()
        }
        let bytes = items.compactMap { allocatedSize(of: $0) }.reduce(0, +)
        alert.messageText = category.deleteQuestion
        alert.informativeText = "\(finderSize(bytes)) will be permanently deleted. " + category.deleteNote
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .utility).async {
            let failures = items.filter { (try? FileManager.default.removeItem(at: $0)) == nil }.count
            DispatchQueue.main.async {
                self.measureFolders()
                guard failures > 0 else { return }
                let failed = NSAlert()
                failed.messageText = failures == 1 ? "1 item couldn't be deleted" : "\(failures) items couldn't be deleted"
                failed.informativeText = "They may be in use or protected by macOS."
                failed.runModal()
            }
        }
    }

    /// Deletes the old bundled CLI versions after asking. Versions a
    /// running Claude session still uses are kept.
    @objc private func deleteOldVersions() {
        let versions = ClaudeData.oldVersions()
        // Gone since the menu was built (deleted some other way): just update the menu.
        guard !versions.isEmpty else { return measureFolders() }
        let busy = ClaudeData.inUse(versions)
        let doomed = versions.filter { !busy.contains($0) }
        let names = { (urls: [URL]) in urls.map(\.lastPathComponent).joined(separator: ", ") }
        let busyNote = busy.isEmpty ? "" : "\n\n\(names(versions.filter(busy.contains))) is still running in a Claude session and will be kept."

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        guard !doomed.isEmpty else {
            alert.messageText = "Nothing deleted"
            alert.informativeText = "\(names(versions)) is still running in a Claude session. Quit those sessions and try again."
            alert.runModal()
            return
        }
        let bytes = doomed.compactMap { allocatedSize(of: $0) }.reduce(0, +)
        alert.messageText = "Delete old Claude Code versions?"
        alert.informativeText = "\(names(doomed)) (\(finderSize(bytes))) will be permanently deleted. "
            + "Claude keeps using the newest version." + busyNote
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .utility).async {
            var failures: [String] = []
            for version in doomed {
                do { try FileManager.default.removeItem(at: version) }
                catch { failures.append("\(version.lastPathComponent): \(error.localizedDescription)") }
            }
            DispatchQueue.main.async {
                self.measureFolders()
                guard !failures.isEmpty else { return }
                let failed = NSAlert()
                failed.messageText = "Some old Claude Code versions couldn't be deleted"
                failed.informativeText = failures.joined(separator: "\n")
                failed.runModal()
            }
        }
    }

    @objc private func toggleClaude() {
        showClaude.toggle()
        claudeToggle.state = showClaude ? .on : .off
        refresh()
    }

    @objc private func toggleBold() {
        bold.toggle()
        boldItem.state = bold ? .on : .off
        refresh()
    }

    @objc private func pickFontSize(_ sender: NSMenuItem) {
        guard let size = FontSize(rawValue: sender.tag) else { return }
        fontSize = size
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
        refresh()
    }

    private func startTimer() {
        timer?.invalidate()
        let interval = TimeInterval(refreshSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = interval / 5
    }

    @objc private func pickRefreshInterval(_ sender: NSMenuItem) {
        refreshSeconds = sender.tag
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
        startTimer()
    }

    @objc private func pickOKColor(_ sender: NSMenuItem) {
        okUsesSystemColor = sender.tag == 1
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
        refresh()
    }

    @objc private func refresh() {
        guard let button = item.button else { return }
        let gb = freeGigabytes()
        let text = gb.map { showUnit ? "\($0)GB" : String($0) } ?? "–"
        let okColor: NSColor = okUsesSystemColor ? .labelColor : .systemGreen
        // Red: an upgrade won't fit. Orange: it fits, but would leave under 1/8 of the drive free.
        let orangeBelow = Self.upgradeGB + Int((nominalDiskBytes() ?? 0) / 8 / 1_000_000_000)
        let color: NSColor = switch gb {
        case nil: .labelColor
        case let gb? where gb < Self.upgradeGB: .systemRed
        case let gb? where gb < orangeBelow: .systemOrange
        default: okColor
        }
        /// Orange from `orangeAt` bytes up, red from `redAt` up, the OK color below.
        func usageColor(_ bytes: UInt64?, orangeAt: UInt64, redAt: UInt64) -> NSColor {
            guard let bytes else { return okColor }
            return bytes >= redAt ? .systemRed : bytes >= orangeAt ? .systemOrange : okColor
        }

        let swap = swapBytes()
        // With Show GB off the numbers carry no unit, so they stay in GB (0.0) rather than
        // switching to a bare MB figure that would read as gigabytes.
        // Zero is a plain 0 here: "(none)" reads oddly next to the other numbers.
        func amount(_ bytes: UInt64) -> String { bytes == 0 ? "0" : showUnit ? shortSize(bytes) : decimalGB(bytes) }
        var extras: [(String, NSColor)] = []
        if showSwap {
            // Relative to RAM: 1/8 is orange, 1/4 is red (2GB and 4GB with 16GB).
            let ram = ProcessInfo.processInfo.physicalMemory
            extras.append(("Swap \(swap.map(amount) ?? "–")",
                           usageColor(swap, orangeAt: ram / 8, redAt: ram / 4)))
        }
        if showRemovable {
            // Relative to the drive: 1/128 is orange, 1/64 is red (2GB and 4GB on 256GB).
            let disk = nominalDiskBytes() ?? .max
            extras.append(("Junk \(removableBytes.map(amount) ?? "–")",
                           usageColor(removableBytes, orangeAt: disk / 128, redAt: disk / 64)))
        }
        if showClaude {
            // No size thresholds: Claude's brand orange, or red while old CLI versions are waiting
            // to be deleted.
            extras.append(("Claude \(claudeBytes.map(amount) ?? "–")",
                           claudeHasOldVersions ? .systemRed : Self.claudeColor))
        }
        // Every 30s, or 100× the last walk's duration if that's longer.
        if (showRemovable || showClaude),
           Date().timeIntervalSince(removableMeasuredAt) >= max(30, removableWalkSeconds * 100) {
            measureFolders()
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize.points, weight: bold ? .heavy : .regular)
        func run(_ string: String, _ color: NSColor) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: font, .foregroundColor: color, .baselineOffset: fontSize.baselineOffset,
            ])
        }
        let title = NSMutableAttributedString(attributedString: run(text, color))
        for (index, (string, extraColor)) in extras.enumerated() {
            title.append(run(index == 0 ? " • " : "  ", color))
            title.append(run(string, extraColor))
        }
        button.attributedTitle = title
        button.toolTip = gb.map { "\($0) GB free" }
        swapItem.title = switch swap {
        case nil: "Swap: –"
        case 0?: "Swap: \(shortSize(0))"
        case let bytes?: "Swap: \(shortSize(bytes)) (Reboot to reclaim)"
        }
    }

    /// Size of the swap files on disk; macOS deletes them on restart.
    private func swapBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return usage.xsu_total
    }

    /// The drive's marketed size (256GB, 512GB, 1TB…): macOS reports less (245GB for a 256GB
    /// drive), so round its capacity up to the next power of two GB.
    private func nominalDiskBytes() -> UInt64? {
        guard let total = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey])
            .volumeTotalCapacity else { return nil }
        var gb: UInt64 = 1
        while gb * 1_000_000_000 < UInt64(total) { gb *= 2 }
        return gb * 1_000_000_000
    }

    /// Free space on the boot volume in decimal GB (what Finder shows), including purgeable space.
    private func freeGigabytes() -> Int? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return Int(bytes / 1_000_000_000)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
