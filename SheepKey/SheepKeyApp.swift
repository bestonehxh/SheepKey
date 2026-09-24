import SwiftUI
import AppKit

@main
struct SheepKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let remapper = KeyRemapper()
    private var statusController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LoginItem.configureOnFirstLaunch()
        statusController = StatusMenuController(remapper: remapper)
        remapper.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        remapper.stop()
    }
}
