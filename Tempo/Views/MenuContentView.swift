import SwiftUI
import SwiftData
import AppKit

struct MenuContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @Query(
        filter: #Predicate<TodoTask> { $0.needsCarryOverDecision == true }
    ) private var carryOverTasks: [TodoTask]

    @Query(sort: \TodoTask.sortOrder) private var allTasks: [TodoTask]

    @State private var selectedTaskId: UUID?
    @State private var editingTaskId: UUID?
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var currentDayStart = Calendar.current.startOfDay(for: .now)
    @State private var dragState = DragState()
    @State private var scrollTargetId: UUID?
    @State private var keyMonitor: Any?
    @State private var dragStartWidth: CGFloat?
    @State private var dragStartHeight: CGFloat?
    @State private var recentlyDroppedId: UUID?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Group {
            if !carryOverTasks.isEmpty {
                CarryOverView()
            } else {
                mainView
            }
        }
        .frame(width: settings.popoverWidth, height: settings.popoverHeight)
        .overlay(alignment: .trailing) { resizeHandle(axis: .horizontal) }
        .overlay(alignment: .bottom) { resizeHandle(axis: .vertical) }
        .overlay(alignment: .bottomTrailing) { resizeHandle(axis: .both) }
        .onKeyPress(.escape) {
            NSApp.keyWindow?.close()
            return .handled
        }
        .onAppear {
            handleDayChangeIfNeeded()
            setupNotificationHandlers()
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            handleDayChangeIfNeeded()
        }
    }

    // 가장자리/코너 드래그 핸들. 드래그 시작 시 현재 크기를 기준점으로 잡고,
    // translation을 누적해 AppSettings에 반영. min 이하로 줄지 못하게 클램프.
    // 히트 영역은 넉넉하게(엣지 14pt, 코너 22pt) 잡아 호버가 자주 잡히도록 함.
    @ViewBuilder
    private func resizeHandle(axis: ResizeAxis) -> some View {
        let edgeThickness: CGFloat = 14
        let cornerSize: CGFloat = 22
        let cursor: NSCursor = {
            switch axis {
            case .horizontal: return .resizeLeftRight
            case .vertical: return .resizeUpDown
            case .both: return .crosshair
            }
        }()

        Color.clear
            .contentShape(Rectangle())
            .frame(
                width: axis == .vertical ? nil : (axis == .both ? cornerSize : edgeThickness),
                height: axis == .horizontal ? nil : (axis == .both ? cornerSize : edgeThickness)
            )
            // onContinuousHover는 onHover보다 안정적으로 진입/이탈을 잡고,
            // 매 프레임 set()을 호출해 다른 영역과의 충돌(스택 누락)을 방지.
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    cursor.set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        cursor.set() // 드래그 중에도 커서 유지.
                        if dragStartWidth == nil { dragStartWidth = settings.popoverWidth }
                        if dragStartHeight == nil { dragStartHeight = settings.popoverHeight }

                        let dx = value.translation.width
                        let dy = value.translation.height

                        if axis != .vertical, let baseW = dragStartWidth {
                            settings.popoverWidth = settings.clampWidth(baseW + dx)
                        }
                        if axis != .horizontal, let baseH = dragStartHeight {
                            settings.popoverHeight = settings.clampHeight(baseH + dy)
                        }
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        dragStartHeight = nil
                    }
            )
    }

    // 메뉴바 popover에서 키보드 단축키 처리.
    // .onKeyPress / .onDeleteCommand 는 SwiftUI 포커스 의존이라 신뢰성 부족.
    // NSEvent local monitor로 keyDown을 직접 받음.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 입력창 포커스 또는 수정 중에는 모든 단축키(방향키 포함) 비활성.
            // 텍스트 커서 이동/편집이 우선이라 행 선택 이동은 막아야 함.
            guard !self.isInputFocused, self.editingTaskId == nil else { return event }

            switch event.keyCode {
            case 126: // Up arrow → 이전 항목 (끝에서 처음으로 순환)
                self.moveSelection(by: -1)
                return nil
            case 125: // Down arrow → 다음 항목 (처음에서 끝으로 순환)
                self.moveSelection(by: 1)
                return nil
            case 123: // Left arrow → 이전 루트 항목
                self.moveRootSelection(by: -1)
                return nil
            case 124: // Right arrow → 다음 루트 항목
                self.moveRootSelection(by: 1)
                return nil
            case 6 where event.modifierFlags.contains([.command, .shift]): // Cmd+Shift+Z → redo
                self.modelContext.undoManager?.redo()
                return nil
            case 6 where event.modifierFlags.contains(.command): // Cmd+Z → undo
                self.modelContext.undoManager?.undo()
                return nil
            default:
                break
            }

            guard let id = self.selectedTaskId, let task = self.findTask(by: id) else { return event }

            switch event.keyCode {
            case 51: // Delete(Backspace) → 항목 삭제
                withAnimation {
                    TaskService.deleteTask(task, context: self.modelContext)
                }
                self.selectedTaskId = nil
                return nil
            case 49: // Space → 진행/대기 토글
                withAnimation {
                    TaskService.toggleInProgress(task, context: self.modelContext)
                }
                return nil
            case 36, 76: // Return / Enter → 완료/미완료 토글
                withAnimation {
                    TaskService.toggleComplete(task, context: self.modelContext)
                }
                return nil
            default:
                return event
            }
        }
    }

    // 위/아래 방향키로 보이는 행 사이에서 선택을 이동. 양 끝에서 순환.
    // 선택 없을 때 아래키는 첫 항목, 위키는 마지막 항목으로.
    private func moveSelection(by delta: Int) {
        let items = flattenedTasks
        guard !items.isEmpty else { return }
        applySelection(in: items.map(\.id), delta: delta)
    }

    // 좌/우 방향키로 루트(메인) 항목 사이에서만 이동. 양 끝에서 순환.
    // 자식이 선택돼 있으면 해당 자식이 속한 루트의 인접 루트로 이동.
    private func moveRootSelection(by delta: Int) {
        let roots = rootTasks
        guard !roots.isEmpty else { return }
        let ids = roots.map(\.id)

        if let current = selectedTaskId,
           let currentRoot = findTask(by: current).map(rootOf),
           let idx = ids.firstIndex(of: currentRoot.id) {
            let count = ids.count
            let target = ((idx + delta) % count + count) % count
            updateSelection(to: ids[target])
        } else {
            updateSelection(to: delta >= 0 ? ids.first! : ids.last!)
        }
    }

    private func applySelection(in ids: [UUID], delta: Int) {
        guard !ids.isEmpty else { return }
        let nextId: UUID
        if let current = selectedTaskId, let idx = ids.firstIndex(of: current) {
            let count = ids.count
            let target = ((idx + delta) % count + count) % count
            nextId = ids[target]
        } else {
            // 선택 없음(또는 선택된 항목이 사라짐): ↓는 첫 루트, ↑는 마지막 루트.
            let roots = rootTasks
            guard let first = roots.first, let last = roots.last else { return }
            nextId = delta >= 0 ? first.id : last.id
        }
        updateSelection(to: nextId)
    }

    private func updateSelection(to id: UUID) {
        // 방향키 이동 시 입력창 포커스는 건드리지 않음. 사용자가 입력 중에도 선택만 이동.
        selectedTaskId = id
        scrollTargetId = id
    }

    // 드롭 완료 후: 이동한 항목으로 자동 스크롤 + 1.5초 동안 배경 하이라이트.
    // 부모-자식 관계가 바뀌어 들여쓰기가 깊어진 항목도 사용자가 시각적으로 추적 가능.
    private func handleDropCompleted(_ id: UUID) {
        scrollTargetId = id
        recentlyDroppedId = id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if recentlyDroppedId == id {
                withAnimation(.easeOut(duration: 0.3)) {
                    recentlyDroppedId = nil
                }
            }
        }
    }

    private func rootOf(_ task: TodoTask) -> TodoTask {
        var node = task
        while let parent = node.parent {
            node = parent
        }
        return node
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleDayChangeIfNeeded() {
        let newDayStart = Calendar.current.startOfDay(for: .now)
        if selectedDate == currentDayStart {
            selectedDate = newDayStart
        }
        currentDayStart = newDayStart
        TaskService.checkCarryOver(context: modelContext)
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            HeaderView(selectedDate: $selectedDate)

            Divider()

            taskList

            Divider()

            TaskInputView(
                selectedTask: selectedTask,
                editingTask: editingTask,
                assignedDate: selectedDate,
                onClearSelection: { selectedTaskId = nil },
                onFinishEditing: { editingTaskId = nil },
                onTaskCreated: { newId in scrollTargetId = newId },
                isInputFocused: $isInputFocused
            )
            .padding(.vertical, 4)
        }
    }

    private var taskList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(flattenedTasks, id: \.id) { task in
                        TaskRowView(
                            task: task,
                            isSelected: selectedTaskId == task.id,
                            isRecentlyDropped: recentlyDroppedId == task.id,
                            onSelect: {
                                // 행 선택 시 입력창 포커스 해제 → Backspace로 항목 삭제 가능.
                                isInputFocused = false
                                if selectedTaskId == task.id {
                                    selectedTaskId = nil
                                } else {
                                    selectedTaskId = task.id
                                }
                            },
                            onEdit: {
                                selectedTaskId = task.id
                                editingTaskId = task.id
                            },
                            onDropped: { droppedId in
                                handleDropCompleted(droppedId)
                            },
                            dragState: dragState
                        )
                        .id(task.id)
                        .contextMenu {
                            taskContextMenu(task)
                        }
                    }

                    if flattenedTasks.isEmpty {
                        emptyState
                    }

                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTaskId = nil }
                }
                .onPreferenceChange(RowFramePreference.self) { frames in
                    // 매 갱신마다 완전 교체 — 이전 날짜·삭제된 행의 frame이 누적돼
                    // 드롭 hit-test에 끼어드는 stale frame 버그 방지.
                    dragState.replaceFrames(frames)
                }
            }
            .coordinateSpace(name: "taskList")
            .frame(minHeight: 80)
            .onChange(of: scrollTargetId) { _, newValue in
                guard let id = newValue else { return }
                // SwiftData @Query 갱신 후 새 행이 LazyVStack에 등장한 다음 스크롤되도록 다음 frame으로 미룸.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    scrollTargetId = nil
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("할 일이 없어요")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    @ViewBuilder
    private func taskContextMenu(_ task: TodoTask) -> some View {
        // 타이머 미실행 + 미완료 항목에 대해 수동 진행 토글.
        if task.status != .completed, !task.isTimerRunning {
            Button(task.status == .inProgress ? "진행 중지" : "진행 시작") {
                TaskService.toggleInProgress(task, context: modelContext)
            }
        }

        if task.plannedDuration != nil {
            Menu("시간 변경") {
                Button("15분") { TaskService.updatePlannedDuration(task, duration: 15 * 60, context: modelContext) }
                Button("25분") { TaskService.updatePlannedDuration(task, duration: 25 * 60, context: modelContext) }
                Button("45분") { TaskService.updatePlannedDuration(task, duration: 45 * 60, context: modelContext) }
                Button("60분") { TaskService.updatePlannedDuration(task, duration: 60 * 60, context: modelContext) }
            }
        }

        Button("삭제", role: .destructive) {
            withAnimation {
                TaskService.deleteTask(task, context: modelContext)
            }
        }
    }

    private var selectedTask: TodoTask? {
        guard let id = selectedTaskId else { return nil }
        return findTask(by: id)
    }

    private var editingTask: TodoTask? {
        guard let id = editingTaskId else { return nil }
        return findTask(by: id)
    }

    private func findTask(by id: UUID) -> TodoTask? {
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    // 선택 날짜에 표시할 task id 집합.
    // 1) assignedDate가 selectedDate인 task — 본체.
    // 2) 그 task의 직속 조상 체인 — 컨텍스트 노출용.
    // 같은 부모의 다른 날짜 자식들은 포함 안 함(시야에서 가려짐).
    private var relevantTaskIds: Set<UUID> {
        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let direct = allTasks.filter { $0.assignedDate >= dayStart && $0.assignedDate < dayEnd }
        var ids = Set(direct.map(\.id))
        for task in direct {
            var current = task.parent
            while let node = current {
                guard ids.insert(node.id).inserted else { break }
                current = node.parent
            }
        }
        return ids
    }

    private var rootTasks: [TodoTask] {
        let ids = relevantTaskIds
        return allTasks
            .filter { $0.parent == nil && ids.contains($0.id) }
            .sorted(by: orderedByActive)
    }

    private var flattenedTasks: [TodoTask] {
        let ids = relevantTaskIds
        var result: [TodoTask] = []
        for task in rootTasks {
            flatten(task, into: &result, allowedIds: ids)
        }
        return result
    }

    private func flatten(_ task: TodoTask, into list: inout [TodoTask], allowedIds: Set<UUID>) {
        list.append(task)
        // 자식 중 표시 대상에 포함된 것만 재귀(다른 날짜 자식은 숨김).
        for child in task.sortedChildren where allowedIds.contains(child.id) {
            flatten(child, into: &list, allowedIds: allowedIds)
        }
    }

    // 진행 중(또는 진행 중 후손을 가진 트리)을 같은 레벨에서 위로 올림.
    // 같은 활성 상태 안에서는 기존 sortOrder 유지.
    private func orderedByActive(_ a: TodoTask, _ b: TodoTask) -> Bool {
        let aActive = subtreeContainsInProgress(a)
        let bActive = subtreeContainsInProgress(b)
        if aActive != bActive { return aActive }
        return a.sortOrder < b.sortOrder
    }

    private func subtreeContainsInProgress(_ task: TodoTask) -> Bool {
        if task.status == .inProgress { return true }
        return task.children.contains { subtreeContainsInProgress($0) }
    }

    private func setupNotificationHandlers() {
        NotificationManager.shared.onTimerExtend = { [self] taskId, seconds in
            guard let uuid = UUID(uuidString: taskId) else { return }
            if let task = findTask(by: uuid) {
                TaskService.extendTimer(task, by: seconds, context: modelContext)
            }
        }

        NotificationManager.shared.onTaskComplete = { [self] taskId in
            guard let uuid = UUID(uuidString: taskId) else { return }
            if let task = findTask(by: uuid) {
                TaskService.toggleComplete(task, context: modelContext)
            }
        }
    }
}

private enum ResizeAxis {
    case horizontal
    case vertical
    case both
}
