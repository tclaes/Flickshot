import AppKit

/// A dark floating strip of icon buttons, like Lightshot's tool palette and action bar.
final class ToolbarView: NSView {
    static let buttonSize: CGFloat = 30
    static let padding: CGFloat = 4

    let vertical: Bool
    let buttons: [ToolButton]

    init(vertical: Bool, buttons: [ToolButton]) {
        self.vertical = vertical
        self.buttons = buttons
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.13, alpha: 0.94).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(white: 1, alpha: 0.15).cgColor
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.5)
            s.shadowBlurRadius = 8
            s.shadowOffset = NSSize(width: 0, height: -2)
            return s
        }()
        buttons.forEach(addSubview)
        setFrameSize(fittingSize)
        layoutButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var fittingSize: NSSize {
        let count = CGFloat(buttons.count)
        let long = count * Self.buttonSize + 2 * Self.padding
        let short = Self.buttonSize + 2 * Self.padding
        return vertical ? NSSize(width: short, height: long) : NSSize(width: long, height: short)
    }

    private func layoutButtons() {
        for (index, button) in buttons.enumerated() {
            let offset = Self.padding + CGFloat(index) * Self.buttonSize
            button.frame = vertical
                // Top-to-bottom order in an unflipped view.
                ? NSRect(x: Self.padding, y: fittingSize.height - offset - Self.buttonSize, width: Self.buttonSize, height: Self.buttonSize)
                : NSRect(x: offset, y: Self.padding, width: Self.buttonSize, height: Self.buttonSize)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

final class ToolButton: NSView {
    var symbolName: String { didSet { needsDisplay = true } }
    var isSelected = false { didSet { needsDisplay = true } }
    /// When set, the icon is drawn in this color (used by the colour picker button).
    var symbolColor: NSColor? { didSet { needsDisplay = true } }
    var action: (ToolButton) -> Void

    private var isPressed = false { didSet { needsDisplay = true } }

    init(symbol: String, tooltip: String, action: @escaping (ToolButton) -> Void) {
        self.symbolName = symbol
        self.action = action
        super.init(frame: .zero)
        toolTip = tooltip
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseDragged(with event: NSEvent) {
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside { action(self) }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected || isPressed {
            (isSelected ? NSColor.controlAccentColor : NSColor(white: 1, alpha: 0.18)).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5).fill()
        }

        let tint = symbolColor ?? .white
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(config) else { return }
        let size = image.size
        image.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                              width: size.width, height: size.height))
    }
}
