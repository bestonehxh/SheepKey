import Foundation
import ServiceManagement

/// "Open at Login" via `SMAppService`, following the family convention from
/// SheepTap: register once on the first launch from a stable location, then
/// leave the user's choice alone, but repair a registration that points at a
/// bundle path that no longer exists.
enum LoginItem {
    /// Set once, the first time the app ever launches from a stable location.
    /// Without it the app re-registered itself on every launch, so turning
    /// "Open at Login" off in System Settings was silently undone.
    private static let didConfigureKey = "SheepKey.didConfigureLoginItem"
    /// The bundle path the login item was registered from. The system keeps
    /// whatever path `register()` was called from, so if the app later moves
    /// (first run from DerivedData, then installed to /Applications) the item
    /// stays enabled but points at a bundle that no longer exists.
    private static let registeredPathKey = "SheepKey.registeredLoginItemPath"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: didConfigureKey)
        do {
            if enabled {
                try SMAppService.mainApp.register()
                defaults.set(Bundle.main.bundlePath, forKey: registeredPathKey)
            } else {
                try SMAppService.mainApp.unregister()
                defaults.removeObject(forKey: registeredPathKey)
            }
        } catch {
            NSLog("SheepKey: login item change failed: \(error)")
        }
    }

    static func configureOnFirstLaunch() {
        let defaults = UserDefaults.standard
        let bundlePath = Bundle.main.bundlePath
        // A registration made from a build directory or the Trash dies as
        // soon as that copy is cleaned out, so never register from there.
        let isStableLocation = !bundlePath.contains("/DerivedData/")
            && !bundlePath.contains("/.Trash/")

        guard defaults.bool(forKey: didConfigureKey) else {
            guard isStableLocation else { return }
            defaults.set(true, forKey: didConfigureKey)
            guard SMAppService.mainApp.status == .notRegistered else { return }
            if (try? SMAppService.mainApp.register()) != nil {
                defaults.set(bundlePath, forKey: registeredPathKey)
            }
            return
        }

        // Repair a registration left behind at an old location. Only while
        // the item is `.enabled`: `.notRegistered` means the user turned it
        // off, and that choice stays theirs.
        guard isStableLocation,
              SMAppService.mainApp.status == .enabled,
              defaults.string(forKey: registeredPathKey) != bundlePath
        else { return }

        try? SMAppService.mainApp.unregister()
        if (try? SMAppService.mainApp.register()) != nil {
            defaults.set(bundlePath, forKey: registeredPathKey)
        }
    }
}
