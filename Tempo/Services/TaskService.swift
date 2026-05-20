import Foundation
import SwiftData
import AppKit

struct TaskService {

    // MARK: - 생성

    @discardableResult
    static func createTask(
        title: String,
        parent: TodoTask?,
        assignedDate: Date = .now,
        plannedDuration: TimeInterval?,
        context: ModelContext
    ) -> TodoTask {
        let siblings: [TodoTask]
        if let parent {
            siblings = parent.children
        } else {
            let descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { $0.parent == nil }
            )
            siblings = (try? context.fetch(descriptor)) ?? []
        }

        // 자식은 호출자가 지정한 날짜(보통 selectedDate)를 그대로 사용.
        // 부모-자식이 서로 다른 날짜를 가질 수 있도록 허용.
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
        return task
    }

    // MARK: - 완료

    static func toggleComplete(_ task: TodoTask, context: ModelContext) {
        if task.status == .completed {
            task.status = .pending
            task.completedAt = nil
            // 완료 해제 시 자손도 함께 해제 (사용자 요청). 완료 진입 때와 대칭.
            propagateUncompleteDownward(from: task)
        } else {
            task.status = .completed
            task.completedAt = .now
            // 완료 시 FOCUS 자동 해제 (SPEC 2.4.2). 자손이라도 동일.
            // 자손 완료가 부모 FOCUS 상태에 영향을 주지는 않음.
            task.isFocused = false
            stopTimer(task, context: context)
            NSSound(named: "Glass")?.play()
            // 자손 자동 완료 → 부모 자동 완료(루트까지) 순서. 자손이 모두 완료된 뒤
            // upward 전파를 호출해야 일관됨.
            propagateCompletionDownward(from: task, context: context)
            propagateCompletionUpward(from: task, context: context)
        }
        try? context.save()
    }

    // 부모 → 자손 방향 자동 완료. 부모를 완료 처리하면 모든 미완료 자손도 함께 완료.
    // 이미 완료된 자손은 completedAt이 보존됨(소급 갱신하지 않음). 자손에 isFocused·타이머가
    // 있었다면 함께 정리.
    private static func propagateCompletionDownward(from task: TodoTask, context: ModelContext) {
        for child in task.children where child.status != .completed {
            child.status = .completed
            child.completedAt = .now
            child.isFocused = false
            stopTimer(child, context: context)
            propagateCompletionDownward(from: child, context: context)
        }
    }

    // 부모 → 자손 방향 완료 해제. 자손 중 완료 상태인 항목만 pending으로 되돌림.
    // 이미 미완료(pending/inProgress)인 자손은 그대로 둠.
    private static func propagateUncompleteDownward(from task: TodoTask) {
        for child in task.children where child.status == .completed {
            child.status = .pending
            child.completedAt = nil
            propagateUncompleteDownward(from: child)
        }
    }

    // 하위 항목이 모두 완료되면 부모도 자동 완료. 루트까지 재귀 전파.
    // 자식이 없는 부모는 영향 없음(자기 상태 유지).
    private static func propagateCompletionUpward(from task: TodoTask, context: ModelContext) {
        guard let parent = task.parent else { return }
        guard !parent.children.isEmpty else { return }
        guard parent.status != .completed else { return }
        guard parent.children.allSatisfy({ $0.status == .completed }) else { return }

        parent.status = .completed
        parent.completedAt = .now
        parent.isFocused = false
        stopTimer(parent, context: context)
        propagateCompletionUpward(from: parent, context: context)
    }

    // MARK: - FOCUS

    // FOCUS 토글. 부모 노드면 자기 자신 + 모든 자손이 함께 진입/이탈한다 (SPEC 2.4.2).
    // 부모가 이미 FOCUS인 상태에서 자식을 또 올리려고 하면, 그 자식은 이미 isFocused=true이므로
    // setFocusRecursively가 멱등하게 동작 — 자손 전체에 동일한 값을 다시 셋해도 문제 없음.
    static func toggleFocus(_ task: TodoTask, context: ModelContext) {
        let newValue = !task.isFocused
        setFocusRecursively(task, to: newValue, context: context)
        try? context.save()
    }

    private static func setFocusRecursively(_ task: TodoTask, to value: Bool, context: ModelContext) {
        // 완료된 작업은 FOCUS에 올리지 않음. 내리는 건 허용(데이터 일관성).
        if value, task.status == .completed { return }
        task.isFocused = value
        if value {
            task.focusOrder = nextFocusOrder(context: context)
            // FOCUS 설정 시 자동으로 진행 중 상태로 함께 전환. 사용자 요청: FOCUS = inProgress + focus 묶음.
            // 자식 동반 시 자손에도 동일하게 적용됨.
            task.status = .inProgress
        }
        for child in task.children {
            setFocusRecursively(child, to: value, context: context)
        }
    }

    private static func nextFocusOrder(context: ModelContext) -> Int {
        var descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.isFocused == true },
            sortBy: [SortDescriptor(\.focusOrder, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let current = (try? context.fetch(descriptor).first?.focusOrder) ?? -1
        return current + 1
    }

    // 상태를 직접 지정. 패널의 segmented picker가 호출.
    // toggleComplete / toggleInProgress 두 토글의 의미를 통합하면서, 부수효과(타이머 정지·
    // FOCUS 자동 해제·완료 시각 등록·사운드·부모 자동 완료 전파)도 한 곳에서 일관되게 처리한다.
    static func setStatus(_ task: TodoTask, to newStatus: TaskStatus, context: ModelContext) {
        guard task.status != newStatus else { return }

        let wasCompleted = task.status == .completed

        switch newStatus {
        case .pending:
            if task.isTimerRunning {
                // 타이머가 돌고 있으면 pauseTimer가 status=pending 처리까지 수행.
                pauseTimer(task, context: context)
            } else {
                task.status = .pending
            }
            // 완료 → 대기 복귀: 완료 시각도 해제 (toggleComplete와 일관).
            if task.completedAt != nil {
                task.completedAt = nil
            }
            if wasCompleted {
                propagateUncompleteDownward(from: task)
            }

        case .inProgress:
            // 타이머 실행 중에는 inProgress가 이미 유지되므로 도달할 수 없는 분기지만 방어.
            guard !task.isTimerRunning else { return }
            if task.completedAt != nil {
                task.completedAt = nil
            }
            task.status = .inProgress
            if wasCompleted {
                propagateUncompleteDownward(from: task)
            }

        case .completed:
            task.status = .completed
            // 패널에서 기존 완료 시각을 보존하며 상태만 토글할 수 있도록, 이미 값이 있으면 유지.
            if task.completedAt == nil {
                task.completedAt = .now
            }
            task.isFocused = false
            stopTimer(task, context: context)
            NSSound(named: "Glass")?.play()
            propagateCompletionDownward(from: task, context: context)
            propagateCompletionUpward(from: task, context: context)
        }

        try? context.save()
    }

    // 타이머가 돌고 있지 않을 때 진행/대기 상태 토글.
    // 타이머 실행 중에는 타이머가 상태를 관리하므로 호출 효과 없음.
    static func toggleInProgress(_ task: TodoTask, context: ModelContext) {
        guard !task.isTimerRunning else { return }
        switch task.status {
        case .pending:
            task.status = .inProgress
        case .inProgress:
            task.status = .pending
        case .completed:
            return
        }
        try? context.save()
    }

    // MARK: - 삭제

    static func deleteTask(_ task: TodoTask, context: ModelContext) {
        // SwiftData @Relationship(.cascade)가 자식까지 삭제하지만,
        // 알림 큐는 모델 외부 자원이라 자식 트리도 명시적으로 정리해야 함.
        cancelNotificationsRecursively(task)
        context.delete(task)
        try? context.save()
    }

    private static func cancelNotificationsRecursively(_ task: TodoTask) {
        NotificationManager.shared.cancelNotification(taskId: task.id.uuidString)
        for child in task.children {
            cancelNotificationsRecursively(child)
        }
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
        task.carriedOverCount += 1
        task.needsCarryOverDecision = false
        // 트리 전체(손자 포함)를 today로 동기화. 직계 자식만 갱신하면 3단 트리에서
        // 손자의 assignedDate가 stale로 남아 어느 날짜 화면에서도 안 보이게 됨.
        applyAssignedDate(today, to: task)
        try? context.save()
    }

    // 모든 자식의 assignedDate를 root와 동기화. 과거 carry-over에서 손자가 누락돼
    // 트리 날짜가 어긋난 잔재(부모-자식 다른 날짜)를 일괄 정리. 앱 시작 시 1회 실행.
    @discardableResult
    static func reconcileTreeDates(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.parent == nil }
        )
        guard let roots = try? context.fetch(descriptor) else { return 0 }

        var fixed = 0
        for root in roots {
            fixed += reconcileSubtree(root, expected: root.assignedDate)
        }
        if fixed > 0 {
            try? context.save()
        }
        return fixed
    }

    private static func reconcileSubtree(_ task: TodoTask, expected: Date) -> Int {
        var count = 0
        for child in task.children {
            if child.assignedDate != expected {
                child.assignedDate = expected
                count += 1
            }
            count += reconcileSubtree(child, expected: expected)
        }
        return count
    }

    // 선택 항목을 다른 날짜로 이동. 루트면 트리 전체, 자식이면 해당 서브트리만 이동.
    // 자식만 이동한 경우 화면에서는 relevantTaskIds 로직으로 부모가 컨텍스트로 노출됨.
    // originalDate도 함께 이동 — 의도적 재계획이므로 "O-N" 배지가 붙으면 안 됨.
    // 자동 carry-over(carryOverToToday)와는 달라야 해서 applyAssignedDate를 그대로 두고 별도 처리.
    static func moveByDays(_ task: TodoTask, days: Int, context: ModelContext) {
        let calendar = Calendar.current
        guard let target = calendar.date(byAdding: .day, value: days, to: task.assignedDate) else { return }
        let targetStart = calendar.startOfDay(for: target)
        applyDates(assigned: targetStart, original: targetStart, to: task)
        try? context.save()
    }

    private static func applyDates(assigned: Date, original: Date, to task: TodoTask) {
        task.assignedDate = assigned
        task.originalDate = original
        for child in task.children {
            applyDates(assigned: assigned, original: original, to: child)
        }
    }

    // MARK: - 디테일 패널 편집

    static func updateTitle(_ task: TodoTask, title: String, context: ModelContext) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        task.title = trimmed
        try? context.save()
    }

    static func updateMemo(_ task: TodoTask, memo: String, context: ModelContext) {
        guard memo != task.memo else { return }
        task.memo = memo
        try? context.save()
    }

    static func updateCreatedAt(_ task: TodoTask, date: Date, context: ModelContext) {
        guard date != task.createdAt else { return }
        task.createdAt = date
        try? context.save()
    }

    // 디테일 패널의 "최초 날짜" 편집용. 자기 자신만 갱신(자식 트리는 건드리지 않음 —
    // assignedDate 변경과 달리, originalDate는 항목별 carry-over 시작 시점을 표현).
    static func updateOriginalDate(_ task: TodoTask, date: Date, context: ModelContext) {
        let day = Calendar.current.startOfDay(for: date)
        guard day != task.originalDate else { return }
        task.originalDate = day
        try? context.save()
    }

    static func updateCompletedAt(_ task: TodoTask, date: Date, context: ModelContext) {
        guard task.completedAt != nil, date != task.completedAt else { return }
        task.completedAt = date
        try? context.save()
    }

    // 특정 절대 날짜로 이동. moveByDays와 달리 임의의 날짜 지정 가능.
    // originalDate도 함께 갱신해 의도적 재계획임을 명시(carry-over 배지 미부착).
    // 자식 서브트리도 동일하게 따라감.
    static func updateAssignedDate(_ task: TodoTask, date: Date, context: ModelContext) {
        let target = Calendar.current.startOfDay(for: date)
        guard target != task.assignedDate else { return }
        applyDates(assigned: target, original: target, to: task)
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
        // 제자리 드롭(결과가 현재 상태와 동일) no-op 처리.
        // 이 가드가 있어야 드롭 영역 중앙을 자식으로 적극 해석해도
        // 같은 줄에 그대로 놓은 동작이 의도치 않게 자식화되지 않음.
        if isNoOpDrop(source: source, target: target, mode: mode) {
            return
        }

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

        // 드래그앤드롭은 트리 구조(부모·순서·깊이)만 변경하고 assignedDate는 건드리지 않음.
        // 부모-자식이 다른 날짜를 가질 수 있는 모델에서 사용자의 날짜 의도를 보존.
        // 날짜를 바꾸려면 carry-over나 별도 액션을 써야 함.
        source.parent = newParent
        source.sortOrder = newSortOrder
        recalculateDepth(source)

        try? context.save()
    }

    private static func isNoOpDrop(source: TodoTask, target: TodoTask, mode: DropMode) -> Bool {
        switch mode {
        case .siblingAbove:
            // 이미 target과 같은 부모를 가지면서 target 바로 위에 있으면 변화 없음.
            guard source.parent === target.parent else { return false }
            return source.sortOrder + 1 == target.sortOrder
        case .siblingBelow:
            // 이미 target과 같은 부모를 가지면서 target 바로 아래에 있으면 변화 없음.
            guard source.parent === target.parent else { return false }
            return source.sortOrder == target.sortOrder + 1
        case .child:
            // 이미 target의 자식이고 children 마지막이면 변화 없음.
            guard source.parent === target else { return false }
            let maxOrder = target.children.map(\.sortOrder).max() ?? -1
            return source.sortOrder == maxOrder
        }
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
