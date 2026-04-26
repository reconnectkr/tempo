import SwiftUI
import SwiftData
import AppKit

struct MenuBarLabel: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<TodoTask> { $0.timerEndsAt != nil },
        sort: \TodoTask.timerEndsAt
    ) private var timerTasks: [TodoTask]

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: checkmarkImage)

            if let nearest = nearestRunningTimer {
                let remaining = max(0, nearest.timerEndsAt!.timeIntervalSince(now))
                Text(TimerManager.formatTime(remaining))
                    .monospacedDigit()
                    .font(.system(size: 12))
            }
        }
        .onReceive(timer) { _ in
            now = Date()
        }
    }

    private var nearestRunningTimer: TodoTask? {
        timerTasks.first { $0.isTimerRunning && ($0.timerEndsAt ?? .distantPast) > now }
    }

    private var checkmarkImage: NSImage {
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
}
