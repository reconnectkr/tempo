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
    @State private var dragStartPanelWidth: CGFloat?
    @State private var recentlyDroppedId: UUID?
    // 각 메인 섹션의 폴드 상태. 기본은 활성 두 섹션 펼침 / 완료는 접힘.
    @State private var isActiveExpanded = true
    @State private var isQueueExpanded = true
    @State private var isCompletedExpanded = false
    // 패널이 열려 있는지 여부. 선택 상태와 분리해 별도로 관리.
    // 항목 선택 → 자동 열림. 선택 해제만으로는 닫히지 않음(삭제 후에도 패널 폭 유지하기 위함).
    // 명시적 닫기는 빈 영역 클릭에서만 발생.
    @State private var isPanelOpen: Bool = false
    @FocusState private var isInputFocused: Bool

    private var totalWidth: CGFloat {
        settings.popoverWidth + (isPanelOpen && carryOverTasks.isEmpty ? settings.detailPanelWidth : 0)
    }

    var body: some View {
        Group {
            if !carryOverTasks.isEmpty {
                CarryOverView()
            } else {
                splitView
            }
        }
        .frame(width: totalWidth, height: settings.popoverHeight)
        .overlay(alignment: .trailing) { resizeHandle(axis: .horizontal) }
        .overlay(alignment: .bottom) { resizeHandle(axis: .vertical) }
        .overlay(alignment: .bottomTrailing) { resizeHandle(axis: .both) }
        .onChange(of: selectedTaskId) { _, newValue in
            // 항목을 선택하면 패널 자동 열림. 선택 해제(예: 삭제)는 패널을 닫지 않음 —
            // 삭제 시 popover가 갑자기 좁아지는 시각적 점프를 피하기 위함.
            if newValue != nil { isPanelOpen = true }
            settings.detailPanelOpen = isPanelOpen && carryOverTasks.isEmpty
        }
        .onChange(of: isPanelOpen) { _, _ in
            settings.detailPanelOpen = isPanelOpen && carryOverTasks.isEmpty
        }
        .onChange(of: carryOverTasks.isEmpty) { _, mainVisible in
            // carry-over 화면에서는 패널 폭 누적 안 함.
            settings.detailPanelOpen = mainVisible && isPanelOpen
        }
        .onKeyPress(.escape) {
            // 수정 중이면 수정 취소가 우선. 그 외에는 팝오버 닫기.
            if editingTaskId != nil {
                editingTaskId = nil
                return .handled
            }
            NSApp.keyWindow?.close()
            return .handled
        }
        .onAppear {
            handleDayChangeIfNeeded()
            setupNotificationHandlers()
            installKeyMonitor()
            settings.detailPanelOpen = isPanelOpen && carryOverTasks.isEmpty
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
            // 텍스트 입력 위젯에 포커스가 있으면 모든 단축키 비활성.
            // SwiftUI의 TextField/TextEditor는 내부적으로 NSTextView를 first responder로 만들기 때문에
            // 이 한 줄로 디테일 패널·인라인 수정·새 입력 등 모든 텍스트 편집 상황을 한꺼번에 보호함.
            // 텍스트 편집 중에는 Backspace가 항목 삭제로, 방향키가 행 이동으로 잡히면 안 됨.
            if isTextInputActive() { return event }
            guard !self.isInputFocused, self.editingTaskId == nil else { return event }

            switch event.keyCode {
            case 126: // Up arrow → 이전 항목 (끝에서 처음으로 순환)
                self.moveSelection(by: -1)
                return nil
            case 125: // Down arrow → 다음 항목 (처음에서 끝으로 순환)
                self.moveSelection(by: 1)
                return nil
            case 123 where !event.modifierFlags.contains(.command): // Left arrow → 이전 루트 항목
                self.moveRootSelection(by: -1)
                return nil
            case 124 where !event.modifierFlags.contains(.command): // Right arrow → 다음 루트 항목
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
            case 124 where event.modifierFlags.contains(.command): // Cmd+→ → 다음날로 이동
                withAnimation {
                    TaskService.moveByDays(task, days: 1, context: self.modelContext)
                }
                self.selectedTaskId = nil
                return nil
            case 123 where event.modifierFlags.contains(.command): // Cmd+← → 이전날로 이동
                withAnimation {
                    TaskService.moveByDays(task, days: -1, context: self.modelContext)
                }
                self.selectedTaskId = nil
                return nil
            case 14 where event.modifierFlags.contains(.command): // Cmd+E → 수정
                self.editingTaskId = task.id
                return nil
            case 3 where event.modifierFlags.contains(.command): // Cmd+F → FOCUS 토글
                withAnimation {
                    TaskService.toggleFocus(task, context: self.modelContext)
                }
                return nil
            default:
                return event
            }
        }
    }

    // 위/아래 방향키로 보이는 행 사이에서 선택을 이동. 양 끝에서 순환.
    // 이동 대상은 화면 순서와 일치: 진행 중(FOCUS+inProgress) → QUEUE → COMPLETED.
    // 폴드된 섹션은 보이지 않으므로 navigation에서도 제외.
    private func moveSelection(by delta: Int) {
        var items: [UUID] = []
        if isActiveExpanded {
            items.append(contentsOf: flattenedFocusedTasks.map(\.id))
            items.append(contentsOf: inProgressMainFlattened.map(\.id))
        }
        if isQueueExpanded {
            items.append(contentsOf: queueMainFlattened.map(\.id))
        }
        if isCompletedExpanded {
            items.append(contentsOf: completedTasks.map(\.id))
        }
        guard !items.isEmpty else { return }
        applySelection(in: items, delta: delta)
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

    // 키 모니터가 현재 텍스트 편집 중인지 판별.
    // NSTextView를 직접 검사하고, 추가로 NSText(에디팅 중인 NSTextField는 내부 field editor가
    // NSTextView 인스턴스이므로 첫 번째 조건에서 잡힘)도 함께 본다.
    private func isTextInputActive() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView { return true }
        if let text = responder as? NSText, text.isEditable { return true }
        return false
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

    // 리스트 + (선택 시) 디테일 패널을 가로 분할. 사이에 드래그 가능한 구분자.
    @ViewBuilder
    private var splitView: some View {
        HStack(spacing: 0) {
            mainView
                .frame(width: settings.popoverWidth)

            if isPanelOpen {
                panelSeparator
                Group {
                    if let task = selectedTask {
                        TaskDetailPanelView(task: task)
                    } else {
                        // 항목이 선택되지 않은 상태(예: 삭제 직후) — 스켈레톤 자리표시자.
                        // 패널 폭은 그대로 유지해 popover 크기 변화로 인한 시각적 점프 방지.
                        TaskDetailPanelSkeletonView()
                    }
                }
                .frame(width: settings.detailPanelWidth)
            }
        }
    }

    // 리스트와 패널 사이의 세로 구분자. 드래그로 패널 폭 조정.
    // 마우스를 오른쪽으로 끌면 패널이 좁아짐(=리스트가 넓어짐)이 직관적이라
    // dx 만큼 detailPanelWidth에서 빼는 방향으로 매핑.
    @ViewBuilder
    private var panelSeparator: some View {
        Divider()
            .overlay(
                Color.clear
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active: NSCursor.resizeLeftRight.set()
                        case .ended: NSCursor.arrow.set()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                NSCursor.resizeLeftRight.set()
                                if dragStartPanelWidth == nil {
                                    dragStartPanelWidth = settings.detailPanelWidth
                                }
                                let dx = value.translation.width
                                if let base = dragStartPanelWidth {
                                    settings.detailPanelWidth = settings.clampDetailPanelWidth(base - dx)
                                }
                            }
                            .onEnded { _ in dragStartPanelWidth = nil }
                    )
            )
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
                    if hasAnyActive {
                        VStack(spacing: 0) {
                            sectionHeader(
                                title: "INPROGRESS",
                                count: activeTotalCount,
                                icon: "play.fill",
                                tint: .teal,
                                expanded: isActiveExpanded
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) { isActiveExpanded.toggle() }
                            }
                            if isActiveExpanded {
                                activeSectionBody
                            }
                        }
                    }

                    if !queueMainFlattened.isEmpty {
                        VStack(spacing: 0) {
                            sectionHeader(
                                title: "QUEUE",
                                count: queueMainFlattened.count,
                                icon: "tray",
                                tint: .secondary,
                                expanded: isQueueExpanded
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) { isQueueExpanded.toggle() }
                            }
                            if isQueueExpanded {
                                mainSectionRows(queueMainFlattened)
                            }
                        }
                    }

                    if !completedTasks.isEmpty {
                        VStack(spacing: 0) {
                            sectionHeader(
                                title: "COMPLETED",
                                count: completedTasks.count,
                                icon: "checkmark.seal",
                                tint: .blue,
                                expanded: isCompletedExpanded
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) { isCompletedExpanded.toggle() }
                            }
                            if isCompletedExpanded {
                                completedSectionRows
                            }
                        }
                        .background(Color.blue.opacity(0.05))
                    }

                    if isAllEmpty {
                        emptyState
                    }

                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // 빈 영역 클릭은 명시적 닫기 — 선택 해제와 함께 패널도 닫는다.
                            selectedTaskId = nil
                            isPanelOpen = false
                        }
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
                _Concurrency.Task { @MainActor in
                    try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    scrollTargetId = nil
                }
            }
        }
    }

    // MARK: - 섹션 빌더

    @ViewBuilder
    private func sectionHeader(
        title: String,
        count: Int?,
        icon: String,
        tint: Color,
        expanded: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        Button(action: onToggle) {
            HStack(spacing: 7) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(tint)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(tint)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint.opacity(0.7))
                }
                Rectangle()
                    .fill(tint.opacity(0.25))
                    .frame(height: 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // INPROGRESS 메인의 내부 본문. FOCUS만 서브헤더로 강조(빨강 배경), 그 외 일반 진행 중 항목은
    // 메인 헤더(INPROGRESS) 하위라는 게 명확하므로 별도 서브헤더 없이 청록 배경으로만 구분.
    // 자식 단독으로 inProgress인 경우 FOCUS와 동일하게 부모 경로 라벨로 컨텍스트 보존.
    @ViewBuilder
    private var activeSectionBody: some View {
        if !focusedRoots.isEmpty {
            VStack(spacing: 0) {
                queueSubHeader(title: "FOCUS", count: flattenedFocusedTasks.count, tint: .red, icon: "target")
                focusTreeRows(focusedRoots)
            }
            .background(Color.red.opacity(0.14))
        }
        if !inProgressRoots.isEmpty {
            VStack(spacing: 0) {
                inProgressTreeRows
            }
            .background(Color.teal.opacity(0.05))
        }
    }

    @ViewBuilder
    private var inProgressTreeRows: some View {
        ForEach(inProgressRoots, id: \.id) { root in
            if root.depth > 0, let path = ancestorPath(of: root) {
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.top, 2)
            }
            ForEach(flattenedInProgressTreeWithDepth(root), id: \.0.id) { pair in
                queueRow(pair.0, depthOverride: pair.1)
            }
        }
    }

    private var hasAnyActive: Bool {
        !focusedRoots.isEmpty || !inProgressMainFlattened.isEmpty
    }

    private var activeTotalCount: Int {
        flattenedFocusedTasks.count + inProgressMainFlattened.count
    }

    @ViewBuilder
    private func focusTreeRows(_ roots: [TodoTask]) -> some View {
        // 같은 부모를 가진 root들을 그룹화 → 부모 경로 라벨이 자식마다 반복되지 않게 한 번만.
        let groups = groupedRootsByParent(roots)
        ForEach(groups.indices, id: \.self) { idx in
            let group = groups[idx]
            if group.parent != nil, let path = ancestorPath(of: group.roots[0]) {
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.top, 2)
            }
            ForEach(group.roots, id: \.id) { root in
                ForEach(flattenedFocusTreeWithDepth(root), id: \.0.id) { pair in
                    focusRow(pair.0, depthOverride: pair.1)
                }
            }
        }
    }

    private struct RootGroup {
        let parent: TodoTask?
        var roots: [TodoTask]
    }

    private func groupedRootsByParent(_ roots: [TodoTask]) -> [RootGroup] {
        var groups: [RootGroup] = []
        for root in roots {
            let parentId = root.parent?.id
            if let idx = groups.firstIndex(where: { $0.parent?.id == parentId }) {
                groups[idx].roots.append(root)
            } else {
                groups.append(RootGroup(parent: root.parent, roots: [root]))
            }
        }
        return groups
    }

    // 메인 섹션(진행 중 / QUEUE)의 행 묶음. queueSectionRows의 단순 치환.
    @ViewBuilder
    private func mainSectionRows(_ tasks: [TodoTask]) -> some View {
        ForEach(tasks, id: \.id) { task in
            queueRow(task)
        }
    }

    private func focusRow(_ task: TodoTask, depthOverride: Int? = nil) -> some View {
        TaskRowView(
            task: task,
            isSelected: selectedTaskId == task.id,
            isRecentlyDropped: recentlyDroppedId == task.id,
            onSelect: { handleRowTap(task) },
            onEdit: { handleRowEdit(task) },
            onDropped: { handleDropCompleted($0) },
            dragState: dragState,
            inFocusSection: true,
            depthOverride: depthOverride
        )
        // FOCUS·QUEUE 두 영역에 같은 task가 보일 수 있어 prefix 붙인 별도 identity로 분리.
        .id("focus-\(task.id.uuidString)")
        .contextMenu { taskContextMenu(task) }
    }

    private func queueRow(_ task: TodoTask, depthOverride: Int? = nil) -> some View {
        TaskRowView(
            task: task,
            isSelected: selectedTaskId == task.id,
            isRecentlyDropped: recentlyDroppedId == task.id,
            onSelect: { handleRowTap(task) },
            onEdit: { handleRowEdit(task) },
            onDropped: { handleDropCompleted($0) },
            dragState: dragState,
            inFocusSection: false,
            depthOverride: depthOverride
        )
        .id(task.id)
        .contextMenu { taskContextMenu(task) }
    }

    // COMPLETED 영역의 행. TaskRowView를 그대로 사용해 드래그앤드롭이 자동 적용됨.
    // 같은 task가 다른 영역에도 보일 가능성은 없지만(status 분기로 배타) 일관성을 위해
    // id에 "completed-" prefix 부여.
    private func completedRow(_ task: TodoTask, depthOverride: Int) -> some View {
        TaskRowView(
            task: task,
            isSelected: selectedTaskId == task.id,
            isRecentlyDropped: recentlyDroppedId == task.id,
            onSelect: { handleRowTap(task) },
            onEdit: { handleRowEdit(task) },
            onDropped: { handleDropCompleted($0) },
            dragState: dragState,
            inFocusSection: false,
            depthOverride: depthOverride
        )
        .id("completed-\(task.id.uuidString)")
        .contextMenu { taskContextMenu(task) }
    }

    @ViewBuilder
    private func queueSubHeader(title: String, count: Int, tint: Color = .purple, icon: String? = "play.fill") -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(tint)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var completedSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCompletedExpanded.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isCompletedExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.blue)
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.blue)
                Text("COMPLETED")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.blue)
                Text("\(completedTasks.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.blue.opacity(0.7))
                Rectangle()
                    .fill(Color.blue.opacity(0.25))
                    .frame(height: 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var completedSectionRows: some View {
        // 시각 정순을 유지하면서 인접한 같은 트리 root끼리 묶음.
        // 그룹 안에 트리 root(parent=nil)도 들어 있으면 부모-자식 트리 형태로 들여쓰기 표시.
        // root가 그룹에 없으면 출처 부모 경로를 그룹 헤더로 한 번만 노출.
        ForEach(completedGroups.indices, id: \.self) { idx in
            let group = completedGroups[idx]
            let hasRoot = group.tasks.contains { $0.parent == nil }
            // 그룹 안에서 가장 얕은 depth를 기준으로 들여쓰기 정렬.
            let baseDepth = group.tasks.map(\.depth).min() ?? 0

            if !hasRoot, let first = group.tasks.first, first.parent != nil,
               let path = ancestorPath(of: first) {
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.top, 2)
            }

            ForEach(group.tasks, id: \.id) { task in
                completedRow(task, depthOverride: task.depth - baseDepth)
            }
        }
    }

    private struct CompletedGroup {
        let rootId: UUID
        var tasks: [TodoTask]
    }

    // 같은 트리에 속한 (부모 또는 자손) 항목들이 시간상 인접하면 한 그룹으로 묶음.
    // 그룹 안 정렬은 depth 오름차순 — 부모가 먼저, 자식이 그 아래로 들여쓰기.
    private var completedGroups: [CompletedGroup] {
        var groups: [CompletedGroup] = []
        for task in completedTasks {
            let rid = rootIdOf(task)
            if var last = groups.last, last.rootId == rid {
                last.tasks.append(task)
                groups[groups.count - 1] = last
            } else {
                groups.append(CompletedGroup(rootId: rid, tasks: [task]))
            }
        }
        for i in groups.indices {
            groups[i].tasks.sort { $0.depth < $1.depth }
        }
        return groups
    }

    private func rootIdOf(_ task: TodoTask) -> UUID {
        var current = task
        while let parent = current.parent {
            current = parent
        }
        return current.id
    }

    private func handleRowTap(_ task: TodoTask) {
        // 행 선택 시 입력창 포커스 해제 → Backspace로 항목 삭제 가능.
        isInputFocused = false
        // 다른 항목을 선택하면 수정 모드 자동 해제.
        if editingTaskId != nil, editingTaskId != task.id {
            editingTaskId = nil
        }
        if selectedTaskId == task.id {
            selectedTaskId = nil
        } else {
            selectedTaskId = task.id
        }
    }

    private func handleRowEdit(_ task: TodoTask) {
        selectedTaskId = task.id
        editingTaskId = task.id
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
            selectedTaskId = task.id
            editingTaskId = task.id
        }
        .keyboardShortcut("e", modifiers: .command)

        Button(task.status == .completed ? "완료 해제" : "완료") {
            withAnimation {
                TaskService.toggleComplete(task, context: modelContext)
            }
        }
        .keyboardShortcut(.return, modifiers: [])

        // FOCUS 토글. 완료된 항목은 메뉴에서 숨김 (완료 시 자동 해제됨).
        if task.status != .completed {
            Button(task.isFocused ? "포커스에서 내리기" : "포커스에 올리기") {
                withAnimation {
                    TaskService.toggleFocus(task, context: modelContext)
                }
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        // 타이머 미실행 + 미완료 항목에 대해 수동 진행 토글.
        if task.status != .completed, !task.isTimerRunning {
            Button(task.status == .inProgress ? "진행 중지" : "진행 시작") {
                TaskService.toggleInProgress(task, context: modelContext)
            }
            .keyboardShortcut(.space, modifiers: [])
        }

        if task.plannedDuration != nil {
            Menu("시간 변경") {
                Button("15분") { TaskService.updatePlannedDuration(task, duration: 15 * 60, context: modelContext) }
                Button("25분") { TaskService.updatePlannedDuration(task, duration: 25 * 60, context: modelContext) }
                Button("45분") { TaskService.updatePlannedDuration(task, duration: 45 * 60, context: modelContext) }
                Button("60분") { TaskService.updatePlannedDuration(task, duration: 60 * 60, context: modelContext) }
            }
        }

        Button("이전날로 넘기기") {
            withAnimation {
                TaskService.moveByDays(task, days: -1, context: modelContext)
            }
            if selectedTaskId == task.id {
                selectedTaskId = nil
            }
        }
        .keyboardShortcut(.leftArrow, modifiers: .command)

        Button("다음날로 넘기기") {
            withAnimation {
                TaskService.moveByDays(task, days: 1, context: modelContext)
            }
            if selectedTaskId == task.id {
                selectedTaskId = nil
            }
        }
        .keyboardShortcut(.rightArrow, modifiers: .command)

        Button("삭제", role: .destructive) {
            withAnimation {
                TaskService.deleteTask(task, context: modelContext)
            }
            if selectedTaskId == task.id {
                selectedTaskId = nil
            }
        }
        .keyboardShortcut(.delete, modifiers: [])
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
    // 1) 활성 구간 [originalDate, effectiveEnd]에 selectedDate가 포함되는 task — 본체.
    //    effectiveEnd: 미완료면 assignedDate, 완료면 min(assignedDate, 완료일).
    //    즉 3일 전 시작해 지금까지 진행 중인 항목은 3일 전부터 오늘까지 매일 노출됨.
    // 2) 그 task의 직속 조상 체인 — 컨텍스트 노출용.
    // 같은 부모의 다른 날짜 자식들은 포함 안 함(시야에서 가려짐).
    private var relevantTaskIds: Set<UUID> {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        let direct = allTasks.filter { task in
            guard task.originalDate <= dayStart else { return false }
            let baseEnd = task.assignedDate
            let effectiveEnd: Date
            if let completedAt = task.completedAt {
                let completedDay = calendar.startOfDay(for: completedAt)
                effectiveEnd = min(baseEnd, completedDay)
            } else {
                effectiveEnd = baseEnd
            }
            return effectiveEnd >= dayStart
        }
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

    private func flatten(_ task: TodoTask, into list: inout [TodoTask], allowedIds: Set<UUID>, skipFocused: Bool = false, skipInProgress: Bool = false) {
        list.append(task)
        // 자식 중 표시 대상에 포함된 것만 재귀(다른 날짜 자식은 숨김).
        // skipFocused=true면 isFocused 자손은 빠짐 (FOCUS 섹션에 따로 표시).
        // skipInProgress=true면 inProgress 자손도 빠짐 (INPROGRESS 섹션에 따로 표시).
        for child in task.sortedChildren {
            guard allowedIds.contains(child.id) else { continue }
            if skipFocused && child.isFocused { continue }
            if skipInProgress && child.status == .inProgress { continue }
            flatten(child, into: &list, allowedIds: allowedIds, skipFocused: skipFocused, skipInProgress: skipInProgress)
        }
    }

    // FOCUS 메인 안에서 다시 두 서브로 나눔: 진행 중 트리 / 대기 트리.
    private var focusedTreesInProgress: [TodoTask] {
        focusedRoots.filter { subtreeContainsInProgress($0) }
    }
    private var focusedTreesRest: [TodoTask] {
        focusedRoots.filter { !subtreeContainsInProgress($0) }
    }

    private var focusedInProgressFlattened: [TodoTask] {
        flattenedFocusedTasksOf(focusedTreesInProgress)
    }
    private var focusedRestFlattened: [TodoTask] {
        flattenedFocusedTasksOf(focusedTreesRest)
    }

    private func flattenedFocusedTasksOf(_ roots: [TodoTask]) -> [TodoTask] {
        var result: [TodoTask] = []
        for root in roots {
            appendFocusTree(root, into: &result)
        }
        return result
    }

    // INPROGRESS root: 자기는 inProgress, 부모는 inProgress가 아닌(또는 isFocused) 작업.
    // FOCUS의 부모-자식 동반 패턴과 달리 inProgress는 자동 동반이 없어 각각의 inProgress 노드가 root가 됨.
    private var inProgressRoots: [TodoTask] {
        let ids = relevantTaskIds
        return allTasks
            .filter { task in
                task.status == .inProgress &&
                !task.isFocused &&
                ids.contains(task.id) &&
                // 부모가 inProgress이고 not isFocused이면 그 트리의 일부 — root 아님.
                !(task.parent.map { $0.status == .inProgress && !$0.isFocused } ?? false)
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func flattenedInProgressTree(_ root: TodoTask) -> [TodoTask] {
        var result: [TodoTask] = []
        appendInProgressTree(root, into: &result)
        return result
    }

    private func appendInProgressTree(_ task: TodoTask, into list: inout [TodoTask]) {
        list.append(task)
        for child in task.sortedChildren where child.status == .inProgress && !child.isFocused {
            appendInProgressTree(child, into: &list)
        }
    }

    private var inProgressMainFlattened: [TodoTask] {
        var result: [TodoTask] = []
        for root in inProgressRoots {
            appendInProgressTree(root, into: &result)
        }
        return result
    }

    // QUEUE 메인 트리. root 자기 자신만 보고 결정 — !isFocused && !inProgress.
    // 자식이 isFocused이거나 inProgress여도 부모는 QUEUE에 남고, 그 자손은 평탄화에서 스킵.
    private var queueMainTrees: [TodoTask] {
        rootTasks.filter { !$0.isFocused && $0.status != .inProgress }
    }

    private var queueMainFlattened: [TodoTask] {
        let ids = relevantTaskIds
        var result: [TodoTask] = []
        for task in queueMainTrees {
            flatten(task, into: &result, allowedIds: ids, skipFocused: true, skipInProgress: true)
        }
        return result.filter { $0.status != .completed }
    }

    // FOCUS 영역의 루트들. isFocused=true이면서 자신의 부모는 isFocused가 아닌 항목.
    // 부모를 통째로 올린 경우 그 부모가 루트가 되고, 자식만 단독으로 올린 경우엔
    // 자기 자신(depth > 0)이 루트가 된다.
    private var focusedRoots: [TodoTask] {
        let ids = relevantTaskIds
        return allTasks
            .filter { task in
                task.isFocused &&
                task.status != .completed &&
                ids.contains(task.id) &&
                !(task.parent?.isFocused ?? false)
            }
            .sorted { $0.focusOrder < $1.focusOrder }
    }

    // FOCUS 영역 전체를 평탄 리스트로 (방향키 이동·키 모니터용).
    private var flattenedFocusedTasks: [TodoTask] {
        var result: [TodoTask] = []
        for root in focusedRoots {
            result.append(contentsOf: flattenedFocusTree(root))
        }
        return result
    }

    // 단일 FOCUS 루트로부터 isFocused 자손만 들여쓰기 트리로 평탄화.
    private func flattenedFocusTree(_ root: TodoTask) -> [TodoTask] {
        var result: [TodoTask] = []
        appendFocusTree(root, into: &result)
        return result
    }

    private func appendFocusTree(_ task: TodoTask, into list: inout [TodoTask]) {
        list.append(task)
        for child in task.sortedChildren where child.isFocused && child.status != .completed {
            appendFocusTree(child, into: &list)
        }
    }

    // root-기준 상대 depth를 함께 반환. 행 들여쓰기를 root=0으로 맞춰 자식 단독 진입한
    // 항목도 다른 행과 체크박스·텍스트 위치가 정렬됨.
    private func flattenedFocusTreeWithDepth(_ root: TodoTask) -> [(TodoTask, Int)] {
        var result: [(TodoTask, Int)] = []
        appendFocusTreeWithDepth(root, rootDepth: root.depth, into: &result)
        return result
    }

    private func appendFocusTreeWithDepth(_ task: TodoTask, rootDepth: Int, into list: inout [(TodoTask, Int)]) {
        list.append((task, task.depth - rootDepth))
        for child in task.sortedChildren where child.isFocused && child.status != .completed {
            appendFocusTreeWithDepth(child, rootDepth: rootDepth, into: &list)
        }
    }

    private func flattenedInProgressTreeWithDepth(_ root: TodoTask) -> [(TodoTask, Int)] {
        var result: [(TodoTask, Int)] = []
        appendInProgressTreeWithDepth(root, rootDepth: root.depth, into: &result)
        return result
    }

    private func appendInProgressTreeWithDepth(_ task: TodoTask, rootDepth: Int, into list: inout [(TodoTask, Int)]) {
        list.append((task, task.depth - rootDepth))
        for child in task.sortedChildren where child.status == .inProgress && !child.isFocused {
            appendInProgressTreeWithDepth(child, rootDepth: rootDepth, into: &list)
        }
    }

    // 자식 단독 진입 시 출처 부모 경로. depth=0인 항목엔 라벨 안 붙임.
    private func ancestorPath(of task: TodoTask) -> String? {
        var chain: [String] = []
        var current = task.parent
        while let node = current {
            chain.insert(node.title, at: 0)
            current = node.parent
        }
        guard !chain.isEmpty else { return nil }
        return chain.joined(separator: " > ") + " >"
    }

    // COMPLETED 영역. 선택일에 완료된 작업들 (완료 시각 정순).
    private var completedTasks: [TodoTask] {
        let ids = relevantTaskIds
        return allTasks
            .filter { ids.contains($0.id) && $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    private var isAllEmpty: Bool {
        flattenedFocusedTasks.isEmpty &&
        inProgressMainFlattened.isEmpty &&
        queueMainFlattened.isEmpty &&
        completedTasks.isEmpty
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

// COMPLETED 섹션의 행 뷰. 미완료 행과 달리 드래그·타이머·진행 표시가 없고
// 완료 시각과 부모 경로(있다면)만 노출. 클릭 → 선택, 체크박스 → 미완료 복귀.
private struct CompletedRowView: View {
    @Environment(\.modelContext) private var modelContext
    let task: TodoTask
    let isSelected: Bool
    // 그룹 헤더(부모 경로 라벨)가 별도로 그려지는 경우 행 자체엔 경로 생략 — 중복 방지.
    var showParentPath: Bool = true
    // 그룹 안 들여쓰기 (root=0, 자식=1, 손자=2). 부모-자식 트리를 시각화.
    var depth: Int = 0
    let onSelect: () -> Void

    var body: some View {
        // 다른 섹션의 TaskRowView와 메트릭을 맞춤: 체크박스 16pt, vertical 6pt, 우측 텍스트 monospaced 11pt.
        HStack(spacing: 8) {
            Button(action: {
                TaskService.toggleComplete(task, context: modelContext)
            }) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)

            Text(displayTitle)
                .strikethrough()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let completedAt = task.completedAt {
                Text(timeString(completedAt))
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 12 + CGFloat(depth) * 24)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    // 자식 작업이면 부모 경로를 앞에 붙여 컨텍스트 보존: "보고서 작성 > 자료 수집".
    // 그룹 헤더가 별도로 그려질 땐 showParentPath=false로 와서 task.title만 노출.
    private var displayTitle: String {
        guard showParentPath else { return task.title }
        var chain: [String] = []
        var current = task.parent
        while let node = current {
            chain.insert(node.title, at: 0)
            current = node.parent
        }
        if chain.isEmpty { return task.title }
        return chain.joined(separator: " > ") + " > " + task.title
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
