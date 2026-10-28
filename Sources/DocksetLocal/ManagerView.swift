import SwiftUI
import AppKit
import UniformTypeIdentifiers

private typealias ManagerState<Value> = SwiftUI.State<Value>

@MainActor
struct ManagerView: View {
    @ObservedObject var store: DockStore
    @ManagerState private var tab: ManagerTab = .dock
    @ManagerState private var sheet: ManagerSheet?
    @ManagerState private var pendingDelete: DockProfile?
    @ManagerState private var pendingNativeLayout: NativeDockLayout?
    @ManagerState private var dropTarget = false

    private let accent = Color(red: 0.53, green: 0.40, blue: 0.91)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Picker("Conteúdo", selection: $tab) {
                    ForEach(ManagerTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
                Divider().padding(.horizontal, 30)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch tab {
                        case .dock: dockEditor
                        case .widgets: widgetLibrary
                        case .appearance: appearance
                        case .native: nativeLayouts
                        }
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 660)
        .tint(accent)
        .sheet(item: $sheet) { mode in
            ManagerInputSheet(mode: mode) { first, second in
                performSheet(mode, first: first, second: second)
            }
        }
        .alert("Não foi possível concluir", isPresented: Binding(
            get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } }
        )) { Button("OK") { store.lastError = nil } } message: {
            Text(store.lastError ?? "")
        }
        .confirmationDialog("Excluir perfil?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Excluir \(pendingDelete?.name ?? "perfil")", role: .destructive) {
                if let profile = pendingDelete { store.deleteProfile(profile.id) }
                pendingDelete = nil
            }
        } message: { Text("Os outros perfis e os aplicativos do Mac continuam disponíveis.") }
        .confirmationDialog("Aplicar layout ao Dock do macOS?", isPresented: Binding(
            get: { pendingNativeLayout != nil }, set: { if !$0 { pendingNativeLayout = nil } }
        ), titleVisibility: .visible) {
            Button("Aplicar \(pendingNativeLayout?.name ?? "layout")") {
                if let layout = pendingNativeLayout { store.applyNativeLayout(layout.id) }
                pendingNativeLayout = nil
            }
        } message: {
            Text("Os itens fixados do Dock da Apple serão substituídos pelo layout salvo. Seus apps abertos continuam abertos. Você poderá restaurar o backup original.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "rectangle.bottomthird.inset.filled")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 43, height: 43)
                    .background(LinearGradient(colors: [accent, accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dockset").font(.system(size: 20, weight: .bold))
                    Text("LOCAL").font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(2.5).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 35)
            HStack {
                Text("SEUS PERFIS").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                Spacer()
                Button { sheet = .newProfile } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Criar perfil")
                    .accessibilityLabel("Criar perfil")
            }.padding(.horizontal, 22).padding(.bottom, 10)
            List(selection: Binding<UUID?>(
                get: { store.selectedProfileID },
                set: { if let id = $0 { store.selectProfile(id) } }
            )) {
                ForEach(Array(store.profiles.enumerated()), id: \.element.id) { index, profile in
                    HStack(spacing: 10) {
                        Image(systemName: profile.symbol).frame(width: 20).foregroundStyle(profile.id == store.selectedProfileID ? accent : .secondary)
                        Text(profile.name).lineLimit(1)
                        Spacer(minLength: 2)
                        if index < 9 { Text("⌃⌥\(index + 1)").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    }
                    .padding(.vertical, 7)
                    .tag(profile.id)
                    .contextMenu {
                        Button("Renomear…") { sheet = .renameProfile(profile.id, profile.name) }
                        Button("Duplicar") { store.duplicateProfile(profile.id) }
                        Divider()
                        Button("Excluir…", role: .destructive) { pendingDelete = profile }
                            .disabled(store.profiles.count <= 1)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Spacer(minLength: 14)
            VStack(alignment: .leading, spacing: 12) {
                Label("Tudo fica neste Mac", systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Button("Importar…", action: importBackup)
                    Spacer()
                    Button("Exportar…", action: exportBackup)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                Text("Versão local independente").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(22)
        }
        .frame(width: 218)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Seu Mac. Do seu jeito.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text(store.currentProfile?.name ?? "Meu Dock").font(.system(size: 30, weight: .bold))
                    Text(store.preferences.showDock ? "ATIVO" : "OCULTO")
                        .font(.system(size: 9, weight: .bold)).tracking(0.8)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .foregroundStyle(store.preferences.showDock ? Color.green : Color.secondary)
                        .background((store.preferences.showDock ? Color.green : Color.secondary).opacity(0.1), in: Capsule())
                }
            }
            Spacer()
            Menu {
                Button("Aplicativos…", systemImage: "app.badge") { pickFiles(.app) }
                Button("Pasta…", systemImage: "folder") { pickFiles(.folder) }
                Button("Arquivos…", systemImage: "doc") { pickFiles(.file) }
                Button("Link…", systemImage: "link") { sheet = .link }
                Button("Atalho do macOS…", systemImage: "command") { sheet = .shortcut }
                Divider()
                Button("Widget…", systemImage: "square.grid.2x2") { tab = .widgets }
                Button("Espaçador", systemImage: "rectangle.split.3x1") { store.addSpacer() }
            } label: { Label("Adicionar", systemImage: "plus").padding(.horizontal, 6).padding(.vertical, 3) }
                .menuStyle(.borderedButton)
                .fixedSize()
                .help("Adicionar ao perfil selecionado")
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 25)
    }

    private var dockEditor: some View {
        VStack(alignment: .leading, spacing: 23) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeading("Uma barra para este momento", subtitle: "Abra apps, pastas e links. Seus widgets ficam sempre por perto.")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        if let profile = store.currentProfile {
                            ForEach(profile.items) { item in
                                previewItem(item)
                                    .contextMenu { itemContextMenu(item) }
                            }
                            if profile.items.isEmpty {
                                Label("Use Adicionar ou arraste um app para cá", systemImage: "plus.app")
                                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(20)
                            }
                        }
                    }
                    .padding(16)
                    .frame(minHeight: 98)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(accent.opacity(dropTarget ? 0.8 : 0.13), lineWidth: dropTarget ? 2 : 1))
                .dropDestination(for: URL.self) { urls, _ in
                    store.addItems(urls)
                    return !urls.isEmpty
                } isTargeted: { dropTarget = $0 }
                HStack {
                    Label("Prévia do perfil", systemImage: "eye").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button(store.preferences.showDock ? "Ocultar barra" : "Mostrar barra") {
                        store.preferences.showDock.toggle()
                    }.buttonStyle(.borderless).font(.system(size: 11))
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("No seu Dock").font(.system(size: 17, weight: .semibold))
                    Text("\(store.currentProfile?.items.count ?? 0) itens").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        if let profile = store.currentProfile {
                            Button("Renomear perfil…") { sheet = .renameProfile(profile.id, profile.name) }
                            Button("Duplicar perfil") { store.duplicateProfile(profile.id) }
                        }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 25)
                }
                LazyVStack(spacing: 1) {
                    ForEach(store.currentProfile?.items ?? []) { item in
                        ManagerItemRow(item: item, onMove: { store.moveItem(item.id, offset: $0) }, onRemove: { store.removeItem(item.id) })
                        Divider().padding(.leading, 58)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "keyboard").foregroundStyle(accent)
                Text("Troque de perfil pela barra de menus ou com Control + Option + 1, 2, 3…")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var widgetLibrary: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionHeading("Pequenos widgets. Mais utilidade.", subtitle: "Dados do seu Mac e ferramentas do dia a dia. Clique em Adicionar para colocar no perfil atual.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 16)], spacing: 16) {
                ForEach(WidgetKind.allCases) { kind in
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: kind.symbol).foregroundStyle(accent)
                            Text(kind.title).font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                        HStack { Spacer(minLength: 0); WidgetGalleryPreview(kind: kind); Spacer(minLength: 0) }
                            .frame(height: 76)
                            .padding(.vertical, 3)
                        Text(kind.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(height: 32, alignment: .topLeading)
                        Button { store.addWidget(kind) } label: {
                            Label("Adicionar", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Adicionar widget \(kind.title)")
                    }
                    .padding(17)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.065)))
                }
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 24) {
            sectionHeading("Encontre seu lugar na tela", subtitle: "A aparência e a posição valem para todos os seus perfis.")
            Form {
                Section("Configuração do macOS") {
                    Button("Usar configuração do meu Dock") { store.matchCurrentMacDock() }
                        .accessibilityLabel("Usar configuração do meu Dock")
                    Text("Copia os itens fixados, o tamanho, a posição e a ocultação automática do Dock do macOS. Seus perfis são preservados.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Barra personalizada") {
                    Toggle("Mostrar o Dock personalizado", isOn: $store.preferences.showDock)
                    Picker("Posição", selection: $store.preferences.edge) {
                        ForEach(DockEdge.allCases, id: \.self) { edge in Text(edge.title).tag(edge) }
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("Tamanho da barra")
                        Spacer()
                        HStack {
                            Slider(value: $store.preferences.dockScale, in: 0.6...1.6, step: 0.05)
                                .frame(width: 170)
                                .accessibilityLabel("Tamanho da barra")
                                .accessibilityValue("\(Int((store.preferences.dockScale * 100).rounded())) por cento")
                            Text("\(Int((store.preferences.dockScale * 100).rounded()))%")
                                .font(.system(size: 11, design: .monospaced)).frame(width: 45)
                            Button("100%") { store.preferences.dockScale = 1 }
                                .controlSize(.small)
                                .accessibilityLabel("Restaurar tamanho da barra para 100%")
                                .help("Restaurar tamanho padrão da barra")
                        }
                        .accessibilityElement(children: .contain)
                    }
                    .accessibilityElement(children: .contain)
                    Text("Arraste a alça na extremidade da barra para redimensionar apps e widgets juntos.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack {
                        Text("Tamanho dos ícones")
                        Spacer()
                        HStack {
                            Slider(value: $store.preferences.iconSize, in: 16...128, step: 1)
                                .frame(width: 210)
                                .accessibilityLabel("Tamanho dos ícones")
                                .accessibilityValue("\(Int(store.preferences.iconSize)) pixels")
                            Text("\(Int(store.preferences.iconSize)) px").font(.system(size: 11, design: .monospaced)).frame(width: 45)
                        }
                        .accessibilityElement(children: .contain)
                    }
                    .accessibilityElement(children: .contain)
                    HStack {
                        Text("Opacidade")
                        Spacer()
                        HStack {
                            Slider(value: $store.preferences.opacity, in: 0.35...1, step: 0.05)
                                .frame(width: 210)
                                .accessibilityLabel("Opacidade da barra")
                                .accessibilityValue("\(Int((store.preferences.opacity * 100).rounded())) por cento")
                            Text("\(Int(store.preferences.opacity * 100))%").font(.system(size: 11, design: .monospaced)).frame(width: 45)
                        }
                        .accessibilityElement(children: .contain)
                    }
                    .accessibilityElement(children: .contain)
                }
                Section("Comportamento") {
                    Toggle("Ocultar automaticamente", isOn: $store.preferences.autoHide)
                    Text("A barra desaparece quando você afasta o ponteiro e reaparece ao levá-lo à borda da tela.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Mostrar aplicativos em execução", isOn: $store.preferences.showRunningApps)
                    Toggle("Abrir ao iniciar sessão", isOn: $store.preferences.launchAtLogin)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 590)
            Label("A barra personalizada funciona ao lado do Dock da Apple.", systemImage: "info.circle")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var nativeLayouts: some View {
        VStack(alignment: .leading, spacing: 23) {
            sectionHeading("Seu Dock da Apple, salvo", subtitle: "Guarde os apps, pastas e espaçadores fixados no Dock do macOS para alternar entre layouts.")
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "rectangle.bottomthird.inset.filled").font(.system(size: 28)).foregroundStyle(accent).padding(.top, 2)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Salvar o layout atual").font(.system(size: 15, weight: .semibold))
                    Text("Captura os itens que estão fixados no Dock da Apple agora. Aplicar um layout não abre nem fecha aplicativos.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Salvar layout…") { sheet = .nativeLayout }.buttonStyle(.borderedProminent).padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 17))
            if store.nativeLayouts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack").font(.system(size: 30)).foregroundStyle(.tertiary)
                    Text("Nenhum layout salvo ainda").font(.system(size: 14, weight: .medium))
                    Text("Seu primeiro layout começa com o Dock que você já usa.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Layouts salvos").font(.system(size: 17, weight: .semibold))
                    ForEach(store.nativeLayouts) { layout in
                        HStack(spacing: 13) {
                            Image(systemName: "square.stack.3d.up").foregroundStyle(accent).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(layout.name).font(.system(size: 13, weight: .medium))
                                Text(layout.savedAt, format: .dateTime.day().month().year().hour().minute()).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Aplicar…") { pendingNativeLayout = layout }.buttonStyle(.bordered)
                        }.padding(15).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        .contextMenu { Button("Excluir layout", role: .destructive) { store.deleteNativeLayout(layout.id) } }
                    }
                }
            }
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Voltar ao Dock original").font(.system(size: 13, weight: .medium))
                    Text("Antes da primeira troca, o app guarda uma cópia do Dock original.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Restaurar original") { store.restoreOriginalNativeDock() }.buttonStyle(.bordered).disabled(!store.hasOriginalNativeDock)
            }
        }
    }

    @ViewBuilder private func previewItem(_ item: DockItem) -> some View {
        switch item.kind {
        case .widget: DockWidgetView(item: item)
        case .spacer: RoundedRectangle(cornerRadius: 1).fill(.secondary.opacity(0.25)).frame(width: 1, height: 38).padding(.horizontal, 8)
        default:
            VStack(spacing: 4) {
                ManagerItemIcon(item: item).frame(width: 48, height: 48)
                Text(item.name).font(.system(size: 9)).lineLimit(1).frame(width: 58)
            }.help(item.name)
        }
    }

    @ViewBuilder private func itemContextMenu(_ item: DockItem) -> some View {
        Button("Mover para a esquerda") { store.moveItem(item.id, offset: -1) }
        Button("Mover para a direita") { store.moveItem(item.id, offset: 1) }
        Divider()
        Button("Remover", role: .destructive) { store.removeItem(item.id) }
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pickFiles(_ kind: DockItemKind) {
        let panel = NSOpenPanel()
        panel.title = kind == .app ? "Adicionar aplicativos" : kind == .folder ? "Adicionar pastas" : "Adicionar arquivos"
        panel.prompt = "Adicionar"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = kind == .folder
        panel.canChooseFiles = kind != .folder
        if kind == .app { panel.allowedContentTypes = [.application] }
        if panel.runModal() == .OK { store.addItems(panel.urls) }
    }

    private func performSheet(_ mode: ManagerSheet, first: String, second: String) {
        switch mode {
        case .newProfile: store.createProfile(name: first)
        case .renameProfile(let id, _): store.renameProfile(id, name: first)
        case .link: store.addLink(name: first, url: second)
        case .shortcut: store.addShortcut(name: first)
        case .nativeLayout: store.saveNativeLayout(name: first)
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "Exportar seus perfis"
        panel.nameFieldStringValue = "Dockset Local.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.exportState(to: url) } catch { store.lastError = error.localizedDescription }
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.title = "Importar backup de perfis"
        panel.message = "O backup substituirá os perfis e preferências atuais. Exporte seus perfis antes se quiser preservá-los."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.importState(from: url) } catch { store.lastError = error.localizedDescription }
        }
    }
}

private enum ManagerTab: String, CaseIterable, Identifiable {
    case dock = "Meu Dock", widgets = "Widgets", appearance = "Aparência", native = "Dock do macOS"
    var id: String { rawValue }
}

private enum ManagerSheet: Identifiable {
    case newProfile, renameProfile(UUID, String), link, shortcut, nativeLayout
    var id: String {
        switch self {
        case .newProfile: "new"
        case .renameProfile(let id, _): "rename-\(id)"
        case .link: "link"
        case .shortcut: "shortcut"
        case .nativeLayout: "native"
        }
    }
    var title: String {
        switch self {
        case .newProfile: "Novo perfil"
        case .renameProfile: "Renomear perfil"
        case .link: "Adicionar link"
        case .shortcut: "Adicionar atalho do macOS"
        case .nativeLayout: "Salvar Dock do macOS"
        }
    }
    var initialName: String { if case .renameProfile(_, let name) = self { name } else { "" } }
    var isLink: Bool { if case .link = self { true } else { false } }
    var isShortcut: Bool { if case .shortcut = self { true } else { false } }
}

@MainActor
private struct ManagerInputSheet: View {
    let mode: ManagerSheet
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ManagerState private var first = ""
    @ManagerState private var second = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text(mode.title).font(.system(size: 21, weight: .semibold))
            TextField(mode.isShortcut ? "Nome exato no app Atalhos" : "Nome", text: $first)
                .textFieldStyle(.roundedBorder).focused($focused)
            if mode.isLink { TextField("https://exemplo.com", text: $second).textFieldStyle(.roundedBorder) }
            if mode.isShortcut {
                Text("Digite o nome de um atalho que já existe no app Atalhos deste Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Salvar") { onSave(first.trimmingCharacters(in: .whitespacesAndNewlines), second.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (mode.isLink && second.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(28)
        .frame(width: 390)
        .onAppear { first = mode.initialName; focused = true }
    }
}

@MainActor
private struct ManagerItemRow: View {
    let item: DockItem
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ManagerItemIcon(item: item).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 10) {
                Button { onMove(-1) } label: { Image(systemName: "chevron.up") }.help("Mover para cima").accessibilityLabel("Mover \(item.name) para cima")
                Button { onMove(1) } label: { Image(systemName: "chevron.down") }.help("Mover para baixo").accessibilityLabel("Mover \(item.name) para baixo")
                Button(role: .destructive, action: onRemove) { Image(systemName: "xmark") }.help("Remover").accessibilityLabel("Remover \(item.name)")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }.padding(.horizontal, 9).padding(.vertical, 8)
    }
    private var detail: String {
        switch item.kind {
        case .widget: WidgetKind(rawValue: item.target)?.subtitle ?? "Widget"
        case .spacer: "Separa grupos de itens"
        case .shortcut: "Atalho do macOS"
        default: item.target
        }
    }
}

@MainActor
private struct ManagerItemIcon: View {
    let item: DockItem
    var body: some View {
        Group {
            switch item.kind {
            case .app, .folder, .file:
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.target)).resizable().interpolation(.high).scaledToFit()
            case .widget:
                Image(systemName: WidgetKind(rawValue: item.target)?.symbol ?? "square.grid.2x2")
                    .font(.system(size: 23)).foregroundStyle(.purple).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            case .link:
                Image(systemName: "globe").font(.system(size: 27)).foregroundStyle(.blue).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .shortcut:
                Image(systemName: "command.square.fill").font(.system(size: 29)).foregroundStyle(.purple).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .spacer:
                Image(systemName: "rectangle.split.3x1").font(.system(size: 23)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
