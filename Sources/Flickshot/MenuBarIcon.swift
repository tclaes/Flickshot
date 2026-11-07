import AppKit

/// The Flickshot mark (selection corners + flick) as a menu bar template image.
/// Mirrors docs/assets/flickshot-mark.svg, whose artwork lives in a 504-unit box starting at (260, 260).
enum MenuBarIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let s = size / 504
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: (x - 260) * s, y: (y - 260) * s) }

            NSColor.black.set()

            let corners = NSBezierPath()
            corners.lineWidth = 60 * s
            corners.lineCapStyle = .round
            corners.lineJoinStyle = .round
            for pts in [[p(300, 420), p(300, 300), p(420, 300)],
                        [p(604, 300), p(724, 300), p(724, 420)],
                        [p(724, 604), p(724, 724), p(604, 724)],
                        [p(420, 724), p(300, 724), p(300, 604)]] {
                corners.move(to: pts[0])
                corners.line(to: pts[1])
                corners.line(to: pts[2])
            }
            corners.stroke()

            let flick = NSBezierPath()
            flick.move(to: p(352, 668))
            flick.curve(to: p(601, 376), controlPoint1: p(470, 650), controlPoint2: p(570, 560))
            let start = atan2(376.0 - 384, 601.0 - 640) * 180 / .pi
            let end = atan2(392.0 - 384, 679.0 - 640) * 180 / .pi
            flick.appendArc(withCenter: p(640, 384), radius: 40 * s, startAngle: start, endAngle: end, clockwise: false)
            flick.curve(to: p(352, 668), controlPoint1: p(646, 572), controlPoint2: p(520, 668))
            flick.close()
            flick.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Flickshot"
        return image
    }
}
