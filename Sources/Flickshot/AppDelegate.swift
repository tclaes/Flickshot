import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var session: CaptureSession?
    private var isCapturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Flickshot")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.menu = buildMenu()

        // Same default as Lightshot for Mac: ⌥⌘S.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.takeScreenshot()
        }
        if hotKey == nil { warnHotKeyTaken() }

        if !ScreenCapturer.hasPermission { ScreenCapturer.requestPermission() }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let capture = NSMenuItem(title: "Take Screenshot", action: #selector(takeScreenshotFromMenu), keyEquivalent: "s")
        capture.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(capture)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Screen Recording Settings…", action: #selector(openPrivacySettings), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Flickshot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        menu.delegate = self
        return menu
    }

    @objc private func takeScreenshotFromMenu() {
        // Let the menu finish fading out so it doesn't end up in the capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.takeScreenshot() }
    }

    func takeScreenshot() {
        guard session == nil, !isCapturing else { return }
        isCapturing = true
        Task { @MainActor in
            defer { isCapturing = false }
            do {
                let shots = try await ScreenCapturer.captureAllScreens()
                guard !shots.isEmpty else { return }
                session = CaptureSession(shots: shots) { [weak self] in self?.session = nil }
            } catch {
                showPermissionAlert(error)
            }
        }
    }

    // MARK: - Menu actions

    @objc private func toggleLaunchAtLogin(_ item: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    // MARK: - Alerts

    private func showPermissionAlert(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        if ScreenCapturer.hasPermission {
            alert.messageText = "Couldn't capture the screen"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }
        alert.messageText = "Flickshot needs Screen Recording permission"
        alert.informativeText = "Turn on Flickshot under Privacy & Security → Screen & System Audio Recording, then try again. "
            + "If it's already on, remove it with “–” and add it again (rebuilt apps get a new signature)."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { openPrivacySettings() }
    }

    private func warnHotKeyTaken() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "⌥⌘S is already in use"
        alert.informativeText = "Another app (probably the old Lightshot) owns this shortcut. Quit it and relaunch Flickshot, "
            + "or use the menu bar icon to take screenshots."
        alert.runModal()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTitle: "Launch at Login")?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
