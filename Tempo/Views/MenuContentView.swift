import SwiftUI
import SwiftData

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
    @State private var editingTaskId: UUID?
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var hasCheckedCarryOver = false
    @State private var dragState = DragState()

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
        .onAppear {
            if !hasCheckedCarryOver {
                TaskService.checkCarryOver(context: modelContext)
                hasCheckedCarryOver = true
            }
            setupNotificationHandlers()
        }
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
                onFinishEditing: { editingTaskId = nil }
            )
            .padding(.vertical, 4)
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(flattenedTasks, id: \.id) { task in
                    TaskRowView(
                        task: task,
                        isSelected: selectedTaskId == task.id,
                        onSelect: {
                            if selectedTaskId == task.id {
                                selectedTaskId = nil
                            } else {
                                selectedTaskId = task.id
                            }
                        },
                        dragState: dragState
                    )
                    .contextMenu {
                        taskContextMenu(task)
                    }
                }

                if flattenedTasks.isEmpty {
                    emptyState
                }
            }
            .onPreferenceChange(RowFramePreference.self) { frames in
                for (id, frame) in frames {
                    dragState.registerFrame(id, frame: frame)
                }
            }
        }
        .coordinateSpace(name: "taskList")
        .frame(minHeight: 80)
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
        Button("수정") {
            editingTaskId = task.id
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

    private var rootTasks: [TodoTask] {
        let dayStart = Calendar.current.startOfDay(for: selectedDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        return allRootTasks.filter { $0.assignedDate >= dayStart && $0.assignedDate < dayEnd }
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
        for child in task.sortedChildren {
            flatten(child, into: &list)
        }
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
