import SwiftUI
import AppKit
import Combine
import IOKit.ps
import Darwin

private typealias WidgetViewState<Value> = SwiftUI.State<Value>

private let widgetAccent = Color.accentColor

/// The dock and library share these compact, independently interactive widgets.
@MainActor
struct DockWidgetView: View {
    let item: DockItem
    var compact: Bool = true
    @StateObject private var state: WidgetState
    @WidgetViewState private var showingDetails = false

    init(item: DockItem, compact: Bool = true) {
        self.item = item
        self.compact = compact
        _state = StateObject(wrappedValue: WidgetState.shared(for: item.id))
    }

    private var kind: WidgetKind { WidgetKind(rawValue: item.target) ?? .clock }

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            content(at: context.date)
                .frame(width: width, height: 64)
                .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .popover(isPresented: $showingDetails, arrowEdge: .bottom) { details }
        .contextMenu {
            if kind == .focus {
                Button("Reiniciar foco") { state.resetFocus() }
            } else if kind == .stopwatch {
                Button("Zerar cronômetro") { state.resetStopwatch() }
            } else if kind == .hydration {
                Button("Remover um copo") { state.changeWater(by: -1) }
                Button("Zerar hoje") { state.resetWater() }
            }
            Button("Detalhes") { showingDetails = true }
        }
        .help(kind.title)
    }

    private var refreshInterval: TimeInterval {
        switch kind {
        case .clock, .focus, .stopwatch, .worldClock: return 1
        case .system: return 5
        default: return 30
        }
    }

    private var width: CGFloat {
        switch kind {
        case .clock: return 146
        case .calendar: return 106
        case .focus: return 142
        case .battery: return 130
        case .note: return 156
        case .system: return 144
        case .stopwatch: return 144
        case .worldClock: return 152
        case .hydration: return 120
        }
    }

    private var background: AnyShapeStyle {
        kind == .note ? AnyShapeStyle(Color.yellow.opacity(0.18)) : AnyShapeStyle(.thinMaterial)
    }

    @ViewBuilder private func content(at date: Date) -> some View {
        switch kind {
        case .clock:
            Button { showingDetails = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.fill").font(.system(size: 27, weight: .light)).foregroundStyle(widgetAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(date, format: .dateTime.hour().minute()).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("Relógio, \(date.formatted(date: .abbreviated, time: .shortened))")
        case .calendar:
            Button { openCalendar() } label: {
                HStack(spacing: 10) {
                    VStack(spacing: 0) {
                        Text(date, format: .dateTime.month(.abbreviated)).font(.system(size: 8, weight: .bold)).textCase(.uppercase).foregroundStyle(.red)
                        Text(date, format: .dateTime.day()).font(.system(size: 27, weight: .medium, design: .rounded))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(date, format: .dateTime.weekday(.abbreviated)).font(.system(size: 11, weight: .semibold))
                        Text("Agenda").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("Abrir Calendário, hoje \(date.formatted(date: .complete, time: .omitted))")
        case .focus:
            Button { state.toggleFocus() } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(widgetAccent.opacity(0.18), lineWidth: 3)
                        Circle().trim(from: 0, to: CGFloat(state.focusSeconds(at: date)) / Double(state.focusDuration))
                            .stroke(widgetAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                        Image(systemName: state.focusDeadline == nil ? "play.fill" : "pause.fill").font(.system(size: 11)).foregroundStyle(widgetAccent)
                    }.frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timerString(TimeInterval(state.focusSeconds(at: date)))).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(state.focusDeadline == nil ? "Iniciar foco" : "Em foco").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("\(state.focusDeadline == nil ? "Iniciar" : "Pausar") foco, \(state.focusSeconds(at: date)) segundos")
        case .battery:
            let battery = BatteryReading.current()
            Button { showingDetails = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: battery.symbol).font(.system(size: 26)).foregroundStyle(battery.percent.map { $0 < 20 ? Color.orange : widgetAccent } ?? widgetAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(battery.percent.map { "\($0)%" } ?? "Tomada").font(.system(size: 20, weight: .medium, design: .rounded))
                        Text(battery.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("Bateria: \(battery.percent.map { "\($0) por cento" } ?? "não disponível"), \(battery.status)")
        case .note:
            Button { showingDetails = true } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "note.text").foregroundStyle(.orange).font(.system(size: 17)).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nota rápida").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text(state.note.isEmpty ? "Clique para escrever" : state.note).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.leading)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("Editar nota rápida")
        case .system:
            let reading = SystemReading.current()
            Button { showingDetails = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 25)).foregroundStyle(widgetAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("RAM \(reading.usedPercent)%").font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(String(format: "Carga %.2f", reading.load)).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("Memória em uso \(reading.usedPercent) por cento, carga média \(reading.load)")
        case .stopwatch:
            Button { state.toggleStopwatch() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "stopwatch").font(.system(size: 27)).foregroundStyle(widgetAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timerString(state.elapsed(at: date))).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(state.stopwatchStart == nil ? "Cronômetro" : "Contando").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("\(state.stopwatchStart == nil ? "Iniciar" : "Pausar") cronômetro")
        case .worldClock:
            Button { showingDetails = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "globe.europe.africa.fill").font(.system(size: 27)).foregroundStyle(widgetAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(worldTime(date, zone: state.timeZone)).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(state.cityName).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("Horário de \(state.cityName): \(worldTime(date, zone: state.timeZone))")
        case .hydration:
            Button { state.changeWater(by: 1) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "drop.fill").font(.system(size: 27)).foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(state.waterToday) / 8").font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("+ um copo").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain).accessibilityLabel("Registrar copo de água. \(state.waterToday) copos hoje")
        }
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(kind.title, systemImage: kind.symbol).font(.headline)
            switch kind {
            case .note:
                TextEditor(text: $state.note).font(.body).frame(width: 270, height: 150)
                    .padding(6).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Texto da nota")
                Text("Salvo automaticamente neste Mac.").font(.caption).foregroundStyle(.secondary)
            case .focus:
                Text("Um intervalo para uma tarefa por vez.").foregroundStyle(.secondary)
                HStack {
                    ForEach([15, 25, 50], id: \.self) { minutes in
                        Button("\(minutes) min") { state.setFocus(minutes: minutes) }
                    }
                }
                HStack {
                    Button(state.focusDeadline == nil ? "Iniciar" : "Pausar") { state.toggleFocus() }
                    Button("Reiniciar") { state.resetFocus() }
                }
            case .stopwatch:
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timerString(state.elapsed(at: context.date))).font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
                }
                HStack {
                    Button(state.stopwatchStart == nil ? "Iniciar" : "Pausar") { state.toggleStopwatch() }
                    Button("Zerar") { state.resetStopwatch() }
                }
            case .worldClock:
                Picker("Cidade", selection: $state.cityID) {
                    ForEach(WidgetState.cities, id: \.zone) { city in Text(city.name).tag(city.zone) }
                }.frame(width: 240)
                Text("Horário local atualizado automaticamente.").font(.caption).foregroundStyle(.secondary)
            case .battery:
                let reading = BatteryReading.current()
                Text(reading.percent.map { "\($0)% de bateria" } ?? "Este Mac está conectado à energia.").font(.title3)
                Text(reading.status).foregroundStyle(.secondary)
                Button("Abrir ajustes de bateria") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") { NSWorkspace.shared.open(url) }
                }
            case .system:
                let reading = SystemReading.current()
                Text("\(reading.usedGB, specifier: "%.1f") GB de \(reading.totalGB, specifier: "%.0f") GB em uso").font(.title3)
                Text("RAM ativa, comprimida e reservada pelo sistema.").font(.caption).foregroundStyle(.secondary)
                Text(String(format: "Carga média de 1 minuto: %.2f", reading.load)).font(.callout)
                Text("\(ProcessInfo.processInfo.activeProcessorCount) núcleos disponíveis").font(.caption).foregroundStyle(.secondary)
                Button("Monitor de Atividade") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                }
            case .hydration:
                Text("\(state.waterToday) copos registrados hoje").font(.title3)
                Text("Cada clique registra um copo. A contagem recomeça a cada dia.").font(.caption).foregroundStyle(.secondary).frame(width: 240, alignment: .leading)
                HStack {
                    Button("Remover um") { state.changeWater(by: -1) }
                    Button("Adicionar um") { state.changeWater(by: 1) }
                }
                Button("Zerar hoje") { state.resetWater() }
            case .calendar:
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide).year()).font(.title3)
                Button("Abrir Calendário") { openCalendar() }
            case .clock:
                Text(Date.now, format: .dateTime.hour().minute().second()).font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide).year()).foregroundStyle(.secondary)
                Text(TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).frame(minWidth: 250, alignment: .leading)
    }

    private func openCalendar() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}

/// Library previews do not create or mutate saved widget sessions.
struct WidgetGalleryPreview: View {
    let kind: WidgetKind

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol).font(.system(size: 28, weight: .light)).foregroundStyle(kind == .hydration ? Color.cyan : widgetAccent)
            VStack(alignment: .leading, spacing: 3) {
                Text(previewValue).font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit()
                Text(kind.title).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 160, height: 64)
        .background(kind == .note ? AnyShapeStyle(Color.yellow.opacity(0.16)) : AnyShapeStyle(.thinMaterial), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var previewValue: String {
        switch kind {
        case .clock: return Date.now.formatted(date: .omitted, time: .shortened)
        case .calendar: return Date.now.formatted(.dateTime.day().month(.abbreviated))
        case .focus: return "25:00"
        case .battery: return BatteryReading.current().percent.map { "\($0)%" } ?? "Tomada"
        case .note: return "Sua próxima ideia"
        case .system: return "RAM \(SystemReading.current().usedPercent)%"
        case .stopwatch: return "00:00"
        case .worldClock: return worldTime(.now, zone: TimeZone(identifier: "Europe/London") ?? .current)
        case .hydration: return "0 / 8 copos"
        }
    }
}

@MainActor
private final class WidgetState: ObservableObject {
    private static var sessions: [UUID: WidgetState] = [:]
    static func shared(for id: UUID) -> WidgetState {
        if let state = sessions[id] { return state }
        let state = WidgetState(id: id)
        sessions[id] = state
        return state
    }

    static let cities: [(name: String, zone: String)] = [
        ("São Paulo", "America/Sao_Paulo"), ("Londres", "Europe/London"),
        ("Nova York", "America/New_York"), ("Tóquio", "Asia/Tokyo"),
        ("Lisboa", "Europe/Lisbon"), ("São Francisco", "America/Los_Angeles")
    ]
    private let prefix: String
    @Published var note: String { didSet { save(note, "note") } }
    @Published var cityID: String { didSet { save(cityID, "city") } }
    @Published private(set) var focusDuration: Int = 25 * 60
    @Published private(set) var focusRemaining: Int = 25 * 60
    @Published private(set) var focusDeadline: Date?
    private var focusCompletionTask: Task<Void, Never>?
    private var focusRunID = UUID()
    private var onFocusFinished: () -> Void = { NSSound.beep() }
    private var importSubscription: AnyCancellable?
    @Published private(set) var stopwatchStart: Date?
    @Published private(set) var stopwatchAccumulated: TimeInterval = 0
    @Published private var waterCount: Int
    @Published private var waterDay: String

    private init(id: UUID) {
        prefix = "DocksetLocal.widget.\(id.uuidString)."
        note = UserDefaults.standard.string(forKey: prefix + "note") ?? ""
        cityID = UserDefaults.standard.string(forKey: prefix + "city") ?? "Europe/London"
        waterCount = UserDefaults.standard.integer(forKey: prefix + "waterCount")
        waterDay = UserDefaults.standard.string(forKey: prefix + "waterDay") ?? ""
        importSubscription = NotificationCenter.default.publisher(for: Notification.Name("DocksetLocal.widgetsImported"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadSavedValues() }
    }

    var timeZone: TimeZone { TimeZone(identifier: cityID) ?? .current }
    var cityName: String { Self.cities.first { $0.zone == cityID }?.name ?? cityID }
    var waterToday: Int { waterDay == Self.dayKey ? waterCount : 0 }
    private static var dayKey: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    func focusSeconds(at date: Date) -> Int {
        focusDeadline.map { max(0, Int(ceil($0.timeIntervalSince(date)))) } ?? focusRemaining
    }
    func toggleFocus() {
        if focusDeadline != nil {
            focusRemaining = focusSeconds(at: .now)
            focusDeadline = nil
            cancelFocusCompletion()
        } else {
            if focusRemaining == 0 { focusRemaining = focusDuration }
            focusDeadline = Date.now.addingTimeInterval(Double(focusRemaining))
            scheduleFocusCompletion()
        }
    }
    func resetFocus() {
        cancelFocusCompletion()
        focusDeadline = nil
        focusRemaining = focusDuration
    }
    func setFocus(minutes: Int) { focusDuration = minutes * 60; resetFocus() }
    func finishFocusIfNeeded() {
        guard let deadline = focusDeadline, deadline <= .now else { return }
        cancelFocusCompletion()
        focusDeadline = nil
        focusRemaining = 0
        onFocusFinished()
    }
    private func cancelFocusCompletion() {
        focusRunID = UUID()
        focusCompletionTask?.cancel()
        focusCompletionTask = nil
    }
    private func scheduleFocusCompletion() {
        cancelFocusCompletion()
        guard let deadline = focusDeadline else { return }
        let runID = focusRunID
        // The session owns completion, so switching profiles cannot lose the alert.
        focusCompletionTask = Task { [weak self] in
            while !Task.isCancelled {
                let remaining = deadline.timeIntervalSinceNow
                if remaining > 0 {
                    do { try await Task.sleep(for: .seconds(remaining)) }
                    catch { return }
                    continue
                }
                guard let self, self.focusRunID == runID else { return }
                self.finishFocusIfNeeded()
                return
            }
        }
    }
    private func reloadSavedValues() {
        let defaults = UserDefaults.standard
        note = defaults.string(forKey: prefix + "note") ?? ""
        cityID = defaults.string(forKey: prefix + "city") ?? "Europe/London"
        waterCount = defaults.integer(forKey: prefix + "waterCount")
        waterDay = defaults.string(forKey: prefix + "waterDay") ?? ""
    }
    func elapsed(at date: Date) -> TimeInterval { stopwatchAccumulated + (stopwatchStart.map { max(0, date.timeIntervalSince($0)) } ?? 0) }
    func toggleStopwatch() {
        if stopwatchStart != nil {
            stopwatchAccumulated = elapsed(at: .now)
            stopwatchStart = nil
        } else { stopwatchStart = .now }
    }
    func resetStopwatch() { stopwatchStart = nil; stopwatchAccumulated = 0 }
    func changeWater(by amount: Int) {
        let count = waterToday
        waterDay = Self.dayKey
        waterCount = max(0, min(1000, count + amount))
        save(waterDay, "waterDay"); save(waterCount, "waterCount")
    }
    func resetWater() { waterDay = Self.dayKey; waterCount = 0; save(waterDay, "waterDay"); save(waterCount, "waterCount") }
    private func save(_ value: Any, _ key: String) { UserDefaults.standard.set(value, forKey: prefix + key) }
}

private struct BatteryReading {
    var percent: Int?
    var charging: Bool = false
    var external: Bool = false
    var status: String {
        guard let percent else { return "Energia externa" }
        if charging { return "Carregando" }
        if external { return percent >= 100 ? "Carga completa" : "Na tomada" }
        return "Na bateria"
    }
    var symbol: String {
        guard let percent else { return "powerplug.fill" }
        if charging { return "battery.100percent.bolt" }
        switch percent { case 0..<13: return "battery.0percent"; case 13..<38: return "battery.25percent"; case 38..<63: return "battery.50percent"; case 63..<88: return "battery.75percent"; default: return "battery.100percent" }
    }
    static func current() -> BatteryReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return BatteryReading() }
        for source in sources {
            guard let raw = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue(),
                  let description = raw as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return BatteryReading(percent: min(100, max(0, current * 100 / maximum)),
                                  charging: description[kIOPSIsChargingKey] as? Bool ?? false,
                                  external: (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return BatteryReading()
    }
}

private struct SystemReading {
    var usedGB: Double
    var totalGB: Double
    var load: Double
    var usedPercent: Int { totalGB > 0 ? min(100, max(0, Int((usedGB / totalGB * 100).rounded()))) : 0 }
    static func current() -> SystemReading {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &size)
            }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let used = result == KERN_SUCCESS ? Double(UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * Double(vm_kernel_page_size) : 0
        var averages = [Double](repeating: 0, count: 3)
        _ = getloadavg(&averages, 3)
        let gb: Double = 1_073_741_824
        return SystemReading(usedGB: used / gb, totalGB: total / gb, load: averages[0])
    }
}

private func timerString(_ seconds: TimeInterval) -> String {
    let value = max(0, Int(seconds))
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
}

private func worldTime(_ date: Date, zone: TimeZone) -> String {
    var format = Date.FormatStyle.dateTime.hour().minute()
    format.timeZone = zone
    return date.formatted(format)
}
