import AppKit
import ServiceManagement
import SwiftUI

/// Ventana de bienvenida y ajustes. Se abre la primera vez, desde el menú "Ajustes…"
/// y cuando el usuario vuelve a abrir la app desde Aplicaciones o Launchpad.
final class SettingsWindow {
    private var window: NSWindow?
    private let model = SettingsModel()

    func show() {
        model.refresh()
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model) { [weak self] in
                self?.window?.close()
            })
            let window = NSWindow(contentViewController: hosting)
            window.title = "RuedaConvert"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsModel: ObservableObject {
    @Published var folders: [URL] = []
    @Published var launchAtLogin = false

    func refresh() {
        folders = SaveLocations.shared.authorizedFolders
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func addFolder() {
        SaveLocations.shared.askForFolder()
        refresh()
    }

    func remove(_ url: URL) {
        SaveLocations.shared.remove(url)
        refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        refresh()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("RuedaConvert").font(.title2.bold())
                    Text("Convierte archivos con solo arrastrarlos.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Cómo se usa") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Empieza a arrastrar un archivo desde Finder o el Escritorio.", systemImage: "hand.draw")
                    Label("Sin soltarlo, pulsa Shift: aparece la rueda.", systemImage: "shift")
                    Label("Suéltalo sobre el formato que quieras. El centro cancela.", systemImage: "circle.circle")
                    Label("RuedaConvert vive en la barra de menú, arriba a la derecha.", systemImage: "menubar.rectangle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox("Dónde se guardan los archivos") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Por defecto, en tu carpeta Descargas. Si das permiso a una carpeta, lo convertido se guarda junto al archivo original cuando esté dentro de ella.")
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(model.folders, id: \.self) { url in
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(.secondary)
                            Text(url.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Quitar") { model.remove(url) }
                        }
                    }

                    Button("Dar permiso a una carpeta…") { model.addFolder() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            Toggle("Abrir RuedaConvert al iniciar sesión", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            HStack {
                Text("Todo se convierte en tu Mac. Ningún archivo sale de tu equipo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Listo", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}
