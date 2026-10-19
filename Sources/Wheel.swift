import AppKit

/// Ventana flotante y transparente que contiene la rueda.
final class Wheel {
    let view: WheelView
    private let panel: NSPanel
    private static let side: CGFloat = 320

    init() {
        let rect = NSRect(x: 0, y: 0, width: Self.side, height: Self.side)
        view = WheelView(frame: rect)
        panel = NSPanel(contentRect: rect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        // Fondo difuminado (efecto vidrio) recortado en círculo.
        let blur = NSVisualEffectView(frame: rect)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        let radius = view.plateRadius
        blur.maskImage = NSImage(size: rect.size, flipped: false) { bounds in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.midX - radius, y: bounds.midY - radius,
                                        width: radius * 2, height: radius * 2)).fill()
            return true
        }

        let container = NSView(frame: rect)
        container.addSubview(blur)
        container.addSubview(view)
        panel.contentView = container
    }

    var isVisible: Bool { panel.isVisible }

    func show(formats: [OutputFormat], at point: NSPoint) {
        view.configure(formats: formats)

        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - Self.side / 2, y: point.y - Self.side / 2)
        if let frame = screen?.frame {
            origin.x = min(max(origin.x, frame.minX), frame.maxX - Self.side)
            origin.y = min(max(origin.y, frame.minY), frame.maxY - Self.side)
        }
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            self.panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        view.reset()
    }
}

enum WheelHover: Equatable {
    case outside
    case cancel
    case option(Int)
}

/// Dibuja la rueda y recibe el archivo soltado encima.
/// La opción 0 va arriba y las demás siguen en sentido horario. El centro cancela.
final class WheelView: NSView {
    var onDrop: ((OutputFormat, [URL]) -> Void)?
    var onFinish: (() -> Void)?

    let plateRadius: CGFloat = 150
    private let outerRadius: CGFloat = 140
    private let innerRadius: CGFloat = 66
    private let centerRadius: CGFloat = 52
    private let pad: CGFloat = 4          // redondeo de las esquinas de cada segmento

    private var formats: [OutputFormat] = []
    private var hover: WheelHover = .outside {
        didSet { if hover != oldValue { needsDisplay = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) no se usa")
    }

    func configure(formats: [OutputFormat]) {
        self.formats = formats
        hover = .outside
        needsDisplay = true
    }

    func reset() { hover = .outside }

    // MARK: Geometría

    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
    private var step: CGFloat { 360 / CGFloat(max(formats.count, 1)) }

    /// Ángulo (grados, sentido antihorario desde la derecha) del centro del segmento i.
    private func midAngle(_ i: Int) -> CGFloat { 90 - CGFloat(i) * step }

    private func hoverTarget(at point: CGPoint) -> WheelHover {
        let dx = point.x - center.x, dy = point.y - center.y
        let distance = hypot(dx, dy)
        if distance <= innerRadius - pad { return .cancel }
        guard distance <= plateRadius, !formats.isEmpty else { return .outside }

        var angle = 90 - atan2(dy, dx) * 180 / .pi      // horario desde arriba
        angle += step / 2
        angle = angle.truncatingRemainder(dividingBy: 360)
        if angle < 0 { angle += 360 }
        return .option(min(Int(angle / step), formats.count - 1))
    }

    private func segmentPath(_ i: Int) -> NSBezierPath {
        let mid = midAngle(i)
        let half = step / 2
        let rOut = outerRadius - pad
        let rIn = innerRadius + pad
        let gap: CGFloat = 3
        let aOut = (pad + gap) / rOut * 180 / .pi
        let aIn = (pad + gap) / rIn * 180 / .pi

        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: rOut,
                       startAngle: mid + half - aOut, endAngle: mid - half + aOut, clockwise: true)
        path.appendArc(withCenter: center, radius: rIn,
                       startAngle: mid - half + aIn, endAngle: mid + half - aIn, clockwise: false)
        path.close()
        path.lineWidth = pad * 2
        path.lineJoinStyle = .round
        return path
    }

    private func circle(_ radius: CGFloat) -> NSRect {
        NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    // MARK: Dibujo

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let plate = NSBezierPath(ovalIn: circle(plateRadius - 0.5))
        (dark ? NSColor(white: 0.05, alpha: 0.35) : NSColor(white: 1, alpha: 0.25)).setFill()
        plate.fill()
        NSColor(white: 1, alpha: dark ? 0.18 : 0.7).setStroke()
        plate.lineWidth = 1
        plate.stroke()

        for (i, format) in formats.enumerated() {
            let hot = hover == .option(i)
            let fill: NSColor = hot
                ? .systemOrange
                : (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 1, alpha: 0.72))
            let path = segmentPath(i)
            fill.setFill()
            fill.setStroke()
            path.fill()
            path.stroke()   // el trazo del mismo color redondea las esquinas

            let labelRadius = (innerRadius + outerRadius) / 2
            let radians = midAngle(i) * .pi / 180
            let point = CGPoint(x: center.x + labelRadius * cos(radians),
                                y: center.y + labelRadius * sin(radians))
            let color: NSColor = hot ? .white : (dark ? .white : NSColor(white: 0.15, alpha: 1))
            drawLabel(format.label, subtitle: format.subtitle, at: point, color: color)
        }

        let cancelHot = hover == .cancel
        let centerFill: NSColor = cancelHot
            ? NSColor.systemRed.withAlphaComponent(0.85)
            : (dark ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 1, alpha: 0.5))
        centerFill.setFill()
        NSBezierPath(ovalIn: circle(centerRadius)).fill()
        let centerColor: NSColor = cancelHot ? .white : (dark ? NSColor(white: 1, alpha: 0.7) : NSColor(white: 0.25, alpha: 1))
        drawLabel("✕", subtitle: "Cancelar", at: center, color: centerColor, size: 17)
    }

    private func drawLabel(_ title: String, subtitle: String?, at point: CGPoint,
                           color: NSColor, size: CGFloat = 16) {
        let titleString = NSAttributedString(string: title, attributes: [
            .font: Self.roundedFont(size, .bold), .foregroundColor: color])
        let titleSize = titleString.size()

        var subString: NSAttributedString?
        var total = titleSize.height
        if let subtitle {
            let s = NSAttributedString(string: subtitle, attributes: [
                .font: Self.roundedFont(10, .medium), .foregroundColor: color.withAlphaComponent(0.75)])
            total += s.size().height - 2
            subString = s
        }

        var y = point.y + total / 2 - titleSize.height
        titleString.draw(at: CGPoint(x: point.x - titleSize.width / 2, y: y))
        if let subString {
            let subSize = subString.size()
            y -= subSize.height - 2
            subString.draw(at: CGPoint(x: point.x - subSize.width / 2, y: y))
        }
    }

    static func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }

    // MARK: Recibir el archivo soltado

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateHover(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateHover(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) { hover = .outside }

    private func updateHover(_ sender: NSDraggingInfo) -> NSDragOperation {
        let newHover = hoverTarget(at: convert(sender.draggingLocation, from: nil))
        if newHover != hover, case .option = newHover {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        hover = newHover
        if case .option = hover { return .copy }
        return []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if case .option = hover { return true }
        return false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard case .option(let index) = hover, index < formats.count else { return false }
        let urls = AppDelegate.fileURLs(in: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDrop?(formats[index], urls)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onFinish?()
    }
}
