import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

enum OutputFormat: String {
    case pdf, docx, txt, rtf, html, png, jpg, heic

    var label: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }

    var subtitle: String {
        switch self {
        case .pdf: return "Documento"
        case .docx: return "Word"
        case .txt: return "Texto"
        case .rtf: return "Enriquecido"
        case .html: return "Web"
        case .png: return "Imagen"
        case .jpg: return "Foto"
        case .heic: return "Compacta"
        }
    }
}

enum InputKind {
    case pdf, image, document
}

struct ConversionError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Todas las conversiones usan frameworks de macOS (PDFKit, ImageIO, Vision, AppKit):
/// no hace falta instalar nada ni se sube ningún archivo a internet.
enum Converter {

    // MARK: - Qué se puede convertir en qué

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]
    private static let plainTextExtensions: Set<String> = ["txt", "text", "md", "markdown"]
    private static let documentExtensions: Set<String> = ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm"]

    static func kind(of url: URL) -> InputKind? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if imageExtensions.contains(ext) { return .image }
        if documentExtensions.contains(ext) || plainTextExtensions.contains(ext) { return .document }
        return nil
    }

    static func currentFormat(of url: URL) -> OutputFormat? {
        switch url.pathExtension.lowercased() {
        case "pdf": return .pdf
        case "docx": return .docx
        case "txt", "text": return .txt
        case "rtf": return .rtf
        case "html", "htm": return .html
        case "png": return .png
        case "jpg", "jpeg": return .jpg
        case "heic", "heif": return .heic
        default: return nil
        }
    }

    /// Orden en la rueda: el primero arriba y luego en sentido horario.
    private static func targets(for kind: InputKind) -> [OutputFormat] {
        switch kind {
        case .pdf: return [.docx, .jpg, .png, .txt]
        case .image: return [.pdf, .jpg, .txt, .png, .heic]
        case .document: return [.pdf, .docx, .txt, .rtf, .html]
        }
    }

    static func targetFormats(for urls: [URL]) -> [OutputFormat] {
        guard let first = urls.first(where: { kind(of: $0) != nil }),
              let firstKind = kind(of: first) else { return [] }
        let own = currentFormat(of: first)
        return targets(for: firstKind).filter { $0 != own }
    }

    static func canConvert(_ url: URL, to format: OutputFormat) -> Bool {
        guard let k = kind(of: url) else { return false }
        return targets(for: k).contains(format) && currentFormat(of: url) != format
    }

    /// Convierte un archivo y devuelve lo creado (junto al original o en Descargas; nunca sobrescribe).
    static func convert(_ url: URL, to format: OutputFormat) throws -> [URL] {
        guard let k = kind(of: url) else { throw ConversionError("Tipo de archivo no compatible") }
        let folder = SaveLocations.shared.outputFolder(for: url)
        let base = url.deletingPathExtension().lastPathComponent

        switch k {
        case .image:
            return [try convertImage(url, to: format, folder: folder, base: base)]
        case .pdf:
            return try convertPDF(url, to: format, folder: folder, base: base)
        case .document:
            // Leer Word/HTML usa AppKit/WebKit, que debe ir en el hilo principal.
            return [try onMain { try convertDocument(url, to: format, folder: folder, base: base) }]
        }
    }

    // MARK: - Imágenes

    private static func convertImage(_ url: URL, to format: OutputFormat, folder: URL, base: String) throws -> URL {
        let image = try loadImage(url)
        let out = uniqueURL(in: folder, base: base, ext: format.fileExtension)

        switch format {
        case .txt:
            let text = try recognizeText(in: image)
            guard !text.isBlank else { throw ConversionError("No encontré texto en la imagen") }
            try text.write(to: out, atomically: true, encoding: .utf8)
        case .pdf:
            try writeImagePDF(image, to: out)
        case .png, .jpg, .heic:
            try writeImage(image, to: out, as: format)
        default:
            throw ConversionError("Conversión no disponible")
        }
        return out
    }

    /// Carga la imagen ya girada según su orientación EXIF (fotos del iPhone, etc.).
    private static func loadImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ConversionError("No pude abrir la imagen")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0

        if max(width, height) > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                kCGImageSourceShouldCacheImmediately: true,
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return image
            }
        }
        if let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { return image }
        throw ConversionError("No pude leer la imagen")
    }

    private static func writeImage(_ image: CGImage, to url: URL, as format: OutputFormat) throws {
        let type: UTType
        switch format {
        case .png: type = .png
        case .jpg: type = .jpeg
        case .heic: type = .heic
        default: throw ConversionError("Formato de imagen no disponible")
        }
        // JPG no admite transparencia: se pone fondo blanco en vez de negro.
        let finalImage = format == .jpg ? (flattenOnWhite(image) ?? image) : image

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError("Este Mac no puede crear archivos \(format.label)")
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImage(destination, finalImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError("No se pudo guardar el \(format.label)")
        }
    }

    private static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let spaces = [image.colorSpace, CGColorSpace(name: CGColorSpace.sRGB)].compactMap { $0 }
        for space in spaces where space.model == .rgb {
            guard let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(rect)
            ctx.draw(image, in: rect)
            return ctx.makeImage()
        }
        return nil
    }

    /// Una página por imagen, del tamaño de la imagen pero sin pasar de A4.
    private static func writeImagePDF(_ image: CGImage, to url: URL) throws {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let landscape = width > height
        let maxW: CGFloat = landscape ? 842 : 595
        let maxH: CGFloat = landscape ? 595 : 842
        let scale = min(1, maxW / width, maxH / height)
        var box = CGRect(x: 0, y: 0, width: width * scale, height: height * scale)

        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw ConversionError("No se pudo crear el PDF")
        }
        ctx.beginPDFPage(nil)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: box)
        ctx.endPDFPage()
        ctx.closePDF()
    }

    /// OCR con Vision (el mismo motor que "Texto en vivo" de macOS).
    private static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let supported = try? request.supportedRecognitionLanguages() {
            let wanted = ["es-ES", "en-US"].filter { supported.contains($0) }
            if !wanted.isEmpty { request.recognitionLanguages = wanted }
        }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    // MARK: - PDF

    private static func convertPDF(_ url: URL, to format: OutputFormat, folder: URL, base: String) throws -> [URL] {
        guard let document = PDFDocument(url: url) else { throw ConversionError("No pude abrir el PDF") }
        if document.isLocked { throw ConversionError("El PDF tiene contraseña") }
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        guard !pages.isEmpty else { throw ConversionError("El PDF no tiene páginas") }

        switch format {
        case .txt:
            let text = pages.map(pageText).joined(separator: "\n\n")
            guard !text.isBlank else { throw ConversionError("No encontré texto en el PDF") }
            let out = uniqueURL(in: folder, base: base, ext: "txt")
            try text.write(to: out, atomically: true, encoding: .utf8)
            return [out]

        case .docx:
            let result = NSMutableAttributedString()
            for (index, page) in pages.enumerated() {
                if index > 0 { result.append(NSAttributedString(string: "\n\n")) }
                if let rich = page.attributedString, !rich.string.isBlank {
                    result.append(rich)
                } else {
                    // Página escaneada: se lee con OCR.
                    let text = (try? recognizeText(in: render(page, scale: 2))) ?? ""
                    result.append(NSAttributedString(string: text, attributes: [
                        .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black]))
                }
            }
            guard !result.string.isBlank else { throw ConversionError("No encontré texto en el PDF") }
            let out = uniqueURL(in: folder, base: base, ext: "docx")
            try onMain { try writeRichText(result, to: out, as: .docx) }
            return [out]

        case .png, .jpg:
            if pages.count == 1 {
                let out = uniqueURL(in: folder, base: base, ext: format.fileExtension)
                try writeImage(render(pages[0], scale: 2), to: out, as: format)
                return [out]
            }
            // Varias páginas: una carpeta con una imagen por página.
            let outFolder = uniqueURL(in: folder, base: "\(base) (\(format.label))", ext: nil)
            try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: false)
            for (index, page) in pages.enumerated() {
                let name = "\(base) - página \(String(format: "%03d", index + 1))"
                let out = outFolder.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
                try writeImage(render(page, scale: 2), to: out, as: format)
            }
            return [outFolder]

        default:
            throw ConversionError("Conversión no disponible")
        }
    }

    private static func pageText(_ page: PDFPage) -> String {
        if let text = page.string, !text.isBlank { return text }
        return (try? recognizeText(in: render(page, scale: 2))) ?? ""
    }

    /// Renderiza una página a imagen (scale 2 ≈ 144 ppp) con fondo blanco y respetando la rotación.
    private static func render(_ page: PDFPage, scale requestedScale: CGFloat) throws -> CGImage {
        guard let cgPage = page.pageRef else { throw ConversionError("Página dañada") }
        let box = cgPage.getBoxRect(.cropBox)
        let rotated = cgPage.rotationAngle % 180 != 0
        let size = CGSize(width: rotated ? box.height : box.width,
                          height: rotated ? box.width : box.height)
        // Límite para pósters gigantes: máximo 8000 px por lado.
        let scale = min(requestedScale, 8000 / max(size.width, size.height, 1))
        let pixelWidth = max(1, Int((size.width * scale).rounded()))
        let pixelHeight = max(1, Int((size.height * scale).rounded()))

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ConversionError("No hay memoria suficiente para la página")
        }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(cgPage.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size),
                                                   rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(cgPage)
        guard let image = ctx.makeImage() else { throw ConversionError("No se pudo dibujar la página") }
        return image
    }

    // MARK: - Documentos (Word, RTF, HTML, ODT, texto)

    private static func convertDocument(_ url: URL, to format: OutputFormat, folder: URL, base: String) throws -> URL {
        let text = try readDocument(url)
        let out = uniqueURL(in: folder, base: base, ext: format.fileExtension)
        switch format {
        case .pdf:
            try writePDF(text, to: out)
        case .txt:
            try text.string.write(to: out, atomically: true, encoding: .utf8)
        case .docx, .rtf, .html:
            try writeRichText(text, to: out, as: format)
        default:
            throw ConversionError("Conversión no disponible")
        }
        return out
    }

    private static func readDocument(_ url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        if plainTextExtensions.contains(ext) {
            let data = try Data(contentsOf: url)
            let string = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
                ?? String(decoding: data, as: UTF8.self)
            return NSAttributedString(string: string, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])
        }
        do {
            return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        } catch {
            throw ConversionError("No pude leer el documento \(ext.uppercased())")
        }
    }

    private static func writeRichText(_ text: NSAttributedString, to url: URL, as format: OutputFormat) throws {
        let type: NSAttributedString.DocumentType
        switch format {
        case .docx: type = .officeOpenXML
        case .rtf: type = .rtf
        case .html: type = .html
        default: throw ConversionError("Formato de texto no disponible")
        }
        let data = try text.data(from: NSRange(location: 0, length: text.length),
                                 documentAttributes: [.documentType: type])
        try data.write(to: url, options: .atomic)
    }

    /// Reparte el texto en páginas A4 con márgenes de 2 cm y lo dibuja en un PDF.
    private static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let margin: CGFloat = 56.7
        var mediaBox = page
        let info: [CFString: Any] = [kCGPDFContextCreator: "RuedaConvert"]
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, info as CFDictionary) else {
            throw ConversionError("No se pudo crear el PDF")
        }

        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let containerSize = CGSize(width: page.width - margin * 2, height: page.height - margin * 2)

        var containers: [NSTextContainer] = []
        while containers.count < 5000 {
            let container = NSTextContainer(size: containerSize)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            let range = layout.glyphRange(for: container)
            if range.length == 0 || NSMaxRange(range) >= layout.numberOfGlyphs { break }
        }

        for container in containers {
            let range = layout.glyphRange(for: container)
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: page.height)    // AppKit dibuja texto con el eje Y invertido
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let origin = CGPoint(x: margin, y: margin)
            layout.drawBackground(forGlyphRange: range, at: origin)
            layout.drawGlyphs(forGlyphRange: range, at: origin)
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    // MARK: - Utilidades

    /// "Informe.pdf" → "Informe.docx"; si ya existe, "Informe 2.docx", "Informe 3.docx"…
    static func uniqueURL(in folder: URL, base: String, ext: String?) -> URL {
        func make(_ name: String) -> URL {
            if let ext { return folder.appendingPathComponent(name).appendingPathExtension(ext) }
            return folder.appendingPathComponent(name, isDirectory: true)
        }
        var url = make(base)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = make("\(base) \(n)")
            n += 1
        }
        return url
    }

    private static func onMain<T>(_ work: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try work() }
        return try DispatchQueue.main.sync(execute: work)
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
