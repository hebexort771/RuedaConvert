import AppKit

/// Aviso flotante en la parte inferior de la pantalla ("Convirtiendo…", "Listo", errores).
final class Toast {
    enum Style { case info, progress, success, error }

    private let panel: NSPanel
    private let stack = NSStackView()
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let clickCatcher = ClickCatcher()
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 44),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = Self.roundedMask(radius: 14)
        panel.contentView = blur

        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.preferredMaxLayoutWidth = 440
        label.maximumNumberOfLines = 3

        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        clickCatcher.translatesAutoresizingMaskIntoConstraints = false

        blur.addSubview(stack)
        blur.addSubview(clickCatcher)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            stack.topAnchor.constraint(equalTo: blur.topAnchor),
            stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
            clickCatcher.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            clickCatcher.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            clickCatcher.topAnchor.constraint(equalTo: blur.topAnchor),
            clickCatcher.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
    }

    /// - duration: segundos visible; por defecto 4 (errores 7). "progress" se queda hasta el siguiente aviso.
    func show(_ text: String, style: Style, duration: TimeInterval? = nil, onClick: (() -> Void)? = nil) {
        label.stringValue = text
        let (symbol, tint) = Self.look(for: style)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = tint

        clickCatcher.action = { [weak self] in
            onClick?()
            self?.hide()
        }

        let size = stack.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.minY + 60,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.invalidateShadow()

        hideWork?.cancel()
        let seconds = duration ?? Self.defaultDuration(for: style)
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            self.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
        })
    }

    private static func defaultDuration(for style: Style) -> TimeInterval {
        switch style {
        case .progress: return 120
        case .error: return 7
        default: return 4
        }
    }

    private static func look(for style: Style) -> (String, NSColor) {
        switch style {
        case .info: return ("info.circle.fill", .controlAccentColor)
        case .progress: return ("hourglass", .systemOrange)
        case .success: return ("checkmark.circle.fill", .systemGreen)
        case .error: return ("exclamationmark.triangle.fill", .systemRed)
        }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Capa invisible que recibe el clic aunque la app no esté activa.
final class ClickCatcher: NSView {
    var action: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { action?() }
}
