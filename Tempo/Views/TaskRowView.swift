import SwiftUI
import SwiftData

struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TodoTask
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
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
                siblingDropLine
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
                    // 드래그 제스처는 제목 영역에만 부착(체크박스/타이머 버튼과 충돌 방지).
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
            // 행 어디든 클릭 가능. Button(체크박스/타이머)은 자체 hit-test가 우선이라 영향 없음.
            // 더블 클릭 대기 지연 회피를 위해 single은 즉시, double은 simultaneousGesture.
            .onTapGesture { onSelect() }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { onEdit() }
            )
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: RowFramePreference.self, value: [task.id: geo.frame(in: .named("taskList"))])
                }
            )
            .modifier(DragVisualModifier(isDragging: dragState.draggedTaskId == task.id, offset: dragState.dragOffset))

            if dropState == .below {
                siblingDropLine
            }
            if dropState == .child {
                childDropLine
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
        ZStack(alignment: .leading) {
            // 1. 베이스 색 레이어: drop, selection 등.
            Group {
                if dropState == .child {
                    Color.accentColor.opacity(0.2)
                } else if dropState == .invalid {
                    Color.red.opacity(0.08)
                } else if isSelected {
                    Color.accentColor.opacity(0.1)
                } else {
                    Color.clear
                }
            }

            // 2. 진행 중 워터마크: 행 가로 중앙에 흐린 텍스트.
            if task.status == .inProgress {
                Text("IN PROGRESS")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color.accentColor.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .center)
            }

        }
    }

    // 형제로 떨어질 때: 떨어진 항목의 최종 depth(=target.depth)에 맞춰 들여쓴 라인.
    private var siblingDropLine: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: CGFloat(task.depth) * 24 + 12)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 3)
            Spacer().frame(width: 12)
        }
    }

    // 자식으로 떨어질 때: 한 단계 더 들여쓴 ghost line으로 "안으로 들어감"을 시각화.
    private var childDropLine: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: CGFloat(task.depth + 1) * 24 + 12)
            Rectangle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(height: 3)
            Spacer().frame(width: 12)
        }
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

private struct DragVisualModifier: ViewModifier {
    let isDragging: Bool
    let offset: CGSize

    func body(content: Content) -> some View {
        content
            .opacity(isDragging ? 0.9 : 1.0)
            .offset(isDragging ? offset : .zero)
            .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: 6, y: 3)
            .zIndex(isDragging ? 1 : 0)
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
