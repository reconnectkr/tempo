import SwiftData
import Foundation

@Model
final class TodoTask {
    var id: UUID
    var title: String
    var createdAt: Date
    var originalDate: Date

    var statusRaw: String
    var completedAt: Date?

    var assignedDate: Date
    var carriedOverCount: Int

    var parent: TodoTask?
    @Relationship(deleteRule: .cascade, inverse: \TodoTask.parent)
    var children: [TodoTask] = []
    var depth: Int
    var sortOrder: Int

    var plannedDuration: TimeInterval?
    var timerStartedAt: Date?
    var timerEndsAt: Date?
    var timerAccumulated: TimeInterval

    var needsCarryOverDecision: Bool

    // FOCUS 영역 (SPEC 2.4). isFocused=true면 상단 FOCUS 섹션에 노출되고
    // QUEUE에서는 음영 표시. 타이머·status와 완전 독립적인 별도 축.
    var isFocused: Bool = false
    var focusOrder: Int = 0

    var memo: String = ""

    @Transient
    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(title: String, assignedDate: Date, parent: TodoTask? = nil, sortOrder: Int = 0, plannedDuration: TimeInterval? = nil) {
        let startOfDay = Calendar.current.startOfDay(for: assignedDate)
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.originalDate = startOfDay
        self.statusRaw = TaskStatus.pending.rawValue
        self.assignedDate = startOfDay
        self.carriedOverCount = 0
        self.parent = parent
        self.depth = (parent?.depth ?? -1) + 1
        self.sortOrder = sortOrder
        self.plannedDuration = plannedDuration
        self.timerAccumulated = 0
        self.needsCarryOverDecision = false
        self.isFocused = false
        self.focusOrder = 0
    }

    var daysActive: Int {
        (Calendar.current.dateComponents([.day], from: originalDate, to: assignedDate).day ?? 0) + 1
    }

    var isTimerRunning: Bool {
        timerStartedAt != nil && statusRaw == TaskStatus.inProgress.rawValue
    }

    var remainingTime: TimeInterval? {
        guard let endsAt = timerEndsAt else { return nil }
        return max(0, endsAt.timeIntervalSinceNow)
    }

    var sortedChildren: [TodoTask] {
        children.sorted { $0.sortOrder < $1.sortOrder }
    }
}

enum TaskStatus: String, Codable {
    case pending
    case inProgress
    case completed
}
