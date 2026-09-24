import AppKit
import ApplicationServices
import CoreGraphics

/// Rewrites ⌘/⌃ on keyboard events while a target app is frontmost.
///
/// A session-level `CGEventTap` sees every key event before the frontmost
/// app does. When that app is one of the configured remote-desktop clients,
/// the modifier flags on key events are rewritten, and the modifier keys
/// themselves (the `flagsChanged` events) are swapped so the remote client
/// forwards a Ctrl press, not a Win press, to the Windows side.
///
/// Everything here runs on the main thread: the tap's run-loop source lives
/// on the main run loop, so the C callback is entered on the main thread and
/// hops back into the actor with `assumeIsolated`.
final class KeyRemapper {
    /// Called after anything the menu displays may have changed.
    var onStateChange: (() -> Void)?

    private(set) var isTrusted = false
    private(set) var frontmostBundleID: String?
    private var frontmostPID: pid_t = 0

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trustPoll: Timer?
    private var activationObserver: NSObjectProtocol?

    /// Snapshot of the settings the hot path reads, refreshed from
    /// `Preferences` whenever something changes rather than decoded per event.
    private var isEnabled = Preferences.isEnabled
    private var mode = Preferences.mode
    private var activeBundleIDs = Set(
        Preferences.targets.filter(\.isEnabled).map(\.bundleID)
    )
    /// Cached per activation change so the per-keystroke path is a bool test.
    private var frontmostIsTarget = false
    /// Chords handed to macOS untouched (app switcher, Spotlight, …).
    private var passthroughChords = SystemHotkeys.alwaysPassthrough
    /// Screenshot chords, re-read from the system each time a target comes
    /// to the front so a shortcut changed in System Settings is picked up.
    /// Remote-desktop clients grab these before macOS can (AnyDesk swallows
    /// ⌃⌥⌘4 even with SheepKey quit), so inside a target the chord is
    /// swallowed here and the capture is taken by SheepKey itself.
    private var screenshotChords = SystemHotkeys.screenshotChords()
    /// Runs a screenshot action; replaceable so tests do not take pictures.
    var captureHandler: (SystemHotkeys.ScreenshotAction) -> Void = { ScreenCapture.perform($0) }
    /// Chord whose keyDown was swallowed; its keyUp is swallowed as well.
    private var swallowedChord: SystemHotkeys.Chord?

    /// Rewritten modifier keys the target app currently believes are held
    /// (by rewritten key code). If the user leaves the app with one of them
    /// down (⌘-Tab does exactly that), the app never sees the release, and
    /// the Windows side is stuck with Ctrl held. On deactivation those keys
    /// are released explicitly.
    private var heldRewrittenKeys: Set<Int64> = []

    /// True while remapping actually applies to keystrokes right now.
    var isRemappingFrontmost: Bool {
        isEnabled && isTrusted && tap != nil && frontmostIsTarget
    }

    // MARK: Lifecycle

    func start() {
        if let app = NSWorkspace.shared.frontmostApplication {
            setFrontmost(bundleID: app.bundleIdentifier, pid: app.processIdentifier)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let pid = app?.processIdentifier ?? 0
            MainActor.assumeIsolated {
                self?.setFrontmost(bundleID: bundleID, pid: pid)
                self?.onStateChange?()
            }
        }
        checkTrust(prompt: true)
    }

    func stop() {
        trustPoll?.invalidate()
        trustPoll = nil
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        releaseHeldKeys()
        tearDownTap()
    }

    /// Re-read settings after the menu changed them.
    func reloadPreferences() {
        isEnabled = Preferences.isEnabled
        mode = Preferences.mode
        activeBundleIDs = Set(Preferences.targets.filter(\.isEnabled).map(\.bundleID))
        frontmostIsTarget = frontmostBundleID.map(activeBundleIDs.contains) ?? false
        if !isRemappingFrontmost { releaseHeldKeys() }
        onStateChange?()
    }

    /// Records which app is in front. Internal so tests can drive it.
    func setFrontmost(bundleID: String?, pid: pid_t) {
        let wasTarget = frontmostIsTarget
        if wasTarget, bundleID != frontmostBundleID {
            releaseHeldKeys()
        }
        frontmostBundleID = bundleID
        frontmostPID = pid
        frontmostIsTarget = bundleID.map(activeBundleIDs.contains) ?? false
        if frontmostIsTarget, !wasTarget {
            screenshotChords = SystemHotkeys.screenshotChords()
        }
    }

    /// Test hooks: replace the system-owned chords.
    func setPassthroughChords(_ chords: Set<SystemHotkeys.Chord>) {
        passthroughChords = chords
    }

    func setScreenshotChords(_ chords: [SystemHotkeys.Chord: SystemHotkeys.ScreenshotAction]) {
        screenshotChords = chords
    }

    // MARK: Accessibility trust

    /// Asks macOS whether the app may observe keystrokes. With `prompt` the
    /// system shows its own "SheepKey would like to control this computer"
    /// dialog once. Until trust is granted the tap cannot be created, so this
    /// keeps polling: the user grants access in System Settings while the app
    /// is running, and nothing tells the app when that happens.
    func checkTrust(prompt: Bool) {
        // The literal key stands in for `kAXTrustedCheckOptionPrompt`, a global
        // C var that Swift 6 refuses to read from an actor.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        let wasTrusted = isTrusted
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if isTrusted != wasTrusted || prompt {
            NSLog("SheepKey: accessibility trusted = %@", isTrusted ? "yes" : "no")
        }
        if isTrusted {
            installTap()
        }
        // Mirrored into defaults so `defaults read Bestchaan.SheepKey` can
        // answer "is it working?" without opening the menu.
        UserDefaults.standard.set(isTrusted, forKey: "SheepKey.state.trusted")
        UserDefaults.standard.set(tap != nil, forKey: "SheepKey.state.tapInstalled")
        if tap != nil {
            trustPoll?.invalidate()
            trustPoll = nil
        } else if trustPoll == nil {
            trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkTrust(prompt: false) }
            }
        }
        onStateChange?()
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Event tap

    private func installTap() {
        guard tap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: KeyRemapper.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Trust was reported but the tap was refused (typically a stale
            // TCC grant for a previous build). The caller keeps polling.
            NSLog("SheepKey: event tap refused despite accessibility trust")
            isTrusted = false
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        NSLog("SheepKey: event tap installed")
    }

    private func tearDownTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    /// The C entry point. It cannot capture anything, so `self` travels
    /// through `userInfo`. The event is rewritten in place and always passed
    /// on; nothing is ever swallowed.
    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        if let userInfo {
            let remapper = Unmanaged<KeyRemapper>.fromOpaque(userInfo).takeUnretainedValue()
            // The tap fires on the main run loop, so this is the main thread;
            // the box only satisfies the compiler's sending check.
            let box = EventBox(event: event)
            let pass = MainActor.assumeIsolated {
                remapper.handle(type: type, event: box.event)
            }
            if !pass { return nil }
        }
        return Unmanaged.passUnretained(event)
    }

    private struct EventBox: @unchecked Sendable {
        let event: CGEvent
    }

    /// Rewrites one event in place. Returns false when the event must be
    /// dropped instead of delivered. Internal so tests can feed it synthetic
    /// events without a tap.
    @discardableResult
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches a tap off if a callback runs too long or the
            // user asks it to; switch it straight back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        case .keyDown, .keyUp, .flagsChanged:
            break
        default:
            return true
        }

        guard isEnabled, frontmostIsTarget else { return true }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if type != .flagsChanged {
            let chord = SystemHotkeys.Chord(keyCode: keyCode,
                                            modifiers: flags.rawValue & SystemHotkeys.modifierMask)

            // Screenshot shortcut: never let the remote app see it. Take the
            // capture here (first press only, not key repeat) and drop both
            // the keyDown and the matching keyUp.
            if let action = screenshotChords[chord] {
                if type == .keyDown {
                    if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                        captureHandler(action)
                    }
                    swallowedChord = chord
                }
                return false
            }
            if type == .keyUp, swallowedChord?.keyCode == keyCode {
                swallowedChord = nil
                return false
            }

            // Shortcuts macOS itself owns (⌘-Tab, ⌘-Space, ⌘-`) go through
            // untouched so the window server can act on them.
            if passthroughChords.contains(chord) {
                return true
            }
        }

        event.flags = rewrite(flags: flags)

        if type == .flagsChanged, let replacement = rewrite(modifierKeyCode: keyCode) {
            event.setIntegerValueField(.keyboardEventKeycode, value: replacement)
            // A modifier's flagsChanged carries its new state in the flags.
            let isDown = flags.contains(Self.mask(forModifierKeyCode: keyCode))
            if isDown {
                heldRewrittenKeys.insert(replacement)
            } else {
                heldRewrittenKeys.remove(replacement)
            }
        }
        return true
    }

    /// Sends the release for every rewritten modifier the target app still
    /// thinks is down, straight to that process.
    private func releaseHeldKeys() {
        guard !heldRewrittenKeys.isEmpty else { return }
        let keys = heldRewrittenKeys
        heldRewrittenKeys = []
        guard frontmostPID > 0 else { return }
        for keyCode in keys {
            guard let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false) else { continue }
            up.type = .flagsChanged
            up.flags = []
            up.postToPid(frontmostPID)
        }
    }

    // MARK: Rewriting

    static let leftCommand: Int64 = 55
    static let rightCommand: Int64 = 54
    static let leftControl: Int64 = 59
    static let rightControl: Int64 = 62

    // Device-specific modifier bits (NX_DEVICE*KEYMASK). Apps that care which
    // side was pressed read these, so they move along with the generic bits.
    static let deviceLeftControl: UInt64 = 0x0000_0001
    static let deviceLeftCommand: UInt64 = 0x0000_0008
    static let deviceRightCommand: UInt64 = 0x0000_0010
    static let deviceRightControl: UInt64 = 0x0000_2000

    private static func mask(forModifierKeyCode keyCode: Int64) -> CGEventFlags {
        switch keyCode {
        case leftCommand, rightCommand: .maskCommand
        case leftControl, rightControl: .maskControl
        default: []
        }
    }

    func rewrite(flags: CGEventFlags) -> CGEventFlags {
        let hadCommand = flags.contains(.maskCommand)
        let hadControl = flags.contains(.maskControl)
        guard hadCommand || hadControl else { return flags }
        var raw = flags.rawValue

        let commandBits = CGEventFlags.maskCommand.rawValue | Self.deviceLeftCommand | Self.deviceRightCommand
        let controlBits = CGEventFlags.maskControl.rawValue | Self.deviceLeftControl | Self.deviceRightControl
        let hadLeftCommand = raw & Self.deviceLeftCommand != 0
        let hadRightCommand = raw & Self.deviceRightCommand != 0
        let hadLeftControl = raw & Self.deviceLeftControl != 0
        let hadRightControl = raw & Self.deviceRightControl != 0

        switch mode {
        case .swap:
            raw &= ~(commandBits | controlBits)
            if hadCommand {
                raw |= CGEventFlags.maskControl.rawValue
                if hadLeftCommand { raw |= Self.deviceLeftControl }
                if hadRightCommand { raw |= Self.deviceRightControl }
            }
            if hadControl {
                raw |= CGEventFlags.maskCommand.rawValue
                if hadLeftControl { raw |= Self.deviceLeftCommand }
                if hadRightControl { raw |= Self.deviceRightCommand }
            }
        case .commandAsControl:
            guard hadCommand else { return flags }
            raw &= ~commandBits
            raw |= CGEventFlags.maskControl.rawValue
            if hadLeftCommand { raw |= Self.deviceLeftControl }
            if hadRightCommand { raw |= Self.deviceRightControl }
        }
        return CGEventFlags(rawValue: raw)
    }

    func rewrite(modifierKeyCode keyCode: Int64) -> Int64? {
        switch (mode, keyCode) {
        case (_, Self.leftCommand):       Self.leftControl
        case (_, Self.rightCommand):      Self.rightControl
        case (.swap, Self.leftControl):   Self.leftCommand
        case (.swap, Self.rightControl):  Self.rightCommand
        default:                          nil
        }
    }
}
