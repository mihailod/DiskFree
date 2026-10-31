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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var unitItem: NSMenuItem!
    private var boldItem: NSMenuItem!
    private var bold: Bool {
        get { UserDefaults.standard.bool(forKey: "bold") }
        set { UserDefaults.standard.set(newValue, forKey: "bold") }
    }
    private var showUnit: Bool {
        get { UserDefaults.standard.bool(forKey: "showUnit") }
        set { UserDefaults.standard.set(newValue, forKey: "showUnit") }
    }
    private var fontSize: FontSize {
        get { FontSize(rawValue: UserDefaults.standard.integer(forKey: "fontSize")) ?? .huge }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "fontSize") }
    }
    /// Whether 50 GB and up uses the menu bar's own text color instead of green.
    private var okUsesSystemColor: Bool {
        get { UserDefaults.standard.bool(forKey: "okUsesSystemColor") }
        set { UserDefaults.standard.set(newValue, forKey: "okUsesSystemColor") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["fontSize": FontSize.huge.rawValue, "bold": true])

        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "").target = self
        menu.addItem(.separator())
        unitItem = menu.addItem(withTitle: "GB on/off", action: #selector(toggleUnit), keyEquivalent: "")
        unitItem.target = self
        unitItem.state = showUnit ? .on : .off
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
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 5

        // Refresh right away after waking, so the number isn't stale.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
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
            .applicationVersion: "1.0",
            .version: "",  // hides the "(1)" build number
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "by Mihailo Despotovic, 2026",
        ])
    }

    @objc private func toggleUnit() {
        showUnit.toggle()
        unitItem.state = showUnit ? .on : .off
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

    @objc private func pickOKColor(_ sender: NSMenuItem) {
        okUsesSystemColor = sender.tag == 1
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
        refresh()
    }

    @objc private func refresh() {
        guard let button = item.button else { return }
        let gb = freeGigabytes()
        let text = gb.map { showUnit ? "\($0)GB" : String($0) } ?? "–"
        let color: NSColor = switch gb {
        case nil: .labelColor
        case let gb? where gb < 10: .systemRed
        case let gb? where gb < 30: .systemOrange
        // Dark gold instead of .systemYellow, which is hard to read on a light menu bar.
        case let gb? where gb < 50: NSColor(srgbRed: 0xC9 / 255, green: 0x9A / 255, blue: 0, alpha: 1)
        default: okUsesSystemColor ? .labelColor : .systemGreen
        }
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize.points, weight: bold ? .heavy : .regular),
            .foregroundColor: color,
            .baselineOffset: fontSize.baselineOffset,
        ])
        button.toolTip = gb.map { "\($0) GB free" }
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
