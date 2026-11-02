import AppKit
import UniformTypeIdentifiers

/// One screenshot in progress: an overlay window per display, plus the shared
/// tool, colour and line width the user picked.
final class CaptureSession {
    static let palette: [(String, NSColor)] = [
        ("Red", .systemRed), ("Orange", .systemOrange), ("Yellow", .systemYellow), ("Green", .systemGreen),
        ("Blue", .systemBlue), ("Purple", .systemPurple), ("Black", .black), ("White", .white),
    ]

    var tool: Tool? { didSet { views.forEach { $0.toolStateChanged() } } }
    var color: NSColor { didSet { Self.savedColorIndex = Self.palette.firstIndex { $0.1 == color } ?? 0; views.forEach { $0.toolStateChanged() } } }
    var lineWidth: CGFloat { didSet { UserDefaults.standard.set(Double(lineWidth), forKey: "lineWidth") } }

    private var windows: [OverlayWindow] = []
    private var views: [OverlayView] { windows.compactMap { $0.contentView as? OverlayView } }
    private let onClose: () -> Void
    private var resignObserver: NSObjectProtocol?

    init(shots: [ScreenShot], onClose: @escaping () -> Void) {
        self.onClose = onClose
        color = Self.palette[min(Self.savedColorIndex, Self.palette.count - 1)].1
        let width = UserDefaults.standard.double(forKey: "lineWidth")
        lineWidth = width > 0 ? width : 3

        let mouse = NSEvent.mouseLocation
        for shot in shots {
            let window = OverlayWindow(screen: shot.screen)
            window.contentView = OverlayView(image: shot.image, session: self)
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        for window in windows {
            if window.frame.contains(mouse) {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
        // Switching apps mid-capture would otherwise leave a frozen screen on top.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.close() }
    }

    private static var savedColorIndex: Int {
        get { UserDefaults.standard.integer(forKey: "colorIndex") }
        set { UserDefaults.standard.set(newValue, forKey: "colorIndex") }
    }

    /// Only one display can hold a selection at a time.
    func selectionStarted(in view: OverlayView) {
        views.filter { $0 !== view }.forEach { $0.clearSelection() }
    }

    func close() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        onClose()
    }

    // MARK: - Output

    func copy(_ shot: RenderedShot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(shot.png, forType: .png)
        if let tiff = shot.bitmap.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        close()
    }

    func save(_ shot: RenderedShot, from window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.defaultFileName()
        if let last = UserDefaults.standard.url(forKey: "saveDirectory") {
            panel.directoryURL = last
        } else {
            panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        }
        // The overlay sits at screen-saver level; the panel must float above it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                window?.makeKey()
                return
            }
            do {
                try shot.png.write(to: url)
                UserDefaults.standard.set(url.deletingLastPathComponent(), forKey: "saveDirectory")
                self.close()
            } catch {
                let alert = NSAlert(error: error)
                alert.window.level = panel.level
                alert.runModal()
                window?.makeKey()
            }
        }
    }

    private static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())).png"
    }
}

struct RenderedShot {
    let bitmap: NSBitmapImageRep
    let png: Data
}

final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
