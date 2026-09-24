import Foundation
import CoreGraphics

/// The key chords macOS itself owns and must keep receiving untouched while a
/// remote app is frontmost. Screenshot shortcuts are read from the user's
/// own assignments (System Settings → Keyboard → Shortcuts → Screenshots)
/// rather than assumed, so a custom ⌥⌘4 is honoured just like the stock ⇧⌘4.
enum SystemHotkeys {
    /// A key plus the modifiers that matter, in `CGEventFlags` raw bits.
    struct Chord: Hashable {
        let keyCode: Int64
        let modifiers: UInt64
    }

    static let modifierMask: UInt64 =
        CGEventFlags.maskShift.rawValue
        | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskSecondaryFn.rawValue

    /// What each Screenshots hotkey does, keyed by AppleSymbolicHotKeys id.
    enum ScreenshotAction: Equatable {
        case saveScreen, copyScreen, saveArea, copyArea, options, saveTouchBar, copyTouchBar
    }

    private static let screenshotActions: [Int: ScreenshotAction] = [
        28: .saveScreen, 29: .copyScreen, 30: .saveArea, 31: .copyArea,
        184: .options, 181: .saveTouchBar, 182: .copyTouchBar,
    ]
    /// Factory chords for ids the plist carries no entry for.
    private static let screenshotDefaults: [Int: Chord] = [
        28: Chord(keyCode: 20, modifiers: 0x12_0000),   // ⇧⌘3  save screen
        29: Chord(keyCode: 20, modifiers: 0x16_0000),   // ⌃⇧⌘3 copy screen
        30: Chord(keyCode: 21, modifiers: 0x12_0000),   // ⇧⌘4  save area
        31: Chord(keyCode: 21, modifiers: 0x16_0000),   // ⌃⇧⌘4 copy area
        184: Chord(keyCode: 23, modifiers: 0x12_0000),  // ⇧⌘5  screenshot options
    ]

    /// Chords that are always the system's: ⌘-Tab / ⌘-Space / ⌘-` reach the
    /// app switcher, Spotlight and window cycling.
    static let alwaysPassthrough: Set<Chord> = [
        Chord(keyCode: 48, modifiers: CGEventFlags.maskCommand.rawValue),
        Chord(keyCode: 48, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue),
        Chord(keyCode: 49, modifiers: CGEventFlags.maskCommand.rawValue),
        Chord(keyCode: 50, modifiers: CGEventFlags.maskCommand.rawValue),
        Chord(keyCode: 50, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue),
    ]

    /// Screenshot chords as currently assigned on this Mac, with what each does.
    static func screenshotChords() -> [Chord: ScreenshotAction] {
        var chords: [Chord: ScreenshotAction] = [:]
        var seen = Set<Int>()
        let raw = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                            "com.apple.symbolichotkeys" as CFString)
        if let table = raw as? [String: Any] {
            for (key, value) in table {
                guard let id = Int(key),
                      let action = screenshotActions[id],
                      let entry = value as? [String: Any]
                else { continue }
                seen.insert(id)
                let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? true
                guard enabled,
                      let params = (entry["value"] as? [String: Any])?["parameters"] as? [Any],
                      params.count >= 3,
                      let keyCode = (params[1] as? NSNumber)?.int64Value,
                      let modifiers = (params[2] as? NSNumber)?.uint64Value,
                      keyCode >= 0, keyCode < 0xFFFF
                else { continue }
                chords[Chord(keyCode: keyCode, modifiers: modifiers & modifierMask)] = action
            }
        }
        for (id, chord) in screenshotDefaults where !seen.contains(id) {
            chords[chord] = screenshotActions[id]
        }
        return chords
    }
}
