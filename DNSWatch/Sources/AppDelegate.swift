import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var statusMenu: NSMenu?

    private let statsEngine = StatsEngine()
    private var packetCaptures: [PacketCapture] = []
    private var activeInterfaces: [String] = []

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_: Notification) {
        self.setupMenuBar()
        self.setupStatusMenu()
        self.startCapture()
        self.observeStats()
    }

    func applicationWillTerminate(_: Notification) {
        // Save stats before quitting
        self.statsEngine.save()
        self.stopAllCaptures()
    }

    private func stopAllCaptures() {
        for capture in self.packetCaptures {
            capture.stopCapture()
        }
        self.packetCaptures.removeAll()
        self.activeInterfaces.removeAll()
        self.statsEngine.setCaptureActive(false)
    }

    /// Check if any capture is currently active
    private var isAnyCapturing: Bool {
        self.packetCaptures.contains { $0.capturing }
    }

    // MARK: - Setup

    private func setupMenuBar() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            self.updateStatusIcon(queryRate: 0)
            button.action = #selector(self.handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let contentView = ContentView(
            statsEngine: statsEngine,
            onReset: { [weak self] in self?.resetStats() },
            onToggleCapture: { [weak self] in self?.toggleCapture() },
            isCapturing: { [weak self] in
                self?.isAnyCapturing ?? false
            },
            onQuit: { NSApp.terminate(nil) },
            activeInterfaces: { [weak self] in
                self?.activeInterfaces ?? []
            },
            onInstallBPFHelper: { [weak self] in
                self?.installBPFHelper()
            },
            onUninstallBPFHelper: { [weak self] in
                self?.uninstallBPFHelper()
            }
        )

        self.popover = NSPopover()
        self.popover?.contentSize = NSSize(width: 400, height: 600)
        self.popover?.behavior = .transient
        self.popover?.animates = true
        self.popover?.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupStatusMenu() {
        self.statusMenu = NSMenu()

        let showItem = NSMenuItem(title: "Show DNSWatch", action: #selector(showPopover), keyEquivalent: "")
        showItem.target = self
        self.statusMenu?.addItem(showItem)

        self.statusMenu?.addItem(NSMenuItem.separator())

        let pauseItem = NSMenuItem(title: "Pause Capture", action: #selector(toggleCaptureMenu), keyEquivalent: "")
        pauseItem.target = self
        self.statusMenu?.addItem(pauseItem)

        let resetItem = NSMenuItem(title: "Reset Statistics", action: #selector(resetStatsMenu), keyEquivalent: "")
        resetItem.target = self
        self.statusMenu?.addItem(resetItem)

        self.statusMenu?.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit DNSWatch", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        self.statusMenu?.addItem(quitItem)
    }

    private func observeStats() {
        // Update icon based on query rate
        self.statsEngine.$queriesLastMinute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                self?.updateStatusIcon(queryRate: rate)
            }
            .store(in: &self.cancellables)
    }

    private func updateStatusIcon(queryRate: Int) {
        guard let button = statusItem?.button else { return }

        // Create icon with activity indicator
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        if self.packetCaptures.isEmpty || !self.isAnyCapturing {
            // Paused state
            button.image = NSImage(systemSymbolName: "network.slash", accessibilityDescription: "DNS Monitor (Paused)")?
                .withSymbolConfiguration(config)
            button.appearsDisabled = true
        } else if queryRate > 30 {
            // High activity
            button.image = NSImage(
                systemSymbolName: "network.badge.shield.half.filled",
                accessibilityDescription: "DNS Monitor (Active)"
            )?
                .withSymbolConfiguration(config)
            button.appearsDisabled = false
        } else {
            // Normal
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "DNS Monitor")?
                .withSymbolConfiguration(config)
            button.appearsDisabled = false
        }
    }

    // MARK: - Actions

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right click - show menu
            if let menu = statusMenu, let button = statusItem?.button {
                // Update menu item titles
                if let pauseItem = menu.item(withTitle: "Pause Capture") ?? menu.item(withTitle: "Resume Capture") {
                    pauseItem.title = self.isAnyCapturing ? "Pause Capture" : "Resume Capture"
                }
                self.statusItem?.menu = menu
                button.performClick(nil)
                self.statusItem?.menu = nil
            }
        } else {
            // Left click - toggle popover
            self.togglePopover()
        }
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func showPopover() {
        guard let popover, let button = statusItem?.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func toggleCaptureMenu() {
        self.toggleCapture()
    }

    @objc private func resetStatsMenu() {
        self.resetStats()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func startCapture() {
        self.stopAllCaptures()

        let detectedInterfaces = InterfaceDetector.detectBestInterfaces()
        print("Detected interfaces: \(detectedInterfaces.map { "\($0.name) (\($0.reason))" })")

        var startedAny = false
        var lastError: Error?

        for info in detectedInterfaces.prefix(3) {
            let capture = PacketCapture()
            do {
                try capture.startCapture(interface: info.name) { [weak self] query in
                    Task { @MainActor in
                        self?.statsEngine.recordQuery(query)
                    }
                }
                self.packetCaptures.append(capture)
                self.activeInterfaces.append(info.name)
                print("✓ Capturing on \(info.name) (\(info.reason))")
                startedAny = true
            } catch {
                print("✗ Failed on \(info.name): \(error.localizedDescription)")
                lastError = error
            }
        }

        if !startedAny, let error = lastError {
            self.showCaptureError(error)
        }

        self.statsEngine.setCaptureActive(startedAny)
        self.updateStatusIcon(queryRate: 0)
    }

    private func toggleCapture() {
        if self.isAnyCapturing {
            self.stopAllCaptures()
        } else {
            self.startCapture()
        }
        self.updateStatusIcon(queryRate: self.statsEngine.queriesLastMinute)
    }

    private func resetStats() {
        self.statsEngine.reset()
    }

    private func showCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "DNS Capture Error"
        alert.informativeText = """
        \(error.localizedDescription)

        To fix this permanently, install the BPF helper (admin password required once).
        Temporary fix:
        sudo chmod o+rw /dev/bpf*

        Or run with: sudo \(Bundle.main.executablePath ?? "DNSWatch")
        """
        alert.alertStyle = .warning
        let isPermissionIssue = self.isPermissionError(error)
        if isPermissionIssue {
            alert.addButton(withTitle: "Install Helper")
            alert.addButton(withTitle: "OK")
        } else {
            alert.addButton(withTitle: "OK")
        }
        let response = alert.runModal()
        if isPermissionIssue && response == .alertFirstButtonReturn {
            self.installBPFHelper()
        }
    }

    private func installBPFHelper() {
        do {
            try BPFHelperInstaller.install()
            self.showBPFHelperResult(
                title: "BPF Helper Installed",
                message: """
                DNSWatch will restore BPF permissions at boot.
                If capture doesn't start immediately, log out and back in.
                """
            )
            if !self.isAnyCapturing {
                self.startCapture()
            }
        } catch {
            self.showBPFHelperResult(
                title: "BPF Helper Failed",
                message: error.localizedDescription
            )
        }
    }

    private func uninstallBPFHelper() {
        do {
            try BPFHelperInstaller.uninstall()
            self.showBPFHelperResult(
                title: "BPF Helper Removed",
                message: "BPF permissions will reset on reboot."
            )
        } catch {
            self.showBPFHelperResult(
                title: "BPF Helper Failed",
                message: error.localizedDescription
            )
        }
    }

    private func showBPFHelperResult(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func isPermissionError(_ error: Error) -> Bool {
        guard let captureError = error as? PacketCapture.CaptureError else {
            return false
        }
        switch captureError {
        case let .openFailed(message):
            let lowercased = message.lowercased()
            return lowercased.contains("permission denied") || lowercased.contains("permission")
        case .filterCompileFailed, .filterSetFailed:
            return false
        }
    }
}
