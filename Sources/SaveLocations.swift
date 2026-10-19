import AppKit

/// Dónde se guardan los archivos convertidos.
///
/// Las apps de la Mac App Store viven en un "sandbox": solo pueden escribir donde el
/// usuario les dio permiso. Por eso:
/// - Por defecto lo convertido va a **Descargas** (permiso incluido en la app).
/// - Si el usuario da permiso a una carpeta (por ejemplo su carpeta personal), lo
///   convertido se guarda **junto al original** cuando el original está dentro de ella.
///   El permiso se recuerda con "security-scoped bookmarks".
final class SaveLocations {
    static let shared = SaveLocations()

    private let defaultsKey = "carpetasConPermiso"
    private let lock = NSLock()
    private var folders: [URL] = []

    private init() {
        restore()
    }

    /// Carpetas con permiso, para mostrarlas en Ajustes.
    var authorizedFolders: [URL] {
        lock.lock(); defer { lock.unlock() }
        return folders
    }

    /// Carpeta personal real del usuario (dentro del sandbox, NSHomeDirectory apunta al contenedor).
    static var realHome: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var downloads: URL {
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return url.resolvingSymlinksInPath()
        }
        return realHome.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// Carpeta donde guardar la conversión de `original`.
    func outputFolder(for original: URL) -> URL {
        let parent = original.deletingLastPathComponent()
        let parentPath = parent.resolvingSymlinksInPath().path
        for root in authorizedFolders {
            let rootPath = root.resolvingSymlinksInPath().path
            if rootPath == "/" || parentPath == rootPath || parentPath.hasPrefix(rootPath + "/") {
                return parent
            }
        }
        return Self.downloads
    }

    // MARK: - Dar y quitar permisos

    func add(_ url: URL) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope],
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        _ = url.startAccessingSecurityScopedResource()
        lock.lock()
        folders.removeAll { $0.path == url.path }
        folders.append(url)
        lock.unlock()

        var stored = storedBookmarks().filter { resolve($0)?.path != url.path }
        stored.append(data)
        UserDefaults.standard.set(stored, forKey: defaultsKey)
    }

    func remove(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
        lock.lock()
        folders.removeAll { $0.path == url.path }
        lock.unlock()
        let stored = storedBookmarks().filter { resolve($0)?.path != url.path }
        UserDefaults.standard.set(stored, forKey: defaultsKey)
    }

    /// Pide al usuario una carpeta con el selector de macOS (así es como el sandbox concede permisos).
    @discardableResult
    func askForFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = Self.realHome
        panel.prompt = "Dar permiso"
        panel.message = "Elige la carpeta donde RuedaConvert podrá guardar junto a tus archivos. Tu carpeta personal incluye Escritorio, Documentos y Descargas."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try add(url)
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            return false
        }
    }

    // MARK: - Bookmarks guardados

    private func storedBookmarks() -> [Data] {
        UserDefaults.standard.array(forKey: defaultsKey) as? [Data] ?? []
    }

    private func resolve(_ data: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private func restore() {
        var refreshed: [Data] = []
        for data in storedBookmarks() {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            folders.append(url)
            if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope],
                                                        includingResourceValuesForKeys: nil,
                                                        relativeTo: nil) {
                refreshed.append(fresh)
            } else {
                refreshed.append(data)
            }
        }
        UserDefaults.standard.set(refreshed, forKey: defaultsKey)
    }
}
