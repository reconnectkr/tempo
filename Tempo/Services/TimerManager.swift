import Foundation
import SwiftData
import Combine

@Observable
final class TimerManager {
    var nearestEndTime: Date?
    var displayText: String = ""

    private var timer: Timer?
    private var modelContext: ModelContext?

    func start(with context: ModelContext) {
        self.modelContext = context
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.current.add(timer!, forMode: .common)
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func tick() {
        guard let context = modelContext else { return }
        refreshNearestTimer(context: context)
    }

    private func refreshNearestTimer(context: ModelContext) {
        let now = Date.now
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.timerEndsAt != nil },
            sortBy: [SortDescriptor(\.timerEndsAt)]
        )

        guard let tasks = try? context.fetch(descriptor) else {
            nearestEndTime = nil
            displayText = ""
            return
        }

        let running = tasks.filter { $0.isTimerRunning && ($0.timerEndsAt ?? .distantPast) > now }

        if let nearest = running.first {
            nearestEndTime = nearest.timerEndsAt
            let remaining = nearest.timerEndsAt!.timeIntervalSince(now)
            displayText = Self.formatTime(remaining)
        } else {
            nearestEndTime = nil
            displayText = ""
        }
    }

    static func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
