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
    private var sizeCancellable: AnyCancellable?
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
        // variableLength면 라벨(FOCUS 제목, 타이머 시간)이 바뀔 때마다 메뉴바 폭이 변하고
        // popover anchor 위치도 함께 흔들려 UX가 불편함. 18자 제목 + " MM:SS" + 여백을
        // 수용하는 고정 폭으로 안정화. 짧은 컨텐츠일 땐 우측에 여백이 남지만 trade-off 수용.
        statusItem = NSStatusBar.system.statusItem(withLength: 220)

        if let button = statusItem.button {
            button.image = makeCheckmarkImage()
            button.imagePosition = .imageLeading
            // 고정 폭이라 짧은 컨텐츠일 때 아이콘 + 텍스트가 좌측에 정렬되도록.
            button.alignment = .left
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        let settings = AppSettings.shared
        let initialWidth = settings.popoverWidth + (settings.detailPanelOpen ? settings.detailPanelWidth : 0)
        popover.contentSize = NSSize(width: initialWidth, height: settings.popoverHeight)
        popover.behavior = .transient
        popover.animates = true

        let contentView = MenuContentView()
            .modelContainer(modelContainer)
            .environmentObject(settings)

        popover.contentViewController = NSHostingController(rootView: contentView)

        // 뷰 측 드래그가 AppSettings를 갱신하면 NSPopover.contentSize에 즉시 반영.
        // popoverWidth(리스트) + (panelOpen ? detailPanelWidth : 0) 을 총 폭으로 반영.
        // 패널이 열리거나 닫힐 때, 패널 폭이 바뀔 때, 리스트 폭이 바뀔 때 모두 popover 크기에 즉시 동기화.
        let widthStream = settings.$popoverWidth
            .combineLatest(settings.$detailPanelWidth, settings.$detailPanelOpen)
            .map { listW, panelW, open -> CGFloat in
                listW + (open ? panelW : 0)
            }
        sizeCancellable = widthStream
            .combineLatest(settings.$popoverHeight)
            .sink { [weak self] width, height in
                self?.popover.contentSize = NSSize(width: width, height: height)
            }
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

        // FOCUS 0번째(focusOrder 최소) root 조회. SwiftData predicate에서 parent.isFocused 직접
        // 비교가 어려워 isFocused=true 전체를 가져온 뒤 메모리에서 root 필터.
        let focusedDescriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.isFocused == true }
        )
        let focusedAll = (try? context.fetch(focusedDescriptor)) ?? []
        let focusedFirst = focusedAll
            .filter { $0.status != .completed && !($0.parent?.isFocused ?? false) }
            .sorted { $0.focusOrder < $1.focusOrder }
            .first

        // 메뉴바에서 시각적으로 무거워지지 않도록 제목은 18자에서 잘라 말줄임표.
        if let focused = focusedFirst {
            let title = Self.truncate(focused.title, max: 18)
            if let endsAt = focused.timerEndsAt, focused.isTimerRunning, endsAt > now {
                let remaining = max(0, endsAt.timeIntervalSince(now))
                statusItem.button?.title = " \(title)  \(TimerManager.formatTime(remaining))"
            } else {
                statusItem.button?.title = " \(title)"
            }
            return
        }

        // FOCUS 없을 때는 기존 동작 — 가장 빠른 타이머 남은 시간.
        let timerDescriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.timerEndsAt != nil },
            sortBy: [SortDescriptor(\.timerEndsAt)]
        )
        let tasks = (try? context.fetch(timerDescriptor)) ?? []
        let running = tasks.filter { $0.isTimerRunning && ($0.timerEndsAt ?? .distantPast) > now }

        if let nearest = running.first, let endsAt = nearest.timerEndsAt {
            let remaining = max(0, endsAt.timeIntervalSince(now))
            statusItem.button?.title = " \(TimerManager.formatTime(remaining))"
        } else {
            statusItem.button?.title = ""
        }
    }

    private static func truncate(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        return String(s.prefix(max)) + "…"
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
