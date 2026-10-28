import AppKit
import Combine
import Foundation

enum DockItemKind: String, Codable, CaseIterable {
    case app, folder, file, link, widget, spacer, shortcut
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, calendar, focus, battery, note, system, stopwatch, worldClock, hydration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Relógio"
        case .calendar: return "Calendário"
        case .focus: return "Foco"
        case .battery: return "Bateria"
        case .note: return "Nota adesiva"
        case .system: return "Atividade do sistema"
        case .stopwatch: return "Cronômetro"
        case .worldClock: return "Relógio mundial"
        case .hydration: return "Hidratação"
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock"
        case .calendar: return "calendar"
        case .focus: return "timer"
        case .battery: return "battery.75percent"
        case .note: return "note.text"
        case .system: return "waveform.path.ecg"
        case .stopwatch: return "stopwatch"
        case .worldClock: return "globe.americas"
        case .hydration: return "drop.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .clock: return "Hora local, sempre à vista."
        case .calendar: return "Dia, mês e calendário."
        case .focus: return "Um temporizador para concentrar."
        case .battery: return "Carga e alimentação do seu Mac."
        case .note: return "Escreva e guarde uma nota rápida."
        case .system: return "Memória e atividade do Mac."
        case .stopwatch: return "Meça o tempo de uma atividade."
        case .worldClock: return "Acompanhe outros fusos horários."
        case .hydration: return "Registre seus copos de água."
        }
    }
}

struct DockItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var kind: DockItemKind
    var target: String
}

struct DockProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
    var items: [DockItem]
}

enum DockEdge: String, Codable, CaseIterable {
    case bottom, left, right

    var title: String {
        switch self {
        case .bottom: return "Embaixo"
        case .left: return "Esquerda"
        case .right: return "Direita"
        }
    }
}

struct DockPreferences: Codable, Equatable {
    var edge: DockEdge = .bottom
    var iconSize: Double = 48
    var autoHide: Bool = false
    var showRunningApps: Bool = true
    var showDock: Bool = true
    var launchAtLogin: Bool = false
    var opacity: Double = 0.92
    var dockScale: Double = 1
    /// Seconds the bar takes to fade in or out. Zero is instant.
    var revealDuration: Double = 0.2

    private enum CodingKeys: String, CodingKey {
        case edge, iconSize, autoHide, showRunningApps, showDock, launchAtLogin, opacity, dockScale, revealDuration
    }

    init(edge: DockEdge = .bottom, iconSize: Double = 48, autoHide: Bool = false,
         showRunningApps: Bool = true, showDock: Bool = true, launchAtLogin: Bool = false,
         opacity: Double = 0.92, dockScale: Double = 1, revealDuration: Double = 0.2) {
        self.edge = edge
        self.iconSize = iconSize
        self.autoHide = autoHide
        self.showRunningApps = showRunningApps
        self.showDock = showDock
        self.launchAtLogin = launchAtLogin
        self.opacity = opacity
        self.dockScale = dockScale
        self.revealDuration = revealDuration
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        edge = try values.decodeIfPresent(DockEdge.self, forKey: .edge) ?? .bottom
        iconSize = try values.decodeIfPresent(Double.self, forKey: .iconSize) ?? 48
        autoHide = try values.decodeIfPresent(Bool.self, forKey: .autoHide) ?? false
        showRunningApps = try values.decodeIfPresent(Bool.self, forKey: .showRunningApps) ?? true
        showDock = try values.decodeIfPresent(Bool.self, forKey: .showDock) ?? true
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        opacity = try values.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.92
        dockScale = try values.decodeIfPresent(Double.self, forKey: .dockScale) ?? 1
        revealDuration = min(max(try values.decodeIfPresent(Double.self, forKey: .revealDuration) ?? 0.2, 0), 1)
    }
}

/// A read-only translation of Apple's Dock preferences into the custom Dock model.
struct NativeDockConfiguration {
    let items: [DockItem]
    let iconSize: Double
    let edge: DockEdge
    let autoHide: Bool
    let showRunningApps: Bool

    init(preferences: [String: Any]) throws {
        guard let apps = (preferences["persistent-apps"] ?? []) as? [[String: Any]],
              let others = (preferences["persistent-others"] ?? []) as? [[String: Any]] else {
            throw DockStoreError.invalid("Não foi possível ler os itens do Dock do macOS.")
        }
        let size = (preferences["tilesize"] as? NSNumber)?.doubleValue ?? 48
        guard size.isFinite, (16...128).contains(size) else {
            throw DockStoreError.invalid("O tamanho do Dock do macOS está fora do intervalo de 16 a 128 pixels.")
        }
        iconSize = size
        edge = DockEdge(rawValue: preferences["orientation"] as? String ?? "bottom") ?? .bottom
        autoHide = (preferences["autohide"] as? NSNumber)?.boolValue ?? false
        showRunningApps = !((preferences["static-only"] as? NSNumber)?.boolValue ?? false)

        let finder = "/System/Library/CoreServices/Finder.app"
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        var result = [DockItem(name: "Finder", kind: .app, target: finder)]
        for entry in apps + others {
            guard let item = Self.item(from: entry), item.target != finder, item.target != trash else { continue }
            result.append(item)
        }
        result.append(DockItem(name: "Lixo", kind: .folder, target: trash))
        guard result.count <= 500 else { throw DockStoreError.invalid("O Dock do macOS tem mais de 500 itens.") }
        items = result
    }

    private static func item(from entry: [String: Any]) -> DockItem? {
        guard let type = entry["tile-type"] as? String else { return nil }
        if ["spacer-tile", "small-spacer-tile", "flex-spacer-tile"].contains(type) {
            return DockItem(name: "Espaço", kind: .spacer, target: "")
        }
        guard let tile = entry["tile-data"] as? [String: Any] else { return nil }
        if type == "url-tile" {
            guard let raw = (tile["url"] as? [String: Any])?["_CFURLString"] as? String,
                  raw.count <= 8192, let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { return nil }
            return DockItem(name: label(tile, fallback: url.host ?? "Link"), kind: .link, target: url.absoluteString)
        }
        guard ["file-tile", "directory-tile"].contains(type), let url = fileURL(tile), url.path.count <= 8192 else { return nil }
        let kind: DockItemKind
        if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame { kind = .app }
        else if type == "directory-tile" || (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { kind = .folder }
        else { kind = .file }
        return DockItem(name: label(tile, fallback: url.deletingPathExtension().lastPathComponent), kind: kind, target: url.standardizedFileURL.path)
    }

    private static func label(_ tile: [String: Any], fallback: String) -> String {
        let label = ((tile["file-label"] as? String) ?? (tile["label"] as? String) ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        return String((label.isEmpty ? fallback : label).prefix(512))
    }

    private static func fileURL(_ tile: [String: Any]) -> URL? {
        if let file = tile["file-data"] as? [String: Any], let raw = file["_CFURLString"] as? String {
            if raw.hasPrefix("/") { return URL(fileURLWithPath: raw) }
            if let url = URL(string: raw), url.isFileURL { return url }
        }
        if let bookmark = tile["book"] as? Data {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale), url.isFileURL {
                return url
            }
        }
        return nil
    }
}

struct NativeDockLayout: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var savedAt: Date = Date()
    var payload: Data
}

private struct DockState: Codable {
    var version: Int = 1
    var profiles: [DockProfile]
    var selectedProfileID: UUID
    var preferences: DockPreferences
    var nativeLayouts: [NativeDockLayout]
    var originalNativeDock: Data?
    var widgetPreferences: Data? = nil
}

enum DockStoreError: LocalizedError {
    case invalid(String)
    case command(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let reason), .command(let reason): return reason
        }
    }
}

@MainActor
final class DockStore: ObservableObject {
    @Published var profiles: [DockProfile] { didSet { persist() } }
    @Published var selectedProfileID: UUID { didSet { persist() } }
    @Published var preferences: DockPreferences { didSet { persist() } }
    @Published var nativeLayouts: [NativeDockLayout] { didSet { persist() } }
    @Published var lastError: String?

    let dataDirectory: URL
    private let stateURL: URL
    private var originalNativeDock: Data?
    private var isLoading = false
    private var persistenceBlocked = false
    private static let profileLimit = 100
    private static let itemLimit = 500
    private static let widgetPreferenceSuffixes = ["note", "city", "waterCount", "waterDay"]

    var currentProfile: DockProfile? {
        profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    var hasOriginalNativeDock: Bool { originalNativeDock != nil }

    init(dataDirectory: URL? = nil) {
        let directory = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DocksetLocal", isDirectory: true)
        self.dataDirectory = directory
        stateURL = directory.appendingPathComponent("state.json")
        let initialProfiles = Self.makeInitialProfiles()
        profiles = initialProfiles
        selectedProfileID = initialProfiles[0].id
        preferences = DockPreferences()
        nativeLayouts = []

        if FileManager.default.fileExists(atPath: stateURL.path) {
            do {
                let data = try Data(contentsOf: stateURL)
                let state = try Self.decodeValidated(data)
                profiles = state.profiles
                selectedProfileID = state.selectedProfileID
                preferences = state.preferences
                nativeLayouts = state.nativeLayouts
                originalNativeDock = state.originalNativeDock
            } catch {
                let loadError = error.localizedDescription
                do {
                    let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                    let recoveryURL = directory.appendingPathComponent("state-recovery-\(timestamp)-\(UUID().uuidString).json")
                    try FileManager.default.copyItem(at: stateURL, to: recoveryURL)
                    lastError = "Não foi possível carregar os perfis salvos. Uma cópia do arquivo original foi guardada em \(recoveryURL.lastPathComponent). \(loadError)"
                } catch {
                    persistenceBlocked = true
                    lastError = "Não foi possível carregar nem copiar o arquivo de perfis. O salvamento foi bloqueado para preservar o original. \(loadError)"
                }
            }
        } else {
            persist()
        }
    }

    func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
    }

    func cycleProfile(_ direction: Int) {
        guard !profiles.isEmpty else { return }
        let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) ?? 0
        let next = ((index + direction) % profiles.count + profiles.count) % profiles.count
        selectedProfileID = profiles[next].id
    }

    func createProfile(name: String) {
        guard canAddProfile() else { return }
        let name = cleanName(name, fallback: "Novo perfil")
        let profile = DockProfile(name: name, symbol: "square.grid.2x2", items: [])
        profiles.append(profile)
        selectedProfileID = profile.id
    }

    func renameProfile(_ id: UUID, name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = cleanName(name, fallback: profiles[index].name)
    }

    func duplicateProfile(_ id: UUID) {
        guard let original = profiles.first(where: { $0.id == id }) else { return }
        guard canAddProfile() else { return }
        let copy = DockProfile(name: cleanName("\(original.name) cópia", fallback: "Cópia"), symbol: original.symbol,
                               items: original.items.map { DockItem(name: $0.name, kind: $0.kind, target: $0.target) })
        profiles.append(copy)
        selectedProfileID = copy.id
    }

    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1, profiles.contains(where: { $0.id == id }) else { return }
        if selectedProfileID == id, let next = profiles.first(where: { $0.id != id }) {
            selectedProfileID = next.id
        }
        profiles.removeAll { $0.id == id }
    }

    func addItems(_ urls: [URL]) {
        guard let index = currentProfileIndex else { return }
        let remaining = Self.itemLimit - profiles[index].items.count
        guard remaining > 0 else { itemLimitError(); return }
        let existingTargets = Set(profiles[index].items.map(\.target))
        var additions: [DockItem] = []
        var targets = existingTargets
        for url in urls {
            guard additions.count < remaining else { itemLimitError(); break }
            if !url.isFileURL {
                guard url.absoluteString.count <= 8192, Self.validWebURL(url.absoluteString), targets.insert(url.absoluteString).inserted else { continue }
                additions.append(DockItem(name: url.host ?? url.absoluteString, kind: .link, target: url.absoluteString))
                continue
            }
            let url = url.standardizedFileURL
            guard url.path.count <= 8192, FileManager.default.fileExists(atPath: url.path), targets.insert(url.path).inserted else { continue }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey, .localizedNameKey])
            let kind: DockItemKind = values?.isApplication == true || url.pathExtension.lowercased() == "app" ? .app :
                (values?.isDirectory == true ? .folder : .file)
            let name = values?.localizedName ?? url.deletingPathExtension().lastPathComponent
            additions.append(DockItem(name: name.replacingOccurrences(of: ".app", with: ""), kind: kind, target: url.path))
        }
        profiles[index].items.append(contentsOf: additions)
    }

    func addLink(name: String, url: String) {
        var target = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.contains("://") { target = "https://" + target }
        guard Self.validWebURL(target) else {
            lastError = "Digite um endereço http ou https válido."
            return
        }
        append(DockItem(name: cleanName(name, fallback: URL(string: target)?.host ?? "Link"), kind: .link, target: target))
    }

    func addWidget(_ kind: WidgetKind) {
        append(DockItem(name: kind.title, kind: .widget, target: kind.rawValue))
    }

    func addSpacer() { append(DockItem(name: "Espaço", kind: .spacer, target: "")) }

    func addShortcut(name: String) {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { lastError = "Digite o nome de um Atalho do macOS."; return }
        append(DockItem(name: target, kind: .shortcut, target: target))
    }

    func removeItem(_ id: UUID) {
        guard let index = currentProfileIndex else { return }
        profiles[index].items.removeAll { $0.id == id }
    }

    func moveItem(_ id: UUID, offset: Int) {
        guard let profileIndex = currentProfileIndex,
              let index = profiles[profileIndex].items.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(index + offset, 0), profiles[profileIndex].items.count - 1)
        guard destination != index else { return }
        let item = profiles[profileIndex].items.remove(at: index)
        profiles[profileIndex].items.insert(item, at: destination)
    }

    func updateItem(_ item: DockItem) {
        guard let profileIndex = currentProfileIndex,
              let index = profiles[profileIndex].items.firstIndex(where: { $0.id == item.id }) else { return }
        var item = item
        item.name = cleanName(item.name, fallback: profiles[profileIndex].items[index].name)
        do { try Self.validateItemFields(item) }
        catch { lastError = error.localizedDescription; return }
        profiles[profileIndex].items[index] = item
    }

    func exportState(to url: URL) throws {
        if url.standardizedFileURL == stateURL.standardizedFileURL { try requirePersistence() }
        try encodedState().write(to: url, options: .atomic)
    }

    func importState(from url: URL) throws {
        try requirePersistence()
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var state = try Self.decodeValidated(data)
        // Keep this Mac's restore point. An imported backup must never replace it.
        state.originalNativeDock = originalNativeDock
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try encoder.encode(state).write(to: stateURL, options: .atomic)
        isLoading = true
        profiles = state.profiles
        selectedProfileID = state.selectedProfileID
        preferences = state.preferences
        nativeLayouts = state.nativeLayouts
        isLoading = false
        Self.restoreWidgetPreferences(state.widgetPreferences, profiles: state.profiles)
        NotificationCenter.default.post(name: Notification.Name("DocksetLocal.widgetsImported"), object: nil)
    }

    func matchCurrentMacDock() {
        do { try matchMacDockConfiguration(NativeDockConfiguration(preferences: NativeDockBridge.readPreferences())) }
        catch { lastError = error.localizedDescription }
    }

    func matchMacDockConfiguration(_ configuration: NativeDockConfiguration) throws {
        try requirePersistence()
        let existing = profiles.firstIndex { $0.name == "Meu Dock" }
        guard existing != nil || profiles.count < Self.profileLimit else {
            throw DockStoreError.invalid("Você atingiu o limite de 100 perfis. Remova um perfil antes de copiar o Dock do macOS.")
        }
        guard configuration.items.count <= Self.itemLimit else {
            throw DockStoreError.invalid("O Dock do macOS tem mais de 500 itens.")
        }
        for item in configuration.items { try Self.validateItemFields(item) }
        let before = (profiles, selectedProfileID, preferences)
        isLoading = true
        defer { isLoading = false }
        let profile = DockProfile(id: existing.map { profiles[$0].id } ?? UUID(), name: "Meu Dock", symbol: "rectangle.bottomthird.inset.filled", items: configuration.items)
        if let existing { profiles[existing] = profile }
        else { profiles.append(profile) }
        selectedProfileID = profile.id
        preferences.edge = configuration.edge
        preferences.iconSize = configuration.iconSize
        preferences.autoHide = configuration.autoHide
        preferences.showRunningApps = configuration.showRunningApps
        preferences.dockScale = 1
        preferences.showDock = true
        do { try save(); lastError = nil }
        catch {
            profiles = before.0; selectedProfileID = before.1; preferences = before.2
            throw error
        }
    }

    func saveNativeLayout(name: String) {
        do {
            let payload = try NativeDockBridge.capture()
            nativeLayouts.append(NativeDockLayout(name: cleanName(name, fallback: "Dock do macOS"), payload: payload))
        } catch { lastError = error.localizedDescription }
    }

    func deleteNativeLayout(_ id: UUID) { nativeLayouts.removeAll { $0.id == id } }

    func applyNativeLayout(_ id: UUID) {
        guard let layout = nativeLayouts.first(where: { $0.id == id }) else { return }
        do {
            if originalNativeDock == nil {
                let snapshot = try NativeDockBridge.capture()
                originalNativeDock = snapshot
                // The restore point must be durable before changing Apple's Dock.
                do { try save() } catch { originalNativeDock = nil; throw error }
            }
            try NativeDockBridge.apply(layout.payload)
        } catch { lastError = error.localizedDescription }
    }

    func restoreOriginalNativeDock() {
        guard let payload = originalNativeDock else {
            lastError = "O Dock do macOS ainda não foi alterado por este app."
            return
        }
        do { try NativeDockBridge.apply(payload) }
        catch { lastError = error.localizedDescription }
    }

    private var currentProfileIndex: Int? {
        profiles.firstIndex(where: { $0.id == selectedProfileID }) ?? profiles.indices.first
    }

    private func append(_ item: DockItem) {
        guard let index = currentProfileIndex else { return }
        guard profiles[index].items.count < Self.itemLimit else { itemLimitError(); return }
        var item = item
        item.name = cleanName(item.name, fallback: "Item")
        do { try Self.validateItemFields(item) }
        catch { lastError = error.localizedDescription; return }
        profiles[index].items.append(item)
    }

    private func canAddProfile() -> Bool {
        guard profiles.count < Self.profileLimit else {
            lastError = "Você atingiu o limite de \(Self.profileLimit) perfis. Remova um perfil antes de adicionar outro."
            return false
        }
        return true
    }

    private func itemLimitError() {
        lastError = "Você atingiu o limite de \(Self.itemLimit) itens neste perfil. Remova um item para continuar."
    }

    private func cleanName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? fallback : trimmed).prefix(120))
    }

    private func persist() {
        guard !isLoading else { return }
        do { try save() }
        catch { lastError = "Não foi possível salvar os perfis. \(error.localizedDescription)" }
    }

    private func save() throws {
        try requirePersistence()
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try encodedState().write(to: stateURL, options: .atomic)
    }

    private func requirePersistence() throws {
        guard !persistenceBlocked else {
            throw DockStoreError.invalid("O salvamento está bloqueado porque não foi possível copiar o arquivo original de perfis.")
        }
    }

    private func encodedState() throws -> Data {
        let state = DockState(profiles: profiles, selectedProfileID: selectedProfileID,
                              preferences: preferences, nativeLayouts: nativeLayouts,
                              originalNativeDock: originalNativeDock,
                              widgetPreferences: try Self.captureWidgetPreferences(profiles: profiles))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= 10_000_000 else {
            throw DockStoreError.invalid("Os perfis excedem o limite de 10 MB. Remova itens para salvar novamente.")
        }
        return data
    }

    private static func validWebURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty else { return false }
        return true
    }

    private static func decodeValidated(_ data: Data) throws -> DockState {
        guard data.count <= 10_000_000 else { throw DockStoreError.invalid("O backup excede o limite de 10 MB.") }
        let state = try JSONDecoder().decode(DockState.self, from: data)
        guard state.version == 1 else { throw DockStoreError.invalid("Esta versão do backup não é compatível.") }
        guard !state.profiles.isEmpty, state.profiles.count <= profileLimit else {
            throw DockStoreError.invalid("O backup precisa conter entre 1 e 100 perfis.")
        }
        let profileIDs = state.profiles.map(\.id)
        guard Set(profileIDs).count == profileIDs.count, profileIDs.contains(state.selectedProfileID) else {
            throw DockStoreError.invalid("O backup contém perfis duplicados ou uma seleção inválida.")
        }
        var itemIDs = Set<UUID>()
        for profile in state.profiles {
            guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  profile.name.count <= 120, profile.items.count <= itemLimit else {
                throw DockStoreError.invalid("O backup contém um perfil inválido.")
            }
            for item in profile.items {
                guard itemIDs.insert(item.id).inserted else {
                    throw DockStoreError.invalid("O backup contém itens inválidos ou duplicados.")
                }
                try validateItemFields(item)
            }
        }
        guard state.preferences.iconSize.isFinite, (16...128).contains(state.preferences.iconSize),
              state.preferences.opacity.isFinite, (0.2...1).contains(state.preferences.opacity),
              state.preferences.dockScale.isFinite, (0.6...1.6).contains(state.preferences.dockScale) else {
            throw DockStoreError.invalid("O backup contém preferências de aparência inválidas.")
        }
        guard Set(state.nativeLayouts.map(\.id)).count == state.nativeLayouts.count else {
            throw DockStoreError.invalid("O backup contém layouts nativos duplicados.")
        }
        for layout in state.nativeLayouts {
            try NativeDockBridge.validate(layout.payload)
        }
        if let original = state.originalNativeDock { try NativeDockBridge.validate(original) }
        _ = try validatedWidgetPreferences(state.widgetPreferences, profiles: state.profiles)
        return state
    }

    private static func validateItemFields(_ item: DockItem) throws {
        guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              item.name.count <= 512, item.target.count <= 8192 else {
            throw DockStoreError.invalid("O item tem um nome ou destino inválido.")
        }
        if item.kind == .widget, WidgetKind(rawValue: item.target) == nil {
            throw DockStoreError.invalid("O item contém um widget desconhecido.")
        }
        if item.kind == .link, !validWebURL(item.target) {
            throw DockStoreError.invalid("O item contém um endereço inválido.")
        }
        if [.app, .folder, .file].contains(item.kind), !item.target.hasPrefix("/") {
            throw DockStoreError.invalid("O item contém um caminho de arquivo inválido.")
        }
        if item.kind == .shortcut, item.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DockStoreError.invalid("O item precisa indicar o nome de um Atalho do macOS.")
        }
    }

    private static func widgetKeys(profiles: [DockProfile]) -> Set<String> {
        Set(profiles.flatMap(\.items).filter { $0.kind == .widget }.flatMap { item in
            widgetPreferenceSuffixes.map { "DocksetLocal.widget.\(item.id.uuidString).\($0)" }
        })
    }

    private static func validWidgetValue(_ value: Any, suffix: String) -> Bool {
        switch suffix {
        case "note": return (value as? String).map { $0.count <= 20_000 } ?? false
        case "city": return (value as? String).map { TimeZone(identifier: $0) != nil } ?? false
        case "waterDay": return (value as? String).map { $0.count <= 32 } ?? false
        case "waterCount":
            guard CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID(), let count = value as? Int else { return false }
            return (0...1000).contains(count)
        default: return false
        }
    }

    private static func captureWidgetPreferences(profiles: [DockProfile]) throws -> Data {
        var values: [String: Any] = [:]
        for key in widgetKeys(profiles: profiles) {
            let suffix = String(key.split(separator: ".").last ?? "")
            if let value = UserDefaults.standard.object(forKey: key), validWidgetValue(value, suffix: suffix) {
                values[key] = value
            }
        }
        return try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }

    private static func validatedWidgetPreferences(_ data: Data?, profiles: [DockProfile]) throws -> [String: Any] {
        guard let data else { return [:] }
        guard let values = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw DockStoreError.invalid("As preferências dos widgets são inválidas.")
        }
        let allowed = widgetKeys(profiles: profiles)
        for (key, value) in values {
            let suffix = String(key.split(separator: ".").last ?? "")
            guard allowed.contains(key), validWidgetValue(value, suffix: suffix) else {
                throw DockStoreError.invalid("O backup contém preferências de widget desconhecidas ou inválidas.")
            }
        }
        return values
    }

    private static func restoreWidgetPreferences(_ data: Data?, profiles: [DockProfile]) {
        // Older backups did not include widget contents. Keep their existing local values.
        guard data != nil, let values = try? validatedWidgetPreferences(data, profiles: profiles) else { return }
        let defaults = UserDefaults.standard
        for key in widgetKeys(profiles: profiles) { defaults.removeObject(forKey: key) }
        for (key, value) in values { defaults.set(value, forKey: key) }
    }

    private static func makeInitialProfiles() -> [DockProfile] {
        let fm = FileManager.default
        var realApps: [String] = []
        // Read the current pinned apps so the first profile reflects this Mac.
        if let data = try? NativeDockBridge.capture(),
           let snapshot = try? NativeDockBridge.dictionary(from: data),
           let apps = snapshot["persistent-apps"] as? [[String: Any]] {
            realApps = apps.compactMap { entry in
                guard let tile = entry["tile-data"] as? [String: Any],
                      let file = tile["file-data"] as? [String: Any],
                      let raw = file["_CFURLString"] as? String,
                      let url = URL(string: raw), url.isFileURL,
                      fm.fileExists(atPath: url.path) else { return nil }
                return url.path
            }
        }
        let applications = ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
                            "/System/Applications", "/System/Applications/Utilities"]
        let discovered = applications.flatMap { root in
            ((try? fm.contentsOfDirectory(atPath: root)) ?? []).filter { $0.hasSuffix(".app") }.map { root + "/" + $0 }
        }
        var seen = Set<String>()
        realApps = (realApps + discovered).filter { seen.insert($0).inserted }
        func appItems(matching preferred: [String], fallbackCount: Int) -> [DockItem] {
            var selected: [String] = []
            for name in preferred {
                if let path = realApps.first(where: { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }),
                   !selected.contains(path) { selected.append(path) }
            }
            for path in realApps where selected.count < fallbackCount {
                if !selected.contains(path) { selected.append(path) }
            }
            return selected.prefix(7).map { DockItem(name: URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent, kind: .app, target: $0) }
        }
        let work = appItems(matching: ["T3 Code", "Codex", "Helium", "Aside", "Safari", "Slack", "Visual Studio Code", "Terminal"], fallbackCount: 5)
        let personal = appItems(matching: ["Safari", "Music", "Spotify", "Photos", "Messages", "Notes"], fallbackCount: 4)
        let focus = appItems(matching: ["Notes", "Obsidian", "Terminal"], fallbackCount: 2)
        return [
            DockProfile(name: "Trabalho", symbol: "briefcase", items: work + [DockItem(name: "Espaço", kind: .spacer, target: ""), DockItem(name: WidgetKind.clock.title, kind: .widget, target: WidgetKind.clock.rawValue), DockItem(name: WidgetKind.battery.title, kind: .widget, target: WidgetKind.battery.rawValue)]),
            DockProfile(name: "Pessoal", symbol: "house", items: personal + [DockItem(name: WidgetKind.calendar.title, kind: .widget, target: WidgetKind.calendar.rawValue), DockItem(name: WidgetKind.hydration.title, kind: .widget, target: WidgetKind.hydration.rawValue)]),
            DockProfile(name: "Foco", symbol: "moon", items: focus + [DockItem(name: WidgetKind.focus.title, kind: .widget, target: WidgetKind.focus.rawValue), DockItem(name: WidgetKind.note.title, kind: .widget, target: WidgetKind.note.rawValue)])
        ]
    }
}

/// Reads and writes only pinned items. Apple's size, hiding and placement settings stay intact.
private enum NativeDockBridge {
    private static let domain = "com.apple.dock"
    private static let keys = ["persistent-apps", "persistent-others"]

    static func capture() throws -> Data {
        let preferences = try readPreferences()
        let snapshot: [String: Any] = [keys[0]: preferences[keys[0]] ?? [], keys[1]: preferences[keys[1]] ?? []]
        return try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
    }

    static func readPreferences() throws -> [String: Any] {
        let output = try run("/usr/bin/defaults", arguments: ["export", domain, "-"])
        guard let preferences = try PropertyListSerialization.propertyList(from: output, options: [], format: nil) as? [String: Any] else {
            throw DockStoreError.command("Não foi possível ler o Dock do macOS.")
        }
        return preferences
    }

    static func dictionary(from data: Data) throws -> [String: Any] {
        guard let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              Set(value.keys) == Set(keys), value[keys[0]] is [Any], value[keys[1]] is [Any] else {
            throw DockStoreError.invalid("O layout do Dock do macOS está incompleto.")
        }
        return value
    }

    static func validate(_ data: Data) throws {
        let snapshot = try dictionary(from: data)
        for key in keys {
            guard let entries = snapshot[key] as? [[String: Any]], entries.count <= 500 else {
                throw DockStoreError.invalid("O layout do Dock do macOS contém itens inválidos.")
            }
            for entry in entries {
                guard let type = entry["tile-type"] as? String,
                      ["file-tile", "directory-tile", "url-tile", "spacer-tile", "small-spacer-tile", "flex-spacer-tile", "recents-tile"].contains(type) else {
                    throw DockStoreError.invalid("O layout do Dock do macOS contém um tipo de item desconhecido.")
                }
            }
        }
    }

    static func apply(_ data: Data) throws {
        try validate(data)
        let snapshot = try dictionary(from: data)
        CFPreferencesAppSynchronize(domain as CFString)
        let before = try capture()
        for key in keys {
            CFPreferencesSetAppValue(key as CFString, snapshot[key] as CFPropertyList?, domain as CFString)
        }
        guard CFPreferencesAppSynchronize(domain as CFString) else {
            if let rollback = try? dictionary(from: before) {
                for key in keys {
                    CFPreferencesSetAppValue(key as CFString, rollback[key] as CFPropertyList?, domain as CFString)
                }
                CFPreferencesAppSynchronize(domain as CFString)
            }
            throw DockStoreError.command("O macOS não permitiu salvar o layout do Dock.")
        }
        _ = try run("/usr/bin/killall", arguments: ["Dock"])
    }

    private static func run(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw DockStoreError.command("Não foi possível atualizar o Dock do macOS. \(detail)")
        }
        return output
    }
}
