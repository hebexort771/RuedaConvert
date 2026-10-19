import AppKit

/// App de la barra de menú: vigila los arrastres de archivos y, si pulsas Shift
/// mientras arrastras, muestra la rueda de formatos bajo el cursor.
@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // sin icono en el Dock
        withExtendedLifetime(delegate) { app.run() }
    }

    private var statusItem: NSStatusItem!
    private let wheel = Wheel()
    private let toast = Toast()
    private let settings = SettingsWindow()
    private let dragPasteboard = NSPasteboard(name: .drag)

    /// changeCount del portapapeles de arrastre la última vez que el ratón estaba suelto.
    /// Si cambia mientras el botón está pulsado, hay un arrastre en curso.
    private var baselineChangeCount = 0
    /// Arrastre que ya revisamos y no tenía archivos convertibles (para no releerlo 25 veces/seg).
    private var rejectedChangeCount = -1
    private var pollTimer: Timer?
    private var eventMonitor: Any?
    private var hidePending = false
    private var lastOutputs: [URL] = []
    private let workQueue = DispatchQueue(label: "ruedaconvert.conversiones", qos: .userInitiated)

    private var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "pausado") }
        set { UserDefaults.standard.set(!newValue, forKey: "pausado") }
    }

    // MARK: - Arranque

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        baselineChangeCount = dragPasteboard.changeCount

        wheel.view.onDrop = { [weak self] format, urls in
            self?.convert(urls, to: format)
        }
        wheel.view.onFinish = { [weak self] in
            self?.wheel.hide()
        }

        // Solo escuchamos el ratón: no hace falta dar permisos de Accesibilidad.
        // Shift se lee con NSEvent.modifierFlags mientras el botón está pulsado.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged]
        ) { [weak self] _ in
            self?.handleGlobalEvent()
        }

        if !UserDefaults.standard.bool(forKey: "bienvenida") {
            UserDefaults.standard.set(true, forKey: "bienvenida")
            settings.show()
        }
    }

    /// Si la app ya está abierta y el usuario la vuelve a abrir (Aplicaciones, Launchpad,
    /// Spotlight), mostramos los ajustes para que vea que está funcionando.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    // MARK: - Detección de "arrastrar + Shift"

    private var isMouseDown: Bool { (NSEvent.pressedMouseButtons & 1) != 0 }

    private func handleGlobalEvent() {
        if isMouseDown { startPolling() }
        check()
    }

    /// Mientras el botón está pulsado revisamos 25 veces por segundo: así detectamos
    /// Shift aunque el ratón esté quieto y sabemos cuándo se suelta el arrastre.
    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.04, target: self, selector: #selector(pollTick),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func pollTick() { check() }

    private func check() {
        guard isMouseDown else {
            baselineChangeCount = dragPasteboard.changeCount
            if wheel.isVisible { scheduleHide() } else { stopPolling() }
            return
        }

        let changeCount = dragPasteboard.changeCount
        guard isEnabled,
              !wheel.isVisible,
              changeCount != baselineChangeCount,      // hay un arrastre en curso
              changeCount != rejectedChangeCount,
              NSEvent.modifierFlags.contains(.shift)
        else { return }

        let urls = Self.fileURLs(in: dragPasteboard)
        let formats = Converter.targetFormats(for: urls)
        guard !formats.isEmpty else {
            rejectedChangeCount = changeCount
            return
        }
        wheel.show(formats: formats, at: NSEvent.mouseLocation)
    }

    /// Al soltar esperamos un poco antes de ocultar la rueda para que el
    /// "drop" llegue a la rueda si se soltó encima de ella.
    private func scheduleHide() {
        guard !hidePending else { return }
        hidePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.hidePending = false
            if !self.isMouseDown { self.wheel.hide() }
        }
    }

    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true])
        return (objects as? [URL]) ?? []
    }

    // MARK: - Conversión

    private func convert(_ urls: [URL], to format: OutputFormat) {
        let files = urls.filter { Converter.canConvert($0, to: format) }
        guard !files.isEmpty else {
            toast.show("Esos archivos no se pueden convertir a \(format.label).", style: .error)
            return
        }
        let what = files.count == 1 ? files[0].lastPathComponent : "\(files.count) archivos"
        toast.show("Convirtiendo \(what) a \(format.label)…", style: .progress)

        workQueue.async { [weak self] in
            var outputs: [URL] = []
            var failures: [(URL, Error)] = []
            for file in files {
                do { outputs += try Converter.convert(file, to: format) }
                catch { failures.append((file, error)) }
            }
            let done = outputs
            let failed = failures
            DispatchQueue.main.async {
                self?.finish(outputs: done, failures: failed)
            }
        }
    }

    private func finish(outputs: [URL], failures: [(URL, Error)]) {
        if !outputs.isEmpty { lastOutputs = outputs }
        let reveal: (() -> Void)? = outputs.isEmpty ? nil : { [weak self] in self?.revealLastOutputs() }

        if let failure = failures.first {
            var message = "\(failure.0.lastPathComponent): \(failure.1.localizedDescription)"
            if !outputs.isEmpty {
                message = "\(outputs.count) listo(s), \(failures.count) con error. " + message
            }
            toast.show(message, style: .error, onClick: reveal)
            NSSound.beep()
        } else {
            let name = outputs.count == 1 ? outputs[0].lastPathComponent : "\(outputs.count) archivos"
            let folder = FileManager.default.displayName(atPath: outputs[0].deletingLastPathComponent().path)
            toast.show("Listo en \(folder): \(name) — clic para verlo", style: .success, onClick: reveal)
            NSSound(named: NSSound.Name("Pop"))?.play()
        }
    }

    @objc private func revealLastOutputs() {
        guard !lastOutputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(lastOutputs)
    }

    // MARK: - Menú de la barra

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.circle",
                                accessibilityDescription: "RuedaConvert")
            image?.isTemplate = true
            button.image = image
            if image == nil { button.title = "⇄" }
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let hint = NSMenuItem(title: "Arrastra un archivo y pulsa ⇧ Shift", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        addItem(to: menu, "Activado", #selector(toggleEnabled), on: isEnabled)
        addItem(to: menu, "Mostrar última conversión",
                lastOutputs.isEmpty ? nil : #selector(revealLastOutputs))
        menu.addItem(.separator())

        let settingsItem = addItem(to: menu, "Ajustes…", #selector(openSettings))
        settingsItem.keyEquivalent = ","

        menu.addItem(withTitle: "Salir de RuedaConvert",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector?, on: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        menu.addItem(item)
        return item
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        if !isEnabled { wheel.hide() }
    }

    @objc private func openSettings() {
        settings.show()
    }
}
