import SwiftUI
import SwiftData
import AppKit

struct MenuContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<TodoTask> { $0.needsCarryOverDecision == true }
    ) private var carryOverTasks: [TodoTask]

    @Query(
        filter: #Predicate<TodoTask> { $0.parent == nil },
        sort: \TodoTask.sortOrder
    ) private var allRootTasks: [TodoTask]

    @State private var selectedTaskId: UUID?
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var currentDayStart = Calendar.current.startOfDay(for: .now)
    @State private var dragState = DragState()
    @State private var scrollTargetId: UUID?
    @State private var keyMonitor: Any?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Group {
            if !carryOverTasks.isEmpty {
                CarryOverView()
            } else {
                mainView
            }
        }
        .frame(width: 360)
        .frame(minHeight: 480, maxHeight: 700)
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

    // 메뉴바 popover에서 Backspace로 선택 항목 삭제.
    // .onKeyPress / .onDeleteCommand 는 SwiftUI 포커스 의존이라 신뢰성 부족.
    // NSEvent local monitor로 keyDown을 직접 받음.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // keyCode 51 = Delete(Backspace)
            guard event.keyCode == 51 else { return event }
            // 입력창에 포커스가 있으면 텍스트 편집을 우선.
            guard !self.isInputFocused else { return event }
            guard let id = self.selectedTaskId, let task = self.findTask(by: id) else { return event }
            withAnimation {
                TaskService.deleteTask(task, context: self.modelContext)
            }
            self.selectedTaskId = nil
            return nil // 이벤트 소비
        }
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
                assignedDate: selectedDate,
                onClearSelection: { selectedTaskId = nil },
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
                            onSelect: {
                                // 행 선택 시 입력창 포커스 해제 → Backspace로 항목 삭제 가능.
                                isInputFocused = false
                                if selectedTaskId == task.id {
                                    selectedTaskId = nil
                                } else {
                                    selectedTaskId = task.id
                                }
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
                    for (id, frame) in frames {
                        dragState.registerFrame(id, frame: frame)
                    }
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

    private func findTask(by id: UUID) -> TodoTask? {
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private var rootTasks: [TodoTask] {
        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let filtered = allRootTasks.filter { $0.assignedDate >= dayStart && $0.assignedDate < dayEnd }
        return filtered.sorted(by: orderedByActive)
    }

    private var flattenedTasks: [TodoTask] {
        var result: [TodoTask] = []
        for task in rootTasks {
            flatten(task, into: &result)
        }
        return result
    }

    private func flatten(_ task: TodoTask, into list: inout [TodoTask]) {
        list.append(task)
        // 트리 내부는 sortOrder만으로 정렬(원래 순서 유지).
        for child in task.sortedChildren {
            flatten(child, into: &list)
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
