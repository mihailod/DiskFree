// DiskFree — a menu bar item showing free gigabytes on the startup disk.

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
        let sizes = folders.compactMap(Removable.allocatedSize)
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    /// Cache folders macOS guards with privacy permissions. Merely opening one makes macOS ask the
    /// user for access (Apple Music, for com.apple.Music), so they're never entered.
    private static let protectedCaches: Set<String> = ["com.apple.Music", "com.apple.TV", "com.apple.Safari", "CloudKit"]

    private static func allocatedSize(of folder: URL) -> UInt64? {
        let fm = FileManager.default
        guard (try? fm.contentsOfDirectory(atPath: folder.path)) != nil,
              let files = fm.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                                        errorHandler: { _, _ in true }) else { return nil }
        let protected = Set(protectedCaches.map { Removable.caches.folders[0].appendingPathComponent($0).path })
        var total: UInt64 = 0
        for case let file as URL in files {
            if protected.contains(file.path) {
                files.skipDescendants()
                continue
            }
            total += UInt64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Decimal GB to one decimal place, like Finder, without the unit.
func decimalGB(_ bytes: UInt64) -> String {
    String(format: "%.1f", Double(bytes) / 1_000_000_000)
}

func gigabytes(_ bytes: UInt64) -> String {
    decimalGB(bytes) + "GB"
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Free space a macOS upgrade needs: Apple lists about 25GB for recent releases, plus 5GB of
    /// margin because part of the free space shown is purgeable and may not all be cleared.
    private static let upgradeGB = 30

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var swapItem: NSMenuItem!
    private var removableItem: NSMenuItem!
    private var removableItems: [Removable: NSMenuItem] = [:]
    private var measuring = false
    /// Last measured total of all removable categories, and when; the menu bar shows it.
    private var removableBytes: UInt64?
    private var removableMeasuredAt = Date.distantPast
    /// How long the last walk took; the next one waits at least 100× that, so Junk never takes
    /// more than ~1% of the time however large the caches grow.
    private var removableWalkSeconds: TimeInterval = 0
    private var unitItem: NSMenuItem!
    private var swapToggle: NSMenuItem!
    private var removableToggle: NSMenuItem!
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
        }
        removableItem.submenu = removableMenu
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
        swapToggle = menu.addItem(withTitle: "Show Swap", action: #selector(toggleSwap), keyEquivalent: "")
        swapToggle.target = self
        swapToggle.state = showSwap ? .on : .off
        removableToggle = menu.addItem(withTitle: "Show Junk", action: #selector(toggleRemovable), keyEquivalent: "")
        removableToggle.target = self
        removableToggle.state = showRemovable ? .on : .off
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
        measureRemovable()
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
        measureRemovable()
    }

    /// Walks the removable folders off the main thread; the menu updates in place when done.
    private func measureRemovable() {
        guard !measuring else { return }
        measuring = true
        DispatchQueue.global(qos: .utility).async {
            let start = Date()
            let sizes = Dictionary(uniqueKeysWithValues: Removable.allCases.map { ($0, $0.size()) })
            let seconds = Date().timeIntervalSince(start)
            DispatchQueue.main.async {
                self.measuring = false
                self.removableWalkSeconds = seconds
                for (category, size) in sizes {
                    self.removableItems[category]?.title =
                        "\(category.title): \(size.map(gigabytes) ?? "needs Full Disk Access")"
                }
                let total = sizes.values.compactMap { $0 }.reduce(0, +)
                self.removableItem.title = total == 0 ? "Junk: 0.0GB" : "Junk: \(gigabytes(total)) (Clean to reclaim)"
                self.removableBytes = total
                self.removableMeasuredAt = Date()
                self.refresh()
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
        let unit = showUnit ? "GB" : ""
        var extras: [(String, NSColor)] = []
        if showSwap {
            // Relative to RAM: 1/8 is orange, 1/4 is red (2GB and 4GB with 16GB).
            let ram = ProcessInfo.processInfo.physicalMemory
            extras.append(("Swap \(swap.map { decimalGB($0) + unit } ?? "–")",
                           usageColor(swap, orangeAt: ram / 8, redAt: ram / 4)))
        }
        if showRemovable {
            // Relative to the drive: 1/128 is orange, 1/64 is red (2GB and 4GB on 256GB).
            let disk = nominalDiskBytes() ?? .max
            extras.append(("Junk \(removableBytes.map { decimalGB($0) + unit } ?? "–")",
                           usageColor(removableBytes, orangeAt: disk / 128, redAt: disk / 64)))
            // Every 30s, or 100× the last walk's duration if that's longer.
            if Date().timeIntervalSince(removableMeasuredAt) >= max(30, removableWalkSeconds * 100) {
                measureRemovable()
            }
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
        case 0?: "Swap: 0.0GB"
        case let bytes?: "Swap: \(decimalGB(bytes))GB (Reboot to reclaim)"
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
