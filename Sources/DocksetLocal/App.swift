import AppKit
import SwiftUI
import Combine
import Carbon
import ServiceManagement
import UniformTypeIdentifiers

private typealias AppViewState<Value> = SwiftUI.State<Value>

@main
enum DocksetLocalApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DockStore()
    private var managerWindow: NSWindow?
    private var dockController: DockPanelController?
    private var statusItem: NSStatusItem?
    private var observation: AnyCancellable?
    private var hotKeys: [EventHotKeyRef] = []
    private var hotKeyHandler: EventHandlerRef?
    private var keyboardMonitor: Any?
    private var loginSetting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let duplicate = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.gui.DocksetLocal")
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let duplicate {
            duplicate.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        loginSetting = store.preferences.launchAtLogin
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "rectangle.bottomthird.inset.filled", accessibilityDescription: "Dockset Local")
        statusItem?.button?.toolTip = "Dockset Local"
        dockController = DockPanelController(store: store, manage: { [weak self] in self?.showManager() })
        observation = store.objectWillChange.debounce(for: .milliseconds(50), scheduler: RunLoop.main).sink { [weak self] _ in
            self?.updateMenu()
            self?.updateLoginSetting()
        }
        updateMenu()
        registerHotKeys()
        let firstRun = !UserDefaults.standard.bool(forKey: "hasOpenedManager")
        if firstRun || CommandLine.arguments.contains("--show-manager") {
            showManager()
            UserDefaults.standard.set(true, forKey: "hasOpenedManager")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    @objc func showManager() {
        if managerWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Dockset Local"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 900, height: 620)
            window.contentView = NSHostingView(rootView: ManagerView(store: store).environment(\.locale, Locale(identifier: "pt_BR")))
            window.center()
            managerWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        managerWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        store.selectProfile(id)
        dockController?.reveal()
    }

    @objc private func toggleDock() { store.preferences.showDock.toggle() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func updateMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Dockset Local", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        for (index, profile) in store.profiles.enumerated() {
            let item = NSMenuItem(title: profile.name, action: #selector(selectProfile(_:)), keyEquivalent: index < 9 ? String(index + 1) : "")
            item.keyEquivalentModifierMask = [.control, .option]
            item.representedObject = profile.id
            item.target = self
            item.state = profile.id == store.selectedProfileID ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let manage = NSMenuItem(title: "Gerenciar Docks…", action: #selector(showManager), keyEquivalent: ",")
        manage.target = self
        menu.addItem(manage)
        let toggle = NSMenuItem(title: store.preferences.showDock ? "Ocultar barra" : "Mostrar barra", action: #selector(toggleDock), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Sair do Dockset Local", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem?.menu = menu
    }

    private func updateLoginSetting() {
        guard loginSetting != store.preferences.launchAtLogin else { return }
        let requested = store.preferences.launchAtLogin
        do {
            if requested { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginSetting = requested
        } catch {
            store.preferences.launchAtLogin = loginSetting
            store.lastError = "Não foi possível atualizar a inicialização com o Mac: \(error.localizedDescription)"
        }
    }

    private func registerHotKeys() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control, .option],
                  let number = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(number),
                  let self, self.store.profiles.indices.contains(number - 1) else { return event }
            self.store.selectProfile(self.store.profiles[number - 1].id)
            self.dockController?.reveal()
            return nil
        }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            let index = Int(identifier.id) - 1
            Task { @MainActor in
                guard delegate.store.profiles.indices.contains(index) else { return }
                delegate.store.selectProfile(delegate.store.profiles[index].id)
                delegate.dockController?.reveal()
            }
            return noErr
        }, 1, &type, context, &hotKeyHandler)
        let codes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        var unavailable: [String] = []
        for (index, code) in codes.enumerated() {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(code, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x444C4F43, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { hotKeys.append(reference) }
            else { unavailable.append(String(index + 1)) }
        }
        if !unavailable.isEmpty {
            store.lastError = "Os atalhos Control + Option + \(unavailable.joined(separator: ", ")) já estão em uso por outro app. Você pode trocar os perfis pelo ícone na barra de menus."
        }
    }
}

private final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DockPanelController {
    private let store: DockStore
    private let panel: NSPanel
    private let manage: () -> Void
    private var hostingView: NSHostingView<AnyView>?
    private var displayedRunningTargets: [String] = []
    private var changes: AnyCancellable?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var gestureMonitor: Any?
    private var lastGesture = Date.distantPast
    private var lastHover = Date()
    private var forceVisibleUntil = Date()
    private var isResizing = false
    private var currentScreen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

    init(store: DockStore, manage: @escaping () -> Void) {
        self.store = store
        self.manage = manage
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.title = "Barra Dockset Local"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        changes = store.objectWillChange.debounce(for: .milliseconds(40), scheduler: RunLoop.main).sink { [weak self] _ in self?.refresh() }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refresh() } })
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in Task { @MainActor in self?.updateVisibility() } }
        gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
            guard let self, event.window === self.panel,
                  event.type == .swipe || event.modifierFlags.contains(.command) else { return event }
            let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            guard abs(delta) > 0.5, Date().timeIntervalSince(self.lastGesture) > 0.45 else { return nil }
            self.lastGesture = Date()
            self.store.cycleProfile(delta > 0 ? -1 : 1)
            self.reveal()
            return nil
        }
        refresh()
    }

    deinit {
        timer?.invalidate()
        if let gestureMonitor { NSEvent.removeMonitor(gestureMonitor) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
    }

    func reveal() {
        forceVisibleUntil = Date().addingTimeInterval(2)
        if store.preferences.showDock { panel.orderFrontRegardless() }
    }

    private func runningApps() -> [DockItem] {
        guard store.preferences.showRunningApps else { return [] }
        let pinned = Set(store.currentProfile?.items.filter { $0.kind == .app }.map(\.target) ?? [])
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  let url = app.bundleURL, !pinned.contains(url.path) else { return nil }
            return DockItem(name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, kind: .app, target: url.path)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func width(for item: DockItem) -> CGFloat {
        if item.kind == .widget { return 168 }
        if item.kind == .spacer { return 16 }
        return store.preferences.iconSize + 12
    }

    private func refresh() {
        let extras = runningApps()
        let items = (store.currentProfile?.items ?? []) + extras
        let vertical = store.preferences.edge != .bottom
        let area = currentScreen.visibleFrame
        let widgetHeight = max(68, store.preferences.iconSize + 12)
        let natural = items.reduce(CGFloat(72)) { $0 + (vertical ? ($1.kind == .spacer ? 16 : widgetHeight + 8) : width(for: $1) + 8) }
        let scale = store.preferences.dockScale
        let width: CGFloat = vertical ? (items.contains { $0.kind == .widget } ? 194 : store.preferences.iconSize + 36) * scale : min(natural * scale, area.width - 32)
        let height: CGFloat = vertical ? min(natural * scale, area.height - 48) : max(90, store.preferences.iconSize + 32) * scale
        let origin: NSPoint
        switch store.preferences.edge {
        case .bottom: origin = NSPoint(x: area.midX - width / 2, y: area.minY + 12)
        case .left: origin = NSPoint(x: area.minX + 12, y: area.midY - height / 2)
        case .right: origin = NSPoint(x: area.maxX - width - 12, y: area.midY - height / 2)
        }
        let targets = extras.map(\.target)
        if hostingView == nil || targets != displayedRunningTargets {
            let host = NSHostingView(rootView: AnyView(DockBarView(store: store, running: extras, manage: manage, resizeStateChanged: { [weak self] active in
                self?.isResizing = active
                self?.lastHover = Date()
            }).environment(\.locale, Locale(identifier: "pt_BR"))))
            hostingView = host
            displayedRunningTargets = targets
            panel.contentView = host
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        updateVisibility()
    }

    private func updateVisibility() {
        guard store.preferences.showDock else { panel.orderOut(nil); return }
        if isResizing { panel.orderFrontRegardless(); return }
        guard store.preferences.autoHide else { panel.orderFrontRegardless(); return }
        let mouse = NSEvent.mouseLocation
        let screen = currentScreen.frame
        let edge: Bool
        switch store.preferences.edge {
        case .bottom: edge = mouse.y <= screen.minY + 5 && mouse.x >= screen.minX && mouse.x <= screen.maxX
        case .left: edge = mouse.x <= screen.minX + 5 && mouse.y >= screen.minY && mouse.y <= screen.maxY
        case .right: edge = mouse.x >= screen.maxX - 5 && mouse.y >= screen.minY && mouse.y <= screen.maxY
        }
        if edge || (panel.isVisible && panel.frame.insetBy(dx: -12, dy: -20).contains(mouse)) { lastHover = Date() }
        let hasPopover = NSApp.windows.contains { $0.isVisible && $0 !== panel && String(describing: type(of: $0)).contains("Popover") }
        if edge || hasPopover || Date() < forceVisibleUntil || Date().timeIntervalSince(lastHover) < 0.85 { panel.orderFrontRegardless() }
        else { panel.orderOut(nil) }
    }
}

struct DockBarView: View {
    @ObservedObject var store: DockStore
    let running: [DockItem]
    let manage: () -> Void
    let resizeStateChanged: (Bool) -> Void
    private var vertical: Bool { store.preferences.edge != .bottom }

    var body: some View {
        GeometryReader { geometry in
            barContent
                .frame(width: geometry.size.width / store.preferences.dockScale,
                       height: geometry.size.height / store.preferences.dockScale)
                .scaleEffect(store.preferences.dockScale, anchor: .topLeading)
        }
    }

    private var barContent: some View {
        AnyLayout(vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))) {
        ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
            AnyLayout(vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))) {
                profileMenu
                ForEach(store.currentProfile?.items ?? []) { item in dockItem(item) }
                if !running.isEmpty {
                    Rectangle().fill(.primary.opacity(0.15)).frame(width: vertical ? 40 : 1, height: vertical ? 1 : 38).padding(4)
                    ForEach(running) { item in dockItem(item) }
                }
            }
            .padding(10)
        }
        DockResizeHandle(edge: store.preferences.edge, scale: store.preferences.dockScale, onChange: { scale in
            store.preferences.dockScale = scale
        }, onDragStateChanged: resizeStateChanged)
        .frame(width: vertical ? nil : 18, height: vertical ? 18 : nil)
        .frame(maxWidth: vertical ? .infinity : nil, maxHeight: vertical ? nil : .infinity)
        }
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial).opacity(store.preferences.opacity)
        }
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.27), lineWidth: 1))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in store.addItems([url]) } }
                }
            }
            return !providers.isEmpty
        }
    }

    private var profileMenu: some View {
        Menu {
            ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                Button { store.selectProfile(profile.id) } label: {
                    Label(profile.name, systemImage: profile.id == store.selectedProfileID ? "checkmark.circle.fill" : profile.symbol)
                }
            }
            Divider()
            Button("Gerenciar Docks…", action: manage)
            Button("Próximo perfil") { store.cycleProfile(1) }
            Button("Ocultar barra") { store.preferences.showDock = false }
        } label: {
            Image(systemName: store.currentProfile?.symbol ?? "square.stack.3d.up.fill")
                .font(.system(size: 19, weight: .semibold)).foregroundStyle(Color.purple)
                .frame(width: 34, height: 48)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .help("\(store.currentProfile?.name ?? "Perfis") • Trocar perfil")
        .accessibilityLabel("Trocar perfil do Dock")
    }

    @ViewBuilder private func dockItem(_ item: DockItem) -> some View {
        if item.kind == .spacer {
            Color.clear.frame(width: vertical ? 40 : 16, height: vertical ? 16 : 40)
        } else if item.kind == .widget {
            DockWidgetView(item: item)
                .contextMenu { Button("Remover do Dock") { store.removeItem(item.id) }; Button("Gerenciar Docks…", action: manage) }
        } else {
            DockLaunchButton(item: item, size: store.preferences.iconSize, launch: { launch(item) })
                .contextMenu {
                    Button("Abrir") { launch(item) }
                    if item.kind == .app || item.kind == .folder || item.kind == .file {
                        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.target)]) }
                    }
                    if !running.contains(where: { $0.id == item.id }) { Button("Remover do Dock") { store.removeItem(item.id) } }
                    Button("Gerenciar Docks…", action: manage)
                }
        }
    }

    private func launch(_ item: DockItem) {
        if item.kind == .shortcut {
            var components = URLComponents()
            components.scheme = "shortcuts"; components.host = "run-shortcut"
            components.queryItems = [URLQueryItem(name: "name", value: item.target)]
            if let url = components.url { NSWorkspace.shared.open(url) }
        } else if item.kind == .link {
            if let url = URL(string: item.target), !NSWorkspace.shared.open(url) { store.lastError = "Não foi possível abrir \(item.name)." }
        } else {
            let url = URL(fileURLWithPath: item.target)
            guard FileManager.default.fileExists(atPath: url.path) else { store.lastError = "O item \(item.name) não foi encontrado. Adicione o novo local no editor."; return }
            if item.kind == .app {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                    if let error { Task { @MainActor in store.lastError = error.localizedDescription } }
                }
            } else if !NSWorkspace.shared.open(url) { store.lastError = "Não foi possível abrir \(item.name)." }
        }
    }
}

private struct DockLaunchButton: View {
    let item: DockItem
    let size: Double
    let launch: () -> Void
    @AppViewState private var hovered = false
    private var isRunning: Bool { item.kind == .app && NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path == item.target } }
    private var icon: NSImage {
        if [.app, .folder, .file].contains(item.kind) { return NSWorkspace.shared.icon(forFile: item.target) }
        return NSImage(systemSymbolName: item.kind == .shortcut ? "square.stack.3d.up.fill" : "globe", accessibilityDescription: item.name) ?? NSImage()
    }
    var body: some View {
        Button(action: launch) {
            VStack(spacing: 3) {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size)
                    .scaleEffect(hovered ? 1.10 : 1)
                Circle().fill(isRunning ? Color.primary.opacity(0.7) : .clear).frame(width: 4, height: 4)
            }.frame(width: size + 12, height: max(68, size + 12))
        }
        .buttonStyle(.plain).help(item.name).accessibilityLabel("Abrir \(item.name)")
        .onHover { hovered = $0 }.animation(.easeOut(duration: 0.15), value: hovered)
    }
}
