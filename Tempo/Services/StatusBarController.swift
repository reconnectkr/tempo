import AppKit
import SwiftUI
import SwiftData
import Combine

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var rightClickMenu: NSMenu!
    private var timerCancellable: AnyCancellable?
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        super.init()
        setupStatusItem()
        setupPopover()
        setupRightClickMenu()
        startTimerUpdate()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = makeCheckmarkImage()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 500)
        popover.behavior = .transient
        popover.animates = true

        let contentView = MenuContentView()
            .modelContainer(modelContainer)

        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupRightClickMenu() {
        rightClickMenu = NSMenu()

        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        rightClickMenu.addItem(aboutItem)

        rightClickMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "종료", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        rightClickMenu.addItem(quitItem)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            statusItem.menu = rightClickMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Tempo"
        alert.informativeText = "버전 \(appVersion) (\(buildNumber))\n\n메뉴바에서 빠르게 관리하는 TODO 앱\n\nCopyright 2026 Reconnect"
        alert.icon = NSImage(named: "AppIcon")
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func startTimerUpdate() {
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateTimerDisplay()
            }
    }

    private func updateTimerDisplay() {
        let context = modelContainer.mainContext
        let now = Date.now
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.timerEndsAt != nil },
            sortBy: [SortDescriptor(\.timerEndsAt)]
        )

        guard let tasks = try? context.fetch(descriptor) else {
            statusItem.button?.title = ""
            return
        }

        let running = tasks.filter { $0.isTimerRunning && ($0.timerEndsAt ?? .distantPast) > now }

        if let nearest = running.first, let endsAt = nearest.timerEndsAt {
            let remaining = max(0, endsAt.timeIntervalSince(now))
            let text = TimerManager.formatTime(remaining)
            statusItem.button?.title = " \(text)"
        } else {
            statusItem.button?.title = ""
        }
    }

    private func makeCheckmarkImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            let w = rect.width
            let h = rect.height
            let inset: CGFloat = 2

            let left = CGPoint(x: inset, y: h * 0.45)
            let bottom = CGPoint(x: w * 0.38, y: inset)
            let right = CGPoint(x: w - inset, y: h - inset)

            path.lineWidth = 3.0
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: left)
            path.line(to: bottom)
            path.line(to: right)

            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
