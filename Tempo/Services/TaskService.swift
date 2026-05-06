import Foundation
import SwiftData
import AppKit

struct TaskService {

    // MARK: - 생성

    static func createTask(
        title: String,
        parent: TodoTask?,
        assignedDate: Date = .now,
        plannedDuration: TimeInterval?,
        context: ModelContext
    ) {
        let siblings: [TodoTask]
        if let parent {
            siblings = parent.children
        } else {
            let descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { $0.parent == nil }
            )
            siblings = (try? context.fetch(descriptor)) ?? []
        }

        let maxOrder = siblings.map(\.sortOrder).max() ?? -1
        let task = TodoTask(
            title: title,
            assignedDate: assignedDate,
            parent: parent,
            sortOrder: maxOrder + 1,
            plannedDuration: plannedDuration
        )
        context.insert(task)
        try? context.save()
    }

    // MARK: - 완료

    static func toggleComplete(_ task: TodoTask, context: ModelContext) {
        if task.status == .completed {
            task.status = .pending
            task.completedAt = nil
        } else {
            task.status = .completed
            task.completedAt = .now
            stopTimer(task, context: context)
            NSSound(named: "Glass")?.play()
        }
        try? context.save()
    }

    // MARK: - 삭제

    static func deleteTask(_ task: TodoTask, context: ModelContext) {
        stopTimer(task, context: context)
        context.delete(task)
        try? context.save()
    }

    // MARK: - 타이머

    static func startTimer(_ task: TodoTask, context: ModelContext) {
        guard let duration = task.plannedDuration, duration > 0 else { return }

        let remaining = duration - task.timerAccumulated
        guard remaining > 0 else { return }

        task.status = .inProgress
        task.timerStartedAt = .now
        task.timerEndsAt = Date.now.addingTimeInterval(remaining)

        NotificationManager.shared.scheduleTimerNotification(
            taskId: task.id.uuidString,
            taskTitle: task.title,
            fireDate: task.timerEndsAt!
        )
        try? context.save()
    }

    static func pauseTimer(_ task: TodoTask, context: ModelContext) {
        guard let startedAt = task.timerStartedAt else { return }

        let elapsed = Date.now.timeIntervalSince(startedAt)
        task.timerAccumulated += elapsed
        task.timerStartedAt = nil
        task.timerEndsAt = nil
        task.status = .pending

        NotificationManager.shared.cancelNotification(taskId: task.id.uuidString)
        try? context.save()
    }

    static func stopTimer(_ task: TodoTask, context: ModelContext) {
        if let startedAt = task.timerStartedAt {
            let elapsed = Date.now.timeIntervalSince(startedAt)
            task.timerAccumulated += elapsed
        }
        task.timerStartedAt = nil
        task.timerEndsAt = nil

        NotificationManager.shared.cancelNotification(taskId: task.id.uuidString)
    }

    static func extendTimer(_ task: TodoTask, by seconds: TimeInterval, context: ModelContext) {
        if task.isTimerRunning, let currentEnd = task.timerEndsAt {
            task.timerEndsAt = currentEnd.addingTimeInterval(seconds)
            task.plannedDuration = (task.plannedDuration ?? 0) + seconds
        } else {
            task.plannedDuration = (task.plannedDuration ?? 0) + seconds
            task.timerAccumulated = 0
            startTimer(task, context: context)
            return
        }

        NotificationManager.shared.cancelNotification(taskId: task.id.uuidString)
        NotificationManager.shared.scheduleTimerNotification(
            taskId: task.id.uuidString,
            taskTitle: task.title,
            fireDate: task.timerEndsAt!
        )
        try? context.save()
    }

    // MARK: - 이월

    static func checkCarryOver(context: ModelContext) {
        let today = Calendar.current.startOfDay(for: .now)
        let completedRaw = TaskStatus.completed.rawValue
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> {
                $0.assignedDate < today &&
                $0.statusRaw != completedRaw &&
                $0.parent == nil
            }
        )

        guard let pending = try? context.fetch(descriptor) else { return }

        for task in pending {
            task.needsCarryOverDecision = true
        }
        try? context.save()
    }

    static func carryOverToToday(_ task: TodoTask, context: ModelContext) {
        let today = Calendar.current.startOfDay(for: .now)
        task.assignedDate = today
        task.carriedOverCount += 1
        task.needsCarryOverDecision = false

        for child in task.children {
            child.assignedDate = today
        }
        try? context.save()
    }

    static func completeCarryOver(_ task: TodoTask, context: ModelContext) {
        task.status = .completed
        task.completedAt = .now
        task.needsCarryOverDecision = false
        try? context.save()
    }

    // MARK: - 드래그앤드롭

    static func canDrop(_ source: TodoTask, onto target: TodoTask, as mode: DropMode) -> Bool {
        if source.id == target.id { return false }
        if isDescendant(target, of: source) { return false }

        let newParentDepth: Int
        switch mode {
        case .siblingAbove, .siblingBelow:
            newParentDepth = target.parent?.depth ?? -1
        case .child:
            newParentDepth = target.depth
        }
        let sourceSubtreeMaxDepth = maxDepthOfSubtree(source) - source.depth
        let resultingMaxDepth = newParentDepth + 1 + sourceSubtreeMaxDepth

        return resultingMaxDepth <= 2
    }

    static func performDrop(
        _ source: TodoTask,
        onto target: TodoTask,
        as mode: DropMode,
        context: ModelContext
    ) {
        let newParent: TodoTask?
        let newSortOrder: Int

        switch mode {
        case .siblingAbove:
            newParent = target.parent
            newSortOrder = target.sortOrder
            shiftSortOrders(parent: newParent, from: target.sortOrder, by: 1, context: context)
        case .siblingBelow:
            newParent = target.parent
            newSortOrder = target.sortOrder + 1
            shiftSortOrders(parent: newParent, from: target.sortOrder + 1, by: 1, context: context)
        case .child:
            newParent = target
            newSortOrder = (target.children.map(\.sortOrder).max() ?? -1) + 1
        }

        // 트리는 같은 assignedDate를 공유함.
        // source가 들어갈 destination tree의 날짜를 mutation 전에 미리 캡처.
        // (siblingAbove/Below of a root처럼 source가 root로 승격될 때
        //  source.parent가 nil이 되어 rootOf(source)가 자기 자신이 되는 함정 회피)
        let destinationRootDate = rootOf(target).assignedDate

        source.parent = newParent
        source.sortOrder = newSortOrder
        recalculateDepth(source)
        applyAssignedDate(destinationRootDate, to: source)

        try? context.save()
    }

    private static func rootOf(_ task: TodoTask) -> TodoTask {
        var current = task
        while let parent = current.parent {
            current = parent
        }
        return current
    }

    private static func applyAssignedDate(_ date: Date, to task: TodoTask) {
        task.assignedDate = date
        for child in task.children {
            applyAssignedDate(date, to: child)
        }
    }

    // MARK: - 유틸리티

    private static func isDescendant(_ candidate: TodoTask, of ancestor: TodoTask) -> Bool {
        var current = candidate.parent
        while let node = current {
            if node.id == ancestor.id { return true }
            current = node.parent
        }
        return false
    }

    private static func maxDepthOfSubtree(_ task: TodoTask) -> Int {
        if task.children.isEmpty { return task.depth }
        return task.children.map { maxDepthOfSubtree($0) }.max() ?? task.depth
    }

    static func recalculateDepth(_ task: TodoTask) {
        task.depth = (task.parent?.depth ?? -1) + 1
        for child in task.children {
            recalculateDepth(child)
        }
    }

    private static func shiftSortOrders(
        parent: TodoTask?,
        from startOrder: Int,
        by offset: Int,
        context: ModelContext
    ) {
        let siblings: [TodoTask]
        if let parent {
            siblings = parent.children
        } else {
            let descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { $0.parent == nil }
            )
            siblings = (try? context.fetch(descriptor)) ?? []
        }

        for sibling in siblings where sibling.sortOrder >= startOrder {
            sibling.sortOrder += offset
        }
    }

    // MARK: - 시간 수정

    static func updatePlannedDuration(_ task: TodoTask, duration: TimeInterval, context: ModelContext) {
        task.plannedDuration = duration

        if task.isTimerRunning, let startedAt = task.timerStartedAt {
            let elapsed = Date.now.timeIntervalSince(startedAt)
            let remaining = duration - task.timerAccumulated - elapsed
            task.timerEndsAt = Date.now.addingTimeInterval(max(0, remaining))

            NotificationManager.shared.cancelNotification(taskId: task.id.uuidString)
            if remaining > 0 {
                NotificationManager.shared.scheduleTimerNotification(
                    taskId: task.id.uuidString,
                    taskTitle: task.title,
                    fireDate: task.timerEndsAt!
                )
            }
        }
        try? context.save()
    }
}

enum DropMode {
    case siblingAbove
    case siblingBelow
    case child
}
