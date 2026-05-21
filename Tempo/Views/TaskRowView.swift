import SwiftUI
import SwiftData

struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var task: TodoTask
    let isSelected: Bool
    var isRecentlyDropped: Bool = false
    let onSelect: () -> Void
    let onEdit: () -> Void
    var onDropped: (UUID) -> Void = { _ in }
    var dragState: DragState
    // true면 FOCUS 영역, false면 QUEUE 영역에서 렌더링됨. QUEUE에서 task.isFocused면 음영 처리.
    var inFocusSection: Bool = false
    // 자식 단독 진입(FOCUS/INPROGRESS) 시 들여쓰기를 root 기준으로 정렬하기 위한 override.
    // nil이면 task.depth 그대로 사용 (QUEUE 일반 행).
    var depthOverride: Int? = nil

    private var effectiveDepth: Int {
        depthOverride ?? task.depth
    }

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // 새 룰: 부모-자식은 상태가 항상 같이 움직임 — FOCUS·INPROGRESS 부모 밑 자식은 추가 시
    // 부모 상태를 상속. 같은 task가 두 섹션에 동시 등장하지 않으므로 dim 표시 불필요.
    private var isDimmedInQueue: Bool { false }

    private var checkboxSymbol: String {
        if task.status == .completed { return "checkmark.circle.fill" }
        // QUEUE 영역의 음영 항목: 점선 원으로 "지금 FOCUS에 올라가 있음" 시각화.
        if isDimmedInQueue { return "circle.dotted" }
        return "circle"
    }

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
                    Image(systemName: checkboxSymbol)
                        .foregroundStyle(task.status == .completed ? Color.accentColor : Color.secondary)
                        .font(.system(size: 16))
                        .opacity(isDimmedInQueue ? 0.4 : 1.0)
                }
                .buttonStyle(.plain)

                Text(task.title)
                    .strikethrough(task.status == .completed)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)
                    .fontWeight(task.status == .inProgress ? .semibold : .regular)
                    .opacity(isDimmedInQueue ? 0.4 : 1.0)
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
            .padding(.leading, CGFloat(effectiveDepth) * 24)
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
        onDropped(source.id)
    }

    private var rowBackground: some View {
        ZStack(alignment: .leading) {
            // 행 배경은 오직 사용자 인터랙션(선택·드롭·하이라이트) 전용. 진행 중 같은 상태는
            // 별도 채널(좌측 세로 bar)로 분리해 시각 충돌을 피한다.
            Group {
                if isRecentlyDropped {
                    Color.yellow.opacity(0.35)
                } else if dropState == .child {
                    Color.accentColor.opacity(0.2)
                } else if dropState == .invalid {
                    Color.red.opacity(0.08)
                } else if isSelected {
                    Color.accentColor.opacity(0.1)
                } else {
                    Color.clear
                }
            }

            // 좌측 마커: 들여쓰기 밖 행 좌측 엣지의 두꺼운 세로 bar. 배경과 독립 채널이라
            // 선택 상태와 동시에 표시돼도 의미가 명확히 구분됨.
            // FOCUS가 우선 — isFocused면 빨강, 그 외 inProgress면 청록.
            if task.isFocused {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 5)
            } else if task.status == .inProgress {
                Rectangle()
                    .fill(Color.teal)
                    .frame(width: 5)
            }
        }
    }

    // 형제로 떨어질 때: 떨어진 항목의 최종 depth(=target.depth)에 맞춰 들여쓴 라인.
    private var siblingDropLine: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: CGFloat(effectiveDepth) * 24 + 12)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 3)
            Spacer().frame(width: 12)
        }
    }

    // 자식으로 떨어질 때: 한 단계 더 들여쓴 ghost line으로 "안으로 들어감"을 시각화.
    private var childDropLine: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: CGFloat(effectiveDepth + 1) * 24 + 12)
            Rectangle()
                .fill(Color.accentColor.opacity(0.7))
                .frame(height: 3)
            Spacer().frame(width: 12)
        }
    }

    @ViewBuilder
    private var timerSection: some View {
        if task.status == .completed, let completedAt = task.completedAt {
            // COMPLETED 행에서는 타이머 자리에 완료 시각을 보여줘 동일 메트릭 유지.
            Text(Self.timeString(completedAt))
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        } else if task.status != .completed, task.plannedDuration != nil {
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

extension TaskRowView {
    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
