import SwiftUI
import SwiftData

struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TodoTask
    let isSelected: Bool
    let onSelect: () -> Void
    var dragState: DragState

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var dropState: DropIndicator {
        guard dragState.currentDropTaskId == task.id,
              let mode = dragState.currentDropMode,
              let sourceId = dragState.draggedTaskId,
              sourceId != task.id else {
            return .none
        }

        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.id == sourceId }
        )
        guard let source = try? modelContext.fetch(descriptor).first else { return .none }

        if !TaskService.canDrop(source, onto: task, as: mode) {
            return .invalid
        }

        switch mode {
        case .siblingAbove: return .above
        case .siblingBelow: return .below
        case .child: return .child
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if dropState == .above {
                dropLine
            }

            HStack(spacing: 8) {
                Button(action: {
                    TaskService.toggleComplete(task, context: modelContext)
                }) {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.status == .completed ? Color.accentColor : Color.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)

                Text(task.title)
                    .strikethrough(task.status == .completed)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect() }

                if task.daysActive >= 2, task.status != .completed {
                    Text("O-\(task.daysActive - 1)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }

                timerSection
            }
            .padding(.leading, CGFloat(task.depth) * 24)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(rowBackground)
            .contentShape(Rectangle())
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: RowFramePreference.self, value: [task.id: geo.frame(in: .named("taskList"))])
                }
            )
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("taskList"))
                    .onChanged { value in
                        if !dragState.isDragging {
                            dragState.draggedTaskId = task.id
                        }
                        dragState.dragOffset = value.translation
                        dragState.updateDrop(at: value.location)
                    }
                    .onEnded { _ in
                        performDropIfNeeded()
                        dragState.reset()
                    }
            )
            .opacity(dragState.draggedTaskId == task.id ? 0.4 : 1.0)

            if dropState == .below {
                dropLine
            }
        }
        .onReceive(timer) { _ in
            now = Date()
        }
    }

    private func performDropIfNeeded() {
        guard let sourceId = dragState.draggedTaskId,
              let targetId = dragState.currentDropTaskId,
              let mode = dragState.currentDropMode else { return }

        let srcDesc = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.id == sourceId }
        )
        let tgtDesc = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.id == targetId }
        )

        guard let source = try? modelContext.fetch(srcDesc).first,
              let target = try? modelContext.fetch(tgtDesc).first else { return }

        guard TaskService.canDrop(source, onto: target, as: mode) else { return }

        withAnimation {
            TaskService.performDrop(source, onto: target, as: mode, context: modelContext)
        }
    }

    private var rowBackground: some View {
        Group {
            if dropState == .child {
                Color.accentColor.opacity(0.12)
            } else if dropState == .invalid {
                Color.red.opacity(0.08)
            } else if isSelected {
                Color.accentColor.opacity(0.1)
            } else {
                Color.clear
            }
        }
    }

    private var dropLine: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var timerSection: some View {
        if task.status != .completed, task.plannedDuration != nil {
            if task.isTimerRunning, let endsAt = task.timerEndsAt {
                Button(action: {
                    TaskService.pauseTimer(task, context: modelContext)
                }) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                let remaining = max(0, endsAt.timeIntervalSince(now))
                Text(TimerManager.formatTime(remaining))
                    .monospacedDigit()
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
            } else {
                Button(action: {
                    TaskService.startTimer(task, context: modelContext)
                }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if let duration = task.plannedDuration {
                    let remaining = duration - task.timerAccumulated
                    Text(TimerManager.formatTime(remaining))
                        .monospacedDigit()
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

enum DropIndicator: Equatable {
    case none
    case above
    case below
    case child
    case invalid
}

struct RowFramePreference: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
