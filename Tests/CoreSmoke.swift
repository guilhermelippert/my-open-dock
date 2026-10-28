import Foundation

private struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct CoreSmoke {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DocksetLocal-Smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceDirectory = directory.appendingPathComponent("source", isDirectory: true)
        let restoredDirectory = directory.appendingPathComponent("restored", isDirectory: true)
        var widgetTestKeys: [String] = []
        defer { for key in widgetTestKeys { UserDefaults.standard.removeObject(forKey: key) } }
        let store = DockStore(dataDirectory: sourceDirectory)
        try check(store.profiles.count == 3, "Expected three starter profiles")
        try check(store.lastError == nil, "First launch failed: \(store.lastError ?? "")")
        try check(store.currentProfile?.name == "Trabalho", "Expected work as the first profile")
        try check(!store.hasOriginalNativeDock, "First launch must not alter the native Dock")
        for item in store.profiles.flatMap(\.items) where item.kind == .app {
            try check(FileManager.default.fileExists(atPath: item.target), "Seeded app does not exist")
        }

        store.createProfile(name: "  Teste  ")
        let testID = store.selectedProfileID
        try check(store.currentProfile?.name == "Teste", "Profile name was not trimmed")
        store.addLink(name: "Documentação", url: "developer.apple.com")
        store.addWidget(.clock)
        store.addSpacer()
        store.addShortcut(name: "Meu atalho")
        try check(store.currentProfile?.items.count == 4, "Item creation failed")
        let link = try require(store.currentProfile?.items.first, "Missing link")
        try check(link.target == "https://developer.apple.com", "URL normalization failed")
        store.moveItem(link.id, offset: 2)
        try check(store.currentProfile?.items[2].id == link.id, "Item reordering failed")
        var edited = link
        edited.name = "Apple"
        store.updateItem(edited)
        try check(store.currentProfile?.items[2].name == "Apple", "Item editing failed")
        store.removeItem(link.id)
        try check(store.currentProfile?.items.count == 3, "Item removal failed")
        store.preferences.iconSize = 60
        store.preferences.edge = .right
        store.preferences.showDock = false
        store.preferences.dockScale = 1.25
        store.preferences.revealDuration = 0

        let reloaded = DockStore(dataDirectory: sourceDirectory)
        try check(reloaded.selectedProfileID == testID, "Selected profile did not persist")
        try check(reloaded.currentProfile?.items == store.currentProfile?.items, "Items did not persist")
        try check(reloaded.preferences.iconSize == 60 && reloaded.preferences.edge == .right, "Preferences did not persist")
        try check(reloaded.preferences.dockScale == 1.25 && !reloaded.preferences.showDock, "Scale did not persist or re-enabled the Dock")
        try check(reloaded.preferences.revealDuration == 0, "Instant reveal did not persist")

        store.duplicateProfile(testID)
        let copy = try require(store.currentProfile, "Missing duplicated profile")
        let original = try require(store.profiles.first(where: { $0.id == testID }), "Missing original profile")
        try check(copy.id != original.id && copy.items.count == original.items.count, "Profile duplication failed")
        try check(Set(copy.items.map(\.id)).isDisjoint(with: original.items.map(\.id)), "Duplicated item IDs were reused")
        store.deleteProfile(copy.id)
        try check(store.profiles.contains(where: { $0.id == store.selectedProfileID }), "Deleting selected profile left invalid selection")

        store.saveNativeLayout(name: "Snapshot somente leitura")
        try check(store.nativeLayouts.count == 1 && store.lastError == nil, "Native Dock snapshot failed")
        try check(!store.hasOriginalNativeDock, "Saving a snapshot must not apply it")
        let widget = try require(store.profiles.flatMap(\.items).first(where: { $0.kind == .widget }), "Missing test widget")
        let widgetPrefix = "DocksetLocal.widget.\(widget.id.uuidString)."
        let widgetValues: [String: Any] = ["note": "Minha nota de teste", "city": "Asia/Tokyo", "waterCount": 4, "waterDay": "2026-10-27"]
        for (suffix, value) in widgetValues {
            widgetTestKeys.append(widgetPrefix + suffix)
            UserDefaults.standard.set(value, forKey: widgetPrefix + suffix)
        }
        let backup = directory.appendingPathComponent("backup.json")
        try store.exportState(to: backup)
        let restored = DockStore(dataDirectory: restoredDirectory)
        UserDefaults.standard.set("Alterado depois do backup", forKey: widgetPrefix + "note")
        UserDefaults.standard.set(99, forKey: widgetPrefix + "waterCount")
        var importsNotified = 0
        let importObserver = NotificationCenter.default.addObserver(forName: Notification.Name("DocksetLocal.widgetsImported"), object: nil, queue: nil) { _ in importsNotified += 1 }
        defer { NotificationCenter.default.removeObserver(importObserver) }
        try restored.importState(from: backup)
        try check(restored.profiles == store.profiles, "Import and export did not roundtrip")
        try check(restored.preferences == store.preferences, "Imported preferences differ")
        try check(restored.nativeLayouts.first?.payload == store.nativeLayouts.first?.payload, "Native layout snapshot did not roundtrip")
        try check(UserDefaults.standard.string(forKey: widgetPrefix + "note") == "Minha nota de teste", "Widget note did not restore")
        try check(UserDefaults.standard.string(forKey: widgetPrefix + "city") == "Asia/Tokyo", "Widget timezone did not restore")
        try check(UserDefaults.standard.integer(forKey: widgetPrefix + "waterCount") == 4, "Widget hydration did not restore")
        try check(UserDefaults.standard.string(forKey: widgetPrefix + "waterDay") == "2026-10-27", "Widget hydration date did not restore")
        try check(importsNotified == 1, "Widget import did not notify live views")
        let priorProfiles = restored.profiles
        var invalid = try require(JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as? [String: Any], "Invalid backup JSON")
        invalid["selectedProfileID"] = UUID().uuidString
        let invalidURL = directory.appendingPathComponent("invalid.json")
        try JSONSerialization.data(withJSONObject: invalid).write(to: invalidURL)
        do {
            try restored.importState(from: invalidURL)
            throw SmokeFailure(description: "Malformed import was accepted")
        } catch is DockStoreError {}
        try check(restored.profiles == priorProfiles, "Rejected import changed existing profiles")
        try check(DockStore(dataDirectory: restoredDirectory).profiles == priorProfiles, "Rejected import changed saved profiles")

        var invalidWidget = try require(JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as? [String: Any], "Invalid widget backup")
        let unknownPreferences = try PropertyListSerialization.data(fromPropertyList: ["unrelated.secret": "must not import"], format: .binary, options: 0)
        invalidWidget["widgetPreferences"] = unknownPreferences.base64EncodedString()
        try JSONSerialization.data(withJSONObject: invalidWidget).write(to: invalidURL)
        do {
            try restored.importState(from: invalidURL)
            throw SmokeFailure(description: "Unknown widget preference was accepted")
        } catch is DockStoreError {}
        try check(UserDefaults.standard.object(forKey: "unrelated.secret") == nil, "Import wrote an unrelated preference")
        try check(UserDefaults.standard.string(forKey: widgetPrefix + "note") == "Minha nota de teste", "Rejected widget preferences changed state")

        var legacy = try require(JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as? [String: Any], "Invalid legacy backup")
        legacy.removeValue(forKey: "widgetPreferences")
        var legacyPreferences = try require(legacy["preferences"] as? [String: Any], "Missing legacy preferences")
        legacyPreferences.removeValue(forKey: "dockScale")
        legacyPreferences.removeValue(forKey: "revealDuration")
        legacy["preferences"] = legacyPreferences
        let legacyURL = directory.appendingPathComponent("legacy.json")
        try JSONSerialization.data(withJSONObject: legacy).write(to: legacyURL)
        UserDefaults.standard.set("Valor local em backup antigo", forKey: widgetPrefix + "note")
        try restored.importState(from: legacyURL)
        try check(UserDefaults.standard.string(forKey: widgetPrefix + "note") == "Valor local em backup antigo", "Legacy import must preserve local widget values")
        try check(restored.preferences.dockScale == 1 && !restored.preferences.showDock, "Legacy scale migration changed the disabled Dock")
        try check(restored.preferences.revealDuration == 0.2, "Legacy backup must get the default reveal animation")

        try testCorruptRecovery(directory: directory, validBackup: backup)
        try testLimits(directory: directory, validBackup: backup)
        try testLocalRestorePoint(directory: directory, validBackup: backup)
        try testScaleValidation(directory: directory, validBackup: backup)
        try testNativeDockMatching(directory: directory)

        for profile in restored.profiles.dropFirst() { restored.deleteProfile(profile.id) }
        if let last = restored.profiles.first { restored.deleteProfile(last.id) }
        try check(restored.profiles.count == 1 && restored.currentProfile != nil, "Deleting final profile must leave one usable profile")
        restored.cycleProfile(-1)
        restored.cycleProfile(1)
        try check(restored.currentProfile != nil, "Profile cycle lost selection")
        print("PASS: profile/item management, persistence, widget backup, corrupt recovery, mutation limits, machine-local restore point, scale validation and native Dock matching. Native Dock unchanged.")
    }

    @MainActor
    private static func testCorruptRecovery(directory: URL, validBackup: URL) throws {
        let fm = FileManager.default
        let corruptDirectory = directory.appendingPathComponent("corrupt", isDirectory: true)
        try fm.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        let stateURL = corruptDirectory.appendingPathComponent("state.json")
        let corruptData = Data("not valid JSON".utf8)
        try corruptData.write(to: stateURL)
        let recovered = DockStore(dataDirectory: corruptDirectory)
        try check(recovered.lastError != nil, "Corrupt state must report recovery")
        let recoveryFile = try require(fm.contentsOfDirectory(at: corruptDirectory, includingPropertiesForKeys: nil).first(where: { $0.lastPathComponent.hasPrefix("state-recovery-") }), "Corrupt state was not copied")
        try check(try Data(contentsOf: recoveryFile) == corruptData, "Recovery copy differs from corrupt original")
        recovered.createProfile(name: "Após recuperar")
        try check(try Data(contentsOf: recoveryFile) == corruptData, "Editing overwrote corrupt recovery copy")
        try check(DockStore(dataDirectory: corruptDirectory).profiles.count == 4, "Recovered state did not remain writable")

        let blockedDirectory = directory.appendingPathComponent("blocked", isDirectory: true)
        try fm.createDirectory(at: blockedDirectory, withIntermediateDirectories: true)
        let blockedURL = blockedDirectory.appendingPathComponent("state.json")
        try corruptData.write(to: blockedURL)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: blockedDirectory.path)
        let blocked = DockStore(dataDirectory: blockedDirectory)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blockedDirectory.path)
        blocked.createProfile(name: "Não deve sobrescrever")
        try check(try Data(contentsOf: blockedURL) == corruptData, "Failed backup allowed later persistence")
        do {
            try blocked.importState(from: validBackup)
            throw SmokeFailure(description: "Failed recovery allowed import to overwrite original")
        } catch is DockStoreError {}
        try check(try Data(contentsOf: blockedURL) == corruptData, "Blocked import overwrote original")
    }

    @MainActor
    private static func testLimits(directory: URL, validBackup: URL) throws {
        var fixture = try require(JSONSerialization.jsonObject(with: Data(contentsOf: validBackup)) as? [String: Any], "Invalid limits fixture")
        let firstID = UUID()
        var profiles: [[String: Any]] = (0..<99).map { index in
            ["id": index == 0 ? firstID.uuidString : UUID().uuidString, "name": "Perfil \(index)", "symbol": "square", "items": []]
        }
        profiles[0]["items"] = (0..<499).map { _ in ["id": UUID().uuidString, "name": "Espaço", "kind": "spacer", "target": ""] }
        profiles[0]["name"] = String(repeating: "N", count: 120)
        fixture["profiles"] = profiles
        fixture["selectedProfileID"] = firstID.uuidString
        fixture.removeValue(forKey: "widgetPreferences")
        let fixtureURL = directory.appendingPathComponent("limits.json")
        try JSONSerialization.data(withJSONObject: fixture).write(to: fixtureURL)
        let store = DockStore(dataDirectory: directory.appendingPathComponent("limits-store", isDirectory: true))
        try store.importState(from: fixtureURL)
        store.duplicateProfile(firstID)
        try check(store.profiles.count == 100 && store.currentProfile?.name.count == 120, "Duplicated long name exceeded profile limit")
        let selection = store.selectedProfileID
        store.createProfile(name: "Perfil excedente")
        store.duplicateProfile(firstID)
        try check(store.profiles.count == 100 && store.selectedProfileID == selection, "Profile cap was not enforced")
        try check(store.lastError != nil, "Profile cap must report the limit")
        store.selectProfile(firstID)
        let fileA = directory.appendingPathComponent("a.txt")
        let fileB = directory.appendingPathComponent("b.txt")
        try Data().write(to: fileA)
        try Data().write(to: fileB)
        let pinning = DockStore(dataDirectory: directory.appendingPathComponent("pin-store", isDirectory: true))
        pinning.createProfile(name: "Fixar app aberto")
        pinning.addItems([directory])
        pinning.addItems([URL(fileURLWithPath: "/System/Applications/Calculator.app")])
        try check(pinning.currentProfile?.items.map(\.kind) == [.app, .folder], "Kept app must join the apps before folders")
        store.addItems([fileA, fileB])
        try check(store.currentProfile?.items.count == 500, "Batch add exceeded item cap")
        store.addSpacer()
        store.addWidget(.clock)
        store.addLink(name: "Extra", url: "https://example.com")
        try check(store.currentProfile?.items.count == 500, "Single-item append exceeded cap")
        var item = try require(store.currentProfile?.items.last, "Missing limit test item")
        let savedItem = item
        item.target = "relative/path"
        store.updateItem(item)
        try check(store.currentProfile?.items.last == savedItem, "Invalid item update was persisted")
        let reloaded = DockStore(dataDirectory: store.dataDirectory)
        try check(reloaded.profiles.count == 100 && reloaded.currentProfile?.items.count == 500 && reloaded.lastError == nil, "Boundary state became unreloadable")
    }

    @MainActor
    private static func testLocalRestorePoint(directory: URL, validBackup: URL) throws {
        let originalJSON = try require(JSONSerialization.jsonObject(with: Data(contentsOf: validBackup)) as? [String: Any], "Invalid restore fixture")
        var foreign = originalJSON
        let layouts = try require(foreign["nativeLayouts"] as? [[String: Any]], "Missing native layout fixtures")
        let foreignPayload = try require(layouts.first?["payload"] as? String, "Missing foreign restore payload")
        foreign["originalNativeDock"] = foreignPayload
        let foreignURL = directory.appendingPathComponent("foreign.json")
        try JSONSerialization.data(withJSONObject: foreign).write(to: foreignURL)
        let targetDirectory = directory.appendingPathComponent("restore-point", isDirectory: true)
        let clean = DockStore(dataDirectory: targetDirectory)
        try clean.importState(from: foreignURL)
        try check(!clean.hasOriginalNativeDock, "Import adopted another Mac's original Dock")

        let localPayload = try PropertyListSerialization.data(fromPropertyList: ["persistent-apps": [], "persistent-others": []], format: .binary, options: 0)
        var local = originalJSON
        local["originalNativeDock"] = localPayload.base64EncodedString()
        try JSONSerialization.data(withJSONObject: local).write(to: targetDirectory.appendingPathComponent("state.json"))
        let withLocalPoint = DockStore(dataDirectory: targetDirectory)
        try check(withLocalPoint.hasOriginalNativeDock, "Local restore point did not load")
        try withLocalPoint.importState(from: foreignURL)
        let exportedURL = directory.appendingPathComponent("local-preserved.json")
        try withLocalPoint.exportState(to: exportedURL)
        let exported = try require(JSONSerialization.jsonObject(with: Data(contentsOf: exportedURL)) as? [String: Any], "Invalid preserved restore export")
        try check(exported["originalNativeDock"] as? String == localPayload.base64EncodedString(), "Import replaced this Mac's restore point")
    }

    @MainActor
    private static func testScaleValidation(directory: URL, validBackup: URL) throws {
        var fixture = try require(JSONSerialization.jsonObject(with: Data(contentsOf: validBackup)) as? [String: Any], "Invalid scale fixture")
        var preferences = try require(fixture["preferences"] as? [String: Any], "Missing scale preferences")
        let fixtureURL = directory.appendingPathComponent("scale.json")
        let store = DockStore(dataDirectory: directory.appendingPathComponent("scale-store", isDirectory: true))
        try store.importState(from: validBackup)
        for scale in [0.6, 1.6] {
            preferences["dockScale"] = scale
            fixture["preferences"] = preferences
            try JSONSerialization.data(withJSONObject: fixture).write(to: fixtureURL)
            try store.importState(from: fixtureURL)
            try check(store.preferences.dockScale == scale && !store.preferences.showDock, "Valid scale boundary failed or enabled the Dock")
        }
        let validPreferences = store.preferences
        for scale in [-1.0, 0.59, 1.61] {
            preferences["dockScale"] = scale
            fixture["preferences"] = preferences
            try JSONSerialization.data(withJSONObject: fixture).write(to: fixtureURL)
            do {
                try store.importState(from: fixtureURL)
                throw SmokeFailure(description: "Invalid Dock scale \(scale) was accepted")
            } catch is DockStoreError {}
            try check(store.preferences == validPreferences, "Rejected scale changed preferences")
        }
        preferences["dockScale"] = "NaN"
        fixture["preferences"] = preferences
        try JSONSerialization.data(withJSONObject: fixture).write(to: fixtureURL)
        do {
            try store.importState(from: fixtureURL)
            throw SmokeFailure(description: "Non-finite Dock scale was accepted")
        } catch is DecodingError {}
        try check(store.preferences == validPreferences, "Rejected non-finite scale changed preferences")
    }

    @MainActor
    private static func testNativeDockMatching(directory: URL) throws {
        let fixture: [String: Any] = [
            "tilesize": 33.0, "orientation": "bottom", "autohide": true, "static-only": false,
            "persistent-apps": [
                ["tile-type": "file-tile", "tile-data": ["file-label": "Editor", "file-data": ["_CFURLString": "file:///Applications/Editor.app/", "_CFURLStringType": 2]]],
                ["tile-type": "small-spacer-tile"],
                ["tile-type": "file-tile", "tile-data": ["file-label": "My Browser", "file-data": ["_CFURLString": "/Applications/My Browser.app", "_CFURLStringType": 0]]],
                ["tile-type": "file-tile", "tile-data": ["file-data": ["_CFURLString": "javascript:alert(1)"]]]
            ],
            "persistent-others": [
                ["tile-type": "directory-tile", "tile-data": ["file-label": "Documents", "file-data": ["_CFURLString": "file:///tmp/DocksetDocuments/", "_CFURLStringType": 2]]],
                ["tile-type": "url-tile", "tile-data": ["label": "Example", "url": ["_CFURLString": "https://example.com"]]],
                ["tile-type": "url-tile", "tile-data": ["url": ["_CFURLString": "shortcuts://run-shortcut?name=untrusted"]]]
            ]
        ]
        let config = try NativeDockConfiguration(preferences: fixture)
        try check(config.items.map(\.name) == ["Finder", "Editor", "Espaço", "My Browser", "Documents", "Example", "Lixo"], "Native Dock item order or invalid-tile filtering is wrong")
        try check(config.items.map(\.kind) == [.app, .app, .spacer, .app, .folder, .link, .folder], "Native Dock item kinds are wrong")
        try check(config.items[3].target == "/Applications/My Browser.app", "Filesystem URL type zero lost spaces")
        try check(config.iconSize == 33 && config.edge == .bottom && config.autoHide && config.showRunningApps, "Native Dock appearance or behavior was not read")
        let store = DockStore(dataDirectory: directory.appendingPathComponent("match-native", isDirectory: true))
        let initialProfiles = store.profiles
        store.preferences.showDock = false
        store.preferences.dockScale = 1.4
        try store.matchMacDockConfiguration(config)
        let matchedID = store.selectedProfileID
        try check(store.profiles.count == initialProfiles.count + 1 && store.profiles.prefix(initialProfiles.count).elementsEqual(initialProfiles), "Matching replaced an existing profile")
        try check(store.currentProfile?.name == "Meu Dock" && store.currentProfile?.items == config.items, "Matching did not select the native profile")
        try check(store.preferences.iconSize == 33 && store.preferences.autoHide && store.preferences.showDock && store.preferences.dockScale == 1, "Matching did not apply native size and visibility")
        try check(!store.hasOriginalNativeDock, "Matching must never apply native Dock changes")
        try store.matchMacDockConfiguration(config)
        try check(store.profiles.count == 4 && store.selectedProfileID == matchedID, "Repeated matching created duplicate profiles")
        let reloaded = DockStore(dataDirectory: store.dataDirectory)
        try check(reloaded.currentProfile?.items == config.items && reloaded.preferences == store.preferences, "Native matching did not persist")

        var left = fixture
        left["orientation"] = "left"; left["tilesize"] = 16; left["autohide"] = false; left["static-only"] = true
        let leftConfig = try NativeDockConfiguration(preferences: left)
        try store.matchMacDockConfiguration(leftConfig)
        try check(store.preferences.edge == .left && store.preferences.iconSize == 16 && !store.preferences.autoHide && !store.preferences.showRunningApps, "Left/static native Dock settings were lost")
        try check(DockStore(dataDirectory: store.dataDirectory).preferences.iconSize == 16, "Small native Dock size became unreadable")
        left["orientation"] = "right"; left["tilesize"] = 128
        try store.matchMacDockConfiguration(NativeDockConfiguration(preferences: left))
        try check(DockStore(dataDirectory: store.dataDirectory).preferences.iconSize == 128, "Large native Dock size became unreadable")
        for invalidSize in [15.0, 129.0, Double.nan] {
            var invalid = fixture; invalid["tilesize"] = invalidSize
            do { _ = try NativeDockConfiguration(preferences: invalid); throw SmokeFailure(description: "Invalid native icon size was accepted") }
            catch is DockStoreError {}
        }
        var invalid = fixture; invalid["persistent-apps"] = "not an array"
        do { _ = try NativeDockConfiguration(preferences: invalid); throw SmokeFailure(description: "Malformed native Dock entries were accepted") }
        catch is DockStoreError {}
        try check(NativeDockConfiguration(preferences: [:]).items.map(\.name) == ["Finder", "Lixo"], "An empty native Dock lost its fixed items")

        let blockedDirectory = directory.appendingPathComponent("match-blocked", isDirectory: true)
        let blocked = DockStore(dataDirectory: blockedDirectory)
        let previous = (blocked.profiles, blocked.selectedProfileID, blocked.preferences)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: blockedDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blockedDirectory.path) }
        do { try blocked.matchMacDockConfiguration(config); throw SmokeFailure(description: "Matching succeeded without persistence permission") }
        catch is CocoaError {}
        try check(blocked.profiles == previous.0 && blocked.selectedProfileID == previous.1 && blocked.preferences == previous.2, "Failed matching changed the live configuration")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blockedDirectory.path)
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw SmokeFailure(description: message) }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw SmokeFailure(description: message) }
        return value
    }
}
