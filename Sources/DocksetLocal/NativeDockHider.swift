import Foundation

/// Hides Apple's Dock while the custom bar replaces it, using an auto-hide delay so long it
/// never shows, and puts the user's own settings back afterwards.
enum NativeDockHider {
    private static let domain = "com.apple.dock" as CFString
    private static let keys = ["autohide", "autohide-delay"]

    /// The backup's presence means "hidden by us", so after a crash the next launch or
    /// turning the option off still restores the original settings.
    static func backupURL(in directory: URL) -> URL {
        directory.appendingPathComponent("native-dock-before-hiding.plist")
    }

    static func setHidden(_ hidden: Bool, dataDirectory: URL) {
        let backup = backupURL(in: dataDirectory)
        guard hidden != FileManager.default.fileExists(atPath: backup.path) else { return }
        CFPreferencesAppSynchronize(domain)
        if hidden {
            var saved: [String: Any] = [:]
            for key in keys { saved[key] = CFPreferencesCopyAppValue(key as CFString, domain) }
            guard (try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)) != nil,
                  let data = try? PropertyListSerialization.data(fromPropertyList: saved, format: .binary, options: 0),
                  (try? data.write(to: backup, options: .atomic)) != nil else { return }
            set(["autohide": true, "autohide-delay": 1000.0])
        } else {
            let saved = (try? Data(contentsOf: backup))
                .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
            set(saved)
            try? FileManager.default.removeItem(at: backup)
        }
    }

    /// Missing keys are deleted so the Dock falls back to Apple's defaults, as before hiding.
    private static func set(_ values: [String: Any]) {
        for key in keys { CFPreferencesSetAppValue(key as CFString, values[key] as CFPropertyList?, domain) }
        CFPreferencesAppSynchronize(domain)
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
    }
}
