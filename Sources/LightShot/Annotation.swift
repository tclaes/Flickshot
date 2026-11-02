import AppKit

enum Tool: CaseIterable {
    case pen, line, arrow, rectangle, ellipse, marker, text

    var symbolName: String {
        switch self {
        case .pen: "pencil"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .marker: "highlighter"
        case .text: "textformat"
        }
    }

    var title: String {
        switch self {
        case .pen: "Pen"
        case .line: "Line"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .marker: "Marker"
        case .text: "Text"
        }
    }

    /// Freehand tools collect every drag point; shape tools only keep start and end.
    var isFreehand: Bool { self == .pen || self == .marker }
}

/// A single mark drawn on top of the screenshot, stored in overlay view coordinates.
struct Annotation {
    let tool: Tool
    let color: NSColor
    let lineWidth: CGFloat
    var points: [CGPoint]
    var text: String = ""
    var font: NSFont = .systemFont(ofSize: 18)
    var textFrame: NSRect = .zero

    var start: CGPoint { points.first ?? .zero }
    var end: CGPoint { points.last ?? .zero }

    /// Ignore accidental clicks that would leave an invisible shape behind.
    var isMeaningful: Bool {
        switch tool {
        case .pen, .marker: !points.isEmpty
        case .text: !text.isEmpty
        default: hypot(end.x - start.x, end.y - start.y) >= 2
        }
    }

    func draw() {
        switch tool {
        case .pen, .marker:
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.move(to: first)
            points.dropFirst().forEach { path.line(to: $0) }
            if points.count == 1 { path.line(to: first) }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            if tool == .marker {
                color.withAlphaComponent(0.4).setStroke()
                path.lineWidth = lineWidth * 4 + 6
            } else {
                color.setStroke()
                path.lineWidth = lineWidth
            }
            path.stroke()

        case .line:
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.stroke()

        case .arrow:
            drawArrow()

        case .rectangle:
            color.setStroke()
            let path = NSBezierPath(rect: NSRect(corner: start, to: end))
            path.lineWidth = lineWidth
            path.lineJoinStyle = .miter
            path.stroke()

        case .ellipse:
            color.setStroke()
            let path = NSBezierPath(ovalIn: NSRect(corner: start, to: end))
            path.lineWidth = lineWidth
            path.stroke()

        case .text:
            NSAttributedString(string: text, attributes: Annotation.textAttributes(font: font, color: color))
                .draw(in: textFrame.insetBy(dx: Annotation.textInset, dy: 0))
        }
    }

    private func drawArrow() {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = hypot(end.x - start.x, end.y - start.y)
        let headLength = min(max(12, lineWidth * 4), length)
        let spread = CGFloat.pi / 7

        let left = CGPoint(x: end.x - headLength * cos(angle - spread), y: end.y - headLength * sin(angle - spread))
        let right = CGPoint(x: end.x - headLength * cos(angle + spread), y: end.y - headLength * sin(angle + spread))
        // Stop the shaft inside the head so a thick line can't poke through the tip.
        let inset = headLength * 0.7
        let shaftEnd = CGPoint(x: end.x - inset * cos(angle), y: end.y - inset * sin(angle))

        color.set()
        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: shaftEnd)
        shaft.lineWidth = lineWidth
        shaft.lineCapStyle = .round
        shaft.stroke()

        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: left)
        head.line(to: right)
        head.close()
        head.fill()
    }

    /// NSTextField draws its text 2pt in from the edge; the burned-in text must match.
    static let textInset: CGFloat = 2

    static func textAttributes(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color]
    }

    static func font(forLineWidth width: CGFloat) -> NSFont {
        .systemFont(ofSize: 10 + width * 3, weight: .semibold)
    }
}

extension NSRect {
    init(corner a: CGPoint, to b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

/// With Shift held: lines snap to 45° steps, rectangles and ellipses become squares and circles.
func constrained(_ point: CGPoint, from origin: CGPoint, tool: Tool) -> CGPoint {
    let dx = point.x - origin.x, dy = point.y - origin.y
    switch tool {
    case .line, .arrow:
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        let length = hypot(dx, dy)
        return CGPoint(x: origin.x + length * cos(angle), y: origin.y + length * sin(angle))
    default:
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: origin.x + (dx < 0 ? -side : side), y: origin.y + (dy < 0 ? -side : side))
    }
}
