import AppKit
import UniformTypeIdentifiers

/// The menu bar item. The menu is rebuilt each time it opens so it always
/// reflects the stored settings and the current frontmost app.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let remapper: KeyRemapper
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    init(remapper: KeyRemapper) {
        self.remapper = remapper
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.length = 24   // same slot width as SheepTap
        statusItem.button?.imagePosition = .imageOnly

        remapper.onStateChange = { [weak self] in
            self?.updateIcon()
        }
        updateIcon()
    }

    // MARK: Icon

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let filled = Preferences.isEnabled && remapper.isRemappingFrontmost
        button.image = NSImage.statusIcon(filled: filled)
        // Dim only when the user paused it; a missing permission is explained
        // in the menu instead, a faded icon just looks broken.
        button.alphaValue = Preferences.isEnabled ? 1 : 0.5
        button.toolTip = statusText
    }

    private var statusText: String {
        if !remapper.isTrusted {
            return "SheepKey needs Accessibility access"
        }
        if !Preferences.isEnabled {
            return "SheepKey is paused"
        }
        if remapper.isRemappingFrontmost,
           let id = remapper.frontmostBundleID,
           let app = Preferences.targets.first(where: { $0.bundleID == id }) {
            return "Remapping ⌘ in \(app.name)"
        }
        return "Waiting for a remote-desktop app"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !remapper.isTrusted {
            let grant = NSMenuItem(title: "Grant Accessibility Access…",
                                   action: #selector(grantAccess), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }
        if !ScreenCapture.hasPermission {
            let grant = NSMenuItem(title: "Grant Screen Recording (for screenshots)…",
                                   action: #selector(grantScreenRecording), keyEquivalent: "")
            grant.target = self
            grant.toolTip = "Screenshot shortcuts pressed inside a remote app are taken by SheepKey, which needs Screen Recording access."
            menu.addItem(grant)
        }
        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "Remap ⌘ in Remote Apps",
                                 action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = Preferences.isEnabled ? .on : .off
        menu.addItem(enabled)

        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in RemapMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = Preferences.mode == mode ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "Apps", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let targets = Preferences.targets
        for target in targets {
            let item = NSMenuItem(title: target.name, action: #selector(toggleTarget(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = target.bundleID
            item.state = target.isEnabled ? .on : .off
            item.indentationLevel = 1
            item.toolTip = target.bundleID
            if target.bundleID == remapper.frontmostBundleID {
                item.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Frontmost")?
                    .withSymbolConfiguration(.init(pointSize: 6, weight: .regular))
            }
            menu.addItem(item)
        }

        let add = NSMenuItem(title: "Add App…", action: #selector(addApp), keyEquivalent: "")
        add.target = self
        add.indentationLevel = 1
        menu.addItem(add)

        let running = runningCandidates(excluding: targets)
        if !running.isEmpty {
            let item = NSMenuItem(title: "Add Running App", action: nil, keyEquivalent: "")
            item.indentationLevel = 1
            let sub = NSMenu()
            for app in running {
                let entry = NSMenuItem(title: app.name, action: #selector(addRunningApp(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = [app.bundleID, app.name]
                sub.addItem(entry)
            }
            item.submenu = sub
            menu.addItem(item)
        }

        if !targets.isEmpty {
            let item = NSMenuItem(title: "Remove App", action: nil, keyEquivalent: "")
            item.indentationLevel = 1
            let sub = NSMenu()
            for target in targets {
                let entry = NSMenuItem(title: target.name, action: #selector(removeTarget(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = target.bundleID
                sub.addItem(entry)
            }
            item.submenu = sub
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let about = NSMenuItem(title: "SheepKey \(version) (\(build))", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit SheepKey", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// Regular (Dock-visible) apps running now that are not yet targets.
    private func runningCandidates(excluding targets: [TargetApp]) -> [(bundleID: String, name: String)] {
        let known = Set(targets.map(\.bundleID))
        let ownID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String)? in
                guard let id = app.bundleIdentifier, id != ownID, !known.contains(id),
                      let name = app.localizedName else { return nil }
                return (id, name)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    // MARK: Actions

    @objc private func grantAccess() {
        remapper.openAccessibilitySettings()
    }

    @objc private func grantScreenRecording() {
        ScreenCapture.requestPermission()
    }

    @objc private func toggleEnabled() {
        Preferences.isEnabled.toggle()
        remapper.reloadPreferences()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = RemapMode(rawValue: raw) else { return }
        Preferences.mode = mode
        remapper.reloadPreferences()
    }

    @objc private func toggleTarget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var targets = Preferences.targets
        guard let index = targets.firstIndex(where: { $0.bundleID == id }) else { return }
        targets[index].isEnabled.toggle()
        Preferences.targets = targets
        remapper.reloadPreferences()
    }

    @objc private func removeTarget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Preferences.targets.removeAll { $0.bundleID == id }
        remapper.reloadPreferences()
    }

    @objc private func addRunningApp(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        append(TargetApp(bundleID: pair[0], name: pair[1]))
    }

    @objc private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose a remote-desktop app"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier
        else { return }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        append(TargetApp(bundleID: id, name: name))
    }

    private func append(_ target: TargetApp) {
        var targets = Preferences.targets
        guard !targets.contains(where: { $0.bundleID == target.bundleID }) else { return }
        targets.append(target)
        Preferences.targets = targets
        remapper.reloadPreferences()
    }

    @objc private func toggleLoginItem() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }
}

private extension NSImage {
    /// The menu bar glyph: a keycap outline with ⌘ inside, drawn at the same
    /// 18-point canvas and 16.5-point outer size as SheepTap's ring so the
    /// two sit at equal height in the menu bar. `filled` inverts it (solid
    /// cap, ⌘ knocked out) while remapping is live.
    static func statusIcon(filled: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()

            let outer = rect.insetBy(dx: 0.75, dy: 0.75)   // outer 16.5, matches SheepTap
            let lineWidth: CGFloat = 2.5
            let cap = NSBezierPath(roundedRect: outer.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                                   xRadius: 3.6, yRadius: 3.6)
            cap.lineWidth = lineWidth
            if filled {
                NSBezierPath(roundedRect: outer, xRadius: 4.6, yRadius: 4.6).fill()
            } else {
                cap.stroke()
            }

            // ⌘ comes from the system font's own glyph (U+2318), centred on
            // its real outline. An SF Symbol image carries baseline padding
            // that pushed the glyph right and down inside the cap.
            if let glyphPath = NSImage.commandGlyphPath() {
                let bounds = glyphPath.boundingBoxOfPath
                let target: CGFloat = 8.2
                let scale = target / max(bounds.width, bounds.height)
                var transform = CGAffineTransform(translationX: rect.midX - bounds.midX * scale,
                                                  y: rect.midY - bounds.midY * scale)
                    .scaledBy(x: scale, y: scale)
                if let centred = glyphPath.copy(using: &transform) {
                    let glyph = NSBezierPath(cgPath: centred)
                    if filled {
                        NSGraphicsContext.current?.compositingOperation = .destinationOut
                        glyph.fill()
                        NSGraphicsContext.current?.compositingOperation = .sourceOver
                    } else {
                        glyph.fill()
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SheepKey"
        return image
    }

    /// Outline of ⌘ from the system font, in font units.
    static func commandGlyphPath() -> CGPath? {
        let font = NSFont.systemFont(ofSize: 100, weight: .heavy) as CTFont
        var character: UniChar = 0x2318
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) else { return nil }
        return CTFontCreatePathForGlyph(font, glyph, nil)
    }
}
