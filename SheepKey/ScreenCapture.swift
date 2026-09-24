import AppKit
import CoreGraphics

/// Takes the screenshot a swallowed hotkey asked for, using the system's
/// own `screencapture` tool so the result matches what macOS would have
/// produced: same folder, same file name pattern, same format.
///
/// Needs Screen Recording permission (TCC); without it `screencapture`
/// quietly returns the wallpaper with no windows, so the first attempt asks
/// for access instead of producing a useless image.
enum ScreenCapture {
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        if !CGRequestScreenCaptureAccess() {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }

    static func perform(_ action: SystemHotkeys.ScreenshotAction) {
        guard hasPermission else {
            requestPermission()
            return
        }
        var args: [String] = []
        switch action {
        case .saveScreen:                  args = [outputPath()]
        case .copyScreen:                  args = ["-c"]
        case .saveArea:                    args = ["-i", outputPath()]
        case .copyArea:                    args = ["-i", "-c"]
        case .options:                     args = ["-i", "-U"]
        case .saveTouchBar:                args = ["-b", outputPath()]
        case .copyTouchBar:                args = ["-b", "-c"]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-t", imageType()] + args
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
        } catch {
            NSLog("SheepKey: screencapture failed to launch: \(error)")
        }
    }

    // MARK: System screenshot preferences

    private static func preference(_ key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, "com.apple.screencapture" as CFString) as? String
    }

    private static func imageType() -> String {
        preference("type")?.lowercased() ?? "png"
    }

    /// "<location>/Screenshot YYYY-MM-DD at HH.MM.SS.<type>", the same
    /// shape macOS uses, in the folder chosen in the Screenshot options.
    private static func outputPath() -> String {
        var folder = preference("location").map { ($0 as NSString).expandingTildeInPath }
            ?? NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first
            ?? NSHomeDirectory()
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory) || !isDirectory.boolValue {
            folder = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first
                ?? NSHomeDirectory()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = (preference("name") ?? "Screenshot") + " " + formatter.string(from: Date())
        return (folder as NSString).appendingPathComponent("\(name).\(imageType())")
    }
}
