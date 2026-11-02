import AppKit

/// Shows the frozen screenshot of one display and handles selecting, moving,
/// resizing and annotating the capture area.
final class OverlayView: NSView, NSTextFieldDelegate {
    private enum Handle: CaseIterable {
        case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left
    }

    private enum Interaction {
        case idle
        case creating(start: CGPoint)
        case moving(original: NSRect, start: CGPoint)
        case resizing(Handle, original: NSRect, start: CGPoint)
        case drawing
    }

    private let image: CGImage
    private unowned let session: CaptureSession

    private var selection: NSRect? { didSet { selectionChanged() } }
    private var annotations: [Annotation] = []
    private var current: Annotation?
    private var interaction = Interaction.idle
    private var textField: NSTextField?
    private var mouseInside = false
    private var widthHint: (text: String, until: Date)?

    private var toolButtons: [Tool: ToolButton] = [:]
    private var colorButton: ToolButton!
    private var palette: ToolbarView!
    private var actionBar: ToolbarView!

    private static let handleSize: CGFloat = 8
    private static let gap: CGFloat = 6

    init(image: CGImage, session: CaptureSession) {
        self.image = image
        self.session = session
        super.init(frame: .zero)
        buildToolbars()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if let window {
            mouseInside = window.frame.contains(NSEvent.mouseLocation)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    // MARK: - Toolbars

    private func buildToolbars() {
        var toolItems: [ToolButton] = Tool.allCases.map { tool in
            let button = ToolButton(symbol: tool.symbolName, tooltip: tool.title) { [unowned self] _ in
                commitText()
                session.tool = session.tool == tool ? nil : tool
            }
            toolButtons[tool] = button
            return button
        }
        colorButton = ToolButton(symbol: "circle.fill", tooltip: "Color") { [unowned self] button in
            showColorMenu(from: button)
        }
        toolItems.append(colorButton)
        toolItems.append(ToolButton(symbol: "arrow.uturn.backward", tooltip: "Undo (⌘Z)") { [unowned self] _ in undo() })

        let actions = [
            ToolButton(symbol: "doc.on.doc", tooltip: "Copy (⌘C)") { [unowned self] _ in copyShot() },
            ToolButton(symbol: "square.and.arrow.down", tooltip: "Save (⌘S)") { [unowned self] _ in saveShot() },
            ToolButton(symbol: "xmark", tooltip: "Close (Esc)") { [unowned self] _ in session.close() },
        ]

        palette = ToolbarView(vertical: true, buttons: toolItems)
        actionBar = ToolbarView(vertical: false, buttons: actions)
        palette.isHidden = true
        actionBar.isHidden = true
        addSubview(palette)
        addSubview(actionBar)
        toolStateChanged()
    }

    func toolStateChanged() {
        for (tool, button) in toolButtons { button.isSelected = session.tool == tool }
        colorButton.symbolColor = session.color
        window?.invalidateCursorRects(for: self)
        updateCursor()
    }

    private func showColorMenu(from button: ToolButton) {
        let menu = NSMenu()
        for (name, color) in CaptureSession.palette {
            let item = NSMenuItem(title: name, action: #selector(pickColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = color
            item.state = color == session.color ? .on : .off
            item.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                color.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                NSColor.gray.setStroke()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).stroke()
                return true
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.maxX + 4, y: button.bounds.maxY), in: button)
    }

    @objc private func pickColor(_ item: NSMenuItem) {
        guard let color = item.representedObject as? NSColor else { return }
        session.color = color
        if let textField {
            textField.textColor = color
            (textField.currentEditor() as? NSTextView)?.insertionPointColor = color
        }
    }

    private func layoutToolbars() {
        let toolbarsVisible: Bool
        if case .idle = interaction, selection != nil { toolbarsVisible = true } else { toolbarsVisible = false }
        palette.isHidden = !toolbarsVisible
        actionBar.isHidden = !toolbarsVisible
        guard toolbarsVisible, let sel = selection else { return }

        let gap = Self.gap, margin: CGFloat = 4
        let p = palette.frame.size, a = actionBar.frame.size

        // Action bar: under the selection, right-aligned. Flip above, then inside, when out of room.
        var actionInside = false
        var ay = sel.minY - gap - a.height
        if ay < margin {
            ay = sel.maxY + gap
            if ay + a.height > bounds.maxY - margin {
                ay = sel.minY + gap
                actionInside = true
            }
        }
        let ax = clamp(sel.maxX - a.width, margin, bounds.maxX - a.width - margin)
        actionBar.frame.origin = NSPoint(x: ax, y: ay)

        // Tool palette: right of the selection, bottom-aligned. Flip left, then inside.
        var px = sel.maxX + gap
        var paletteInside = false
        if px + p.width > bounds.maxX - margin {
            px = sel.minX - gap - p.width
            if px < margin {
                px = sel.maxX - gap - p.width
                paletteInside = true
            }
        }
        var py = sel.minY
        if paletteInside && actionInside { py += a.height + gap * 2 }
        py = clamp(py, margin, bounds.maxY - p.height - margin)
        palette.frame.origin = NSPoint(x: px, y: py)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds)

        let dim = NSColor.black.withAlphaComponent(0.45)
        guard let sel = selection else {
            dim.setFill()
            bounds.fill()
            if mouseInside { drawHint() }
            return
        }

        let shade = NSBezierPath(rect: bounds)
        shade.appendRect(sel)
        shade.windingRule = .evenOdd
        dim.setFill()
        shade.fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: sel).setClip()
        annotations.forEach { $0.draw() }
        current?.draw()
        NSGraphicsContext.restoreGraphicsState()

        drawSelectionFrame(sel)
        drawSizeLabel(for: sel)
        if let hint = widthHint, hint.until > Date() { drawBadge(hint.text, centeredAt: NSPoint(x: sel.midX, y: sel.midY)) }
    }

    private func drawSelectionFrame(_ sel: NSRect) {
        let frame = NSBezierPath(rect: sel.insetBy(dx: -0.5, dy: -0.5))
        frame.lineWidth = 1
        NSColor.white.setStroke()
        frame.stroke()
        frame.setLineDash([4, 4], count: 2, phase: 0)
        NSColor.black.withAlphaComponent(0.7).setStroke()
        frame.stroke()

        guard case .idle = interaction else { return }
        for handle in Handle.allCases {
            let rect = handleRect(handle, in: sel)
            NSColor.white.setFill()
            NSBezierPath(rect: rect).fill()
            NSColor.black.withAlphaComponent(0.6).setStroke()
            NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
    }

    private func drawSizeLabel(for sel: NSRect) {
        let px = pixelRect(for: sel)
        let text = "\(Int(px.width)) × \(Int(px.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = NSSize(width: size.width + 10, height: size.height + 4)
        var origin = NSPoint(x: sel.minX, y: sel.maxY + 4)
        if origin.y + box.height > bounds.maxY { origin.y = sel.maxY - box.height - 4; origin.x += 4 }
        let rect = NSRect(origin: origin, size: box)
        NSColor(white: 0, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 5, y: rect.minY + 2), withAttributes: attributes)
    }

    private func drawHint() {
        drawBadge("Drag to select an area  ·  Click for full screen  ·  Esc to cancel",
                  centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
    }

    private func drawBadge(_ text: String, centeredAt center: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(x: center.x - size.width / 2 - 14, y: center.y - size.height / 2 - 8,
                          width: size.width + 28, height: size.height + 16)
        NSColor(white: 0.1, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 14, y: rect.minY + 8), withAttributes: attributes)
    }

    // MARK: - Geometry

    private var scale: CGFloat { bounds.width > 0 ? CGFloat(image.width) / bounds.width : 1 }

    /// The selection snapped to whole image pixels (top-left origin, as CGImage expects).
    private func pixelRect(for sel: NSRect) -> CGRect {
        let s = scale
        let minX = (sel.minX * s).rounded(), maxX = (sel.maxX * s).rounded()
        let minY = ((bounds.height - sel.maxY) * s).rounded(), maxY = ((bounds.height - sel.minY) * s).rounded()
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func handleRect(_ handle: Handle, in sel: NSRect) -> NSRect {
        let center: NSPoint
        switch handle {
        case .bottomLeft: center = NSPoint(x: sel.minX, y: sel.minY)
        case .bottom: center = NSPoint(x: sel.midX, y: sel.minY)
        case .bottomRight: center = NSPoint(x: sel.maxX, y: sel.minY)
        case .right: center = NSPoint(x: sel.maxX, y: sel.midY)
        case .topRight: center = NSPoint(x: sel.maxX, y: sel.maxY)
        case .top: center = NSPoint(x: sel.midX, y: sel.maxY)
        case .topLeft: center = NSPoint(x: sel.minX, y: sel.maxY)
        case .left: center = NSPoint(x: sel.minX, y: sel.midY)
        }
        let size = Self.handleSize
        return NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }

    private func handle(at point: NSPoint) -> Handle? {
        guard let sel = selection else { return nil }
        return Handle.allCases.first { handleRect($0, in: sel).insetBy(dx: -4, dy: -4).contains(point) }
    }

    private func resized(_ rect: NSRect, _ handle: Handle, by delta: CGVector) -> NSRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch handle {
        case .left, .topLeft, .bottomLeft: minX += delta.dx
        case .right, .topRight, .bottomRight: maxX += delta.dx
        default: break
        }
        switch handle {
        case .bottom, .bottomLeft, .bottomRight: minY += delta.dy
        case .top, .topLeft, .topRight: maxY += delta.dy
        default: break
        }
        return NSRect(corner: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY)).intersection(bounds)
    }

    private func clampedPoint(_ p: NSPoint) -> NSPoint {
        NSPoint(x: clamp(p.x, bounds.minX, bounds.maxX), y: clamp(p.y, bounds.minY, bounds.maxY))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hadText = textField != nil
        commitText()

        if let sel = selection {
            if let handle = handle(at: point) {
                interaction = .resizing(handle, original: sel, start: point)
                return redraw()
            }
            if sel.contains(point) {
                if event.clickCount == 2 && session.tool == nil { return copyShot() }
                switch session.tool {
                case .text?:
                    if !hadText { beginText(at: point) }
                case let tool?:
                    current = Annotation(tool: tool, color: session.color, lineWidth: session.lineWidth, points: [point, point])
                    interaction = .drawing
                case nil:
                    interaction = .moving(original: sel, start: point)
                }
                return redraw()
            }
            // Keep annotated work safe from a stray click outside the selection.
            if !annotations.isEmpty { return }
        }

        session.selectionStarted(in: self)
        selection = nil
        interaction = .creating(start: clampedPoint(point))
        redraw()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let shift = event.modifierFlags.contains(.shift)

        switch interaction {
        case .creating(let start):
            var end = clampedPoint(point)
            if shift { end = clampedPoint(constrained(end, from: start, tool: .rectangle)) }
            selection = NSRect(corner: start, to: end)
        case .moving(let original, let start):
            var moved = original.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            moved.origin.x = clamp(moved.origin.x, bounds.minX, bounds.maxX - moved.width)
            moved.origin.y = clamp(moved.origin.y, bounds.minY, bounds.maxY - moved.height)
            selection = moved
        case .resizing(let handle, let original, let start):
            selection = resized(original, handle, by: CGVector(dx: point.x - start.x, dy: point.y - start.y))
        case .drawing:
            guard var annotation = current else { return }
            if annotation.tool.isFreehand {
                annotation.points.append(point)
            } else {
                annotation.points[1] = shift ? constrained(point, from: annotation.start, tool: annotation.tool) : point
            }
            current = annotation
        case .idle:
            return
        }
        redraw()
    }

    override func mouseUp(with event: NSEvent) {
        switch interaction {
        case .creating:
            // A click without a drag grabs the whole display.
            if let sel = selection, sel.width >= 3, sel.height >= 3 { break }
            selection = bounds
        case .drawing:
            if let current, current.isMeaningful { annotations.append(current) }
            current = nil
        default:
            break
        }
        if let sel = selection, sel.width < 1 || sel.height < 1 { selection = nil }
        interaction = .idle
        redraw()
        updateCursor()
    }

    override func rightMouseDown(with event: NSEvent) {
        // Right-click cancels, matching the Windows Lightshot habit.
        session.close()
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.5, selection != nil else { return }
        // Trackpads send many small deltas; mouse wheels send one per notch.
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.25 : 1
        session.lineWidth = clamp(session.lineWidth + (delta > 0 ? step : -step), 1, 20)
        let size = Int(session.lineWidth.rounded())
        widthHint = ("Line width: \(size)", Date().addingTimeInterval(0.8))
        if let textField { textField.font = Annotation.font(forLineWidth: session.lineWidth); fitTextField(textField) }
        redraw()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in self?.redraw() }
    }

    override func mouseMoved(with event: NSEvent) {
        if !mouseInside { mouseInside = true; redraw() }
        updateCursor()
    }

    override func mouseEntered(with event: NSEvent) {
        mouseInside = true
        redraw()
    }

    override func mouseExited(with event: NSEvent) {
        mouseInside = false
        redraw()
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor() }

    private func updateCursor() {
        guard let window, case .idle = interaction else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if palette.frame.contains(point) && !palette.isHidden || actionBar.frame.contains(point) && !actionBar.isHidden {
            NSCursor.arrow.set()
        } else if let handle = handle(at: point) {
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            default: NSCursor.crosshair.set()
            }
        } else if let sel = selection, sel.contains(point) {
            switch session.tool {
            case .text?: NSCursor.iBeam.set()
            case _?: NSCursor.crosshair.set()
            case nil: NSCursor.openHand.set()
            }
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleKey(event) || super.performKeyEquivalent(with: event)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch (event.keyCode, command, event.charactersIgnoringModifiers?.lowercased()) {
        case (53, _, _): // Esc
            if textField != nil { commitText() } else { session.close() }
        case (36, false, _), (76, false, _): // Return / Enter
            guard textField == nil else { return false }
            copyShot()
        case (_, true, "c"): copyShot()
        case (_, true, "s"): saveShot()
        case (_, true, "z"): undo()
        case (_, true, "a"):
            guard textField == nil else { return false }
            session.selectionStarted(in: self)
            selection = bounds
        default:
            return false
        }
        return true
    }

    // MARK: - Text tool

    private func beginText(at point: NSPoint) {
        let field = NSTextField(string: "")
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Annotation.font(forLineWidth: session.lineWidth)
        field.textColor = session.color
        field.delegate = self
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        addSubview(field)
        textField = field
        fitTextField(field, anchor: point)
        window?.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = session.color
    }

    /// Grows the field with its text, keeping its left edge and vertical centre fixed.
    private func fitTextField(_ field: NSTextField, anchor: NSPoint? = nil) {
        let font = field.font ?? Annotation.font(forLineWidth: session.lineWidth)
        let text = field.stringValue.isEmpty ? " " : field.stringValue
        let size = (text as NSString).size(withAttributes: [.font: font])
        let height = ceil(font.ascender - font.descender + font.leading) + 2
        let width = ceil(size.width) + Annotation.textInset * 2 + 12
        let midY = anchor?.y ?? field.frame.midY
        let minX = anchor?.x ?? field.frame.minX
        field.frame = NSRect(x: minX, y: midY - height / 2, width: width, height: height)
    }

    func controlTextDidChange(_ notification: Notification) {
        if let textField { fitTextField(textField) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
            commitText()
            return true
        }
        return false
    }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue
        if !text.isEmpty {
            var annotation = Annotation(tool: .text, color: field.textColor ?? session.color,
                                        lineWidth: session.lineWidth, points: [field.frame.origin])
            annotation.text = text
            annotation.font = field.font ?? Annotation.font(forLineWidth: session.lineWidth)
            annotation.textFrame = field.frame
            annotations.append(annotation)
        }
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        redraw()
    }

    // MARK: - Actions

    func clearSelection() {
        commitText()
        annotations.removeAll()
        selection = nil
        redraw()
    }

    private func undo() {
        if let textField {
            self.textField = nil
            textField.removeFromSuperview()
            window?.makeFirstResponder(self)
        } else if !annotations.isEmpty {
            annotations.removeLast()
        }
        redraw()
    }

    private func copyShot() {
        commitText()
        guard let shot = render() else { return NSSound.beep() }
        session.copy(shot)
    }

    private func saveShot() {
        commitText()
        guard let shot = render() else { return NSSound.beep() }
        session.save(shot, from: window)
    }

    /// Burns the annotations into the selected part of the full-resolution capture.
    func render() -> RenderedShot? {
        guard let sel = selection else { return nil }
        let px = pixelRect(for: sel)
        let s = scale
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: Int(px.width), height: Int(px.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .none
        // Map view points onto the cropped pixel grid.
        context.scaleBy(x: s, y: s)
        context.translateBy(x: -px.minX / s, y: -(bounds.height - px.maxY / s))
        context.draw(image, in: bounds)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        annotations.forEach { $0.draw() }
        NSGraphicsContext.restoreGraphicsState()

        guard let output = context.makeImage() else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: output)
        // Like macOS screenshots: Retina captures open at their on-screen size.
        bitmap.size = NSSize(width: px.width / s, height: px.height / s)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return RenderedShot(bitmap: bitmap, png: png)
    }

    private func selectionChanged() {
        layoutToolbars()
        window?.invalidateCursorRects(for: self)
    }

    private func redraw() {
        layoutToolbars()
        needsDisplay = true
    }
}

func clamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T {
    min(max(value, low), max(low, high))
}
