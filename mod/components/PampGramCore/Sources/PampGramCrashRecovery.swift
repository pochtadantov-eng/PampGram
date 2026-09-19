import Foundation

/// Detects crash-on-startup loops and clears Telegram's navigation state so
/// the app starts from the chat list rather than the chat that caused the crash.
///
/// How it works:
///   - AppDelegate sets the flag to `false` (= "startup in progress") at the very
///     start of didFinishLaunchingWithOptions.
///   - AppDelegate sets it to `true` (= "clean") in applicationDidBecomeActive,
///     which only fires after the UI is fully up and no crash has happened.
///   - On the NEXT launch, if the flag is still `false` the previous launch crashed.
///     In that case `onWillLaunch()` clears Telegram's navigation state files and
///     returns true so the caller can show a recovery notice if desired.
public enum PampGramCrashRecovery {

    static let startupKey = "pampgram_startup_completed"

    /// Call this at the very beginning of `application(_:didFinishLaunchingWithOptions:)`,
    /// before any TelegramUI setup. Returns `true` when a crash was detected and recovery
    /// actions were performed (navigation state cleared).
    @discardableResult
    public static func onWillLaunch() -> Bool {
        let hadRecord = UserDefaults.standard.object(forKey: startupKey) != nil
        let wasClean = UserDefaults.standard.bool(forKey: startupKey)
        // Mark this launch as in-progress (crash = flag stays false on next boot)
        UserDefaults.standard.set(false, forKey: startupKey)
        UserDefaults.standard.synchronize()

        let crashed = hadRecord && !wasClean
        if crashed {
            clearNavigationState()
        }
        return crashed
    }

    /// Call from `applicationDidBecomeActive` — the UI is up, no crash happened.
    public static func onBecameActive() {
        UserDefaults.standard.set(true, forKey: startupKey)
        UserDefaults.standard.synchronize()
    }

    // MARK: - Navigation state cleanup

    private static func clearNavigationState() {
        let fm = FileManager.default
        var candidates: [URL] = []

        for dir in [
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fm.urls(for: .documentDirectory, in: .userDomainMask).first,
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
        ].compactMap({ $0 }) {
            // Telegram stores navigation state in files whose names contain "navigation"
            // under the app's data directories. Deleting them is safe: Telegram
            // re-creates them on the next launch, starting from the chat list.
            addNavigationFiles(in: dir, to: &candidates, fm: fm, depth: 3)
        }

        for url in candidates {
            try? fm.removeItem(at: url)
        }
    }

    private static func addNavigationFiles(in dir: URL, to list: inout [URL], fm: FileManager, depth: Int) {
        guard depth > 0,
              let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        else { return }

        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                addNavigationFiles(in: item, to: &list, fm: fm, depth: depth - 1)
            } else {
                let name = item.lastPathComponent.lowercased()
                if name.contains("navigation") {
                    list.append(item)
                }
            }
        }
    }
}
