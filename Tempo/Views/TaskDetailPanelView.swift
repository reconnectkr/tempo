import SwiftUI
import SwiftData

// 선택된 항목의 상세 정보를 보여주고 편집 가능한 우측 패널.
// 편집 가능 필드: 제목, 할당 날짜, 계획 시간(분), 메모.
// 저장 시점: 각 입력의 포커스가 빠질 때(=focus loss). 별도 저장 버튼 없음.
// 자동 저장은 TaskService 헬퍼를 통해 수행되며, 변경이 없으면 no-op 처리됨.
struct TaskDetailPanelView: View {
    @Environment(\.modelContext) private var modelContext
    let task: TodoTask

    @State private var titleText: String = ""
    @State private var memoText: String = ""
    @State private var durationMinutes: String = ""
    @State private var assignedDate: Date = .now
    @State private var createdAt: Date = .now
    @State private var originalDate: Date = .now
    @State private var completedAt: Date = .now
    @State private var status: TaskStatus = .pending

    // 현재 state 버퍼(titleText/memoText/...)에 로드된 task.
    // task 프로퍼티는 부모가 선택을 바꾸는 즉시 새 task로 갈아끼우기 때문에,
    // 갈아끼운 이후의 커밋에서 task가 가리키는 객체와 버퍼 내용이 어긋남.
    // → 버퍼는 항상 loadedTask에 대해서만 커밋해야 함.
    @State private var loadedTask: TodoTask?

    @FocusState private var titleFocused: Bool
    @FocusState private var memoFocused: Bool
    @FocusState private var durationFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            // 상단(제목·메타)은 자기 자연 높이만큼 차지. 메모는 남은 세로 영역을 모두 채움.
            VStack(alignment: .leading, spacing: 14) {
                titleField
                Divider()
                metaSection
                Divider()
                memoField
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear(perform: loadFromTask)
        .onChange(of: task.id) { _, _ in
            // 다른 항목을 선택하면 이전 항목(loadedTask)의 미저장 변경을 커밋한 뒤 새 항목 로드.
            // task는 이미 새 항목을 가리키므로 commit 대상은 반드시 loadedTask여야 함.
            commitAll()
            loadFromTask()
        }
        .onChange(of: titleFocused) { _, focused in
            if !focused { commitTitle() }
        }
        .onChange(of: memoFocused) { _, focused in
            if !focused { commitMemo() }
        }
        .onChange(of: durationFocused) { _, focused in
            if !focused { commitDuration() }
        }
        .onChange(of: assignedDate) { _, newValue in
            // DatePicker는 포커스 개념이 없어 값 변경 즉시 커밋.
            // 이 변화가 task 전환에 의한 loadFromTask의 부수효과로 생긴 경우에는
            // 새 task의 날짜로 새 task에 쓰는 셈이라 문제 없음.
            guard let target = loadedTask else { return }
            TaskService.updateAssignedDate(target, date: newValue, context: modelContext)
        }
        .onChange(of: createdAt) { _, newValue in
            guard let target = loadedTask else { return }
            TaskService.updateCreatedAt(target, date: newValue, context: modelContext)
        }
        .onChange(of: originalDate) { _, newValue in
            guard let target = loadedTask else { return }
            TaskService.updateOriginalDate(target, date: newValue, context: modelContext)
        }
        .onChange(of: completedAt) { _, newValue in
            // completedAt은 task가 완료 상태일 때만 노출. 그 외에는 wiring 무시.
            guard let target = loadedTask, target.completedAt != nil else { return }
            TaskService.updateCompletedAt(target, date: newValue, context: modelContext)
        }
        .onChange(of: status) { _, newValue in
            guard let target = loadedTask, target.status != newValue else { return }
            TaskService.setStatus(target, to: newValue, context: modelContext)
            // 상태가 completed로 전환되면 부수효과로 completedAt이 .now로 들어감.
            // 그 값을 패널 버퍼에도 반영해 DatePicker가 빈 값으로 깜빡이는 일을 막는다.
            if let updated = target.completedAt {
                completedAt = updated
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            Text("세부 정보")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var statusPicker: some View {
        // 타이머가 돌고 있으면 status는 타이머 라이프사이클에 종속이라 picker는 비활성.
        // 사용자가 직접 바꾸려면 행에서 일시정지부터 해야 함.
        let timerLocked = task.isTimerRunning
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("상태")
            Picker("", selection: $status) {
                Text("대기").tag(TaskStatus.pending)
                Text("진행 중").tag(TaskStatus.inProgress)
                Text("완료").tag(TaskStatus.completed)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .disabled(timerLocked)
            if timerLocked {
                Text("타이머 실행 중에는 상태 변경 불가")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("제목")
            TextField("제목", text: $titleText)
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .onSubmit { commitTitle() }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusPicker

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("할당 날짜")
                DatePicker("", selection: $assignedDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("계획 시간 (분)")
                TextField("미설정", text: $durationMinutes)
                    .textFieldStyle(.plain)
                    .focused($durationFocused)
                    .onSubmit { commitDuration() }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    )
            }

            editableMeta
        }
    }

    @ViewBuilder
    private var editableMeta: some View {
        VStack(alignment: .leading, spacing: 8) {
            metaEditableRow("생성일") {
                DatePicker("", selection: $createdAt, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            metaEditableRow("최초 날짜") {
                DatePicker("", selection: $originalDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            // 경과는 originalDate ↔ assignedDate 차이로 자동 산출 — 별도 편집 불가.
            // 최초 날짜를 바꾸면 자동 갱신됨.
            if task.daysActive > 1 {
                metaRow("경과", value: "\(task.daysActive)일째")
            }
            // 완료일은 항상 노출하되 status에 따라 활성/비활성. 미완료 상태일 때 분기로 숨기면
            // status picker로 완료 전환해도 @State가 아닌 task 프로퍼티에 의존해 뷰가 갱신되지 않아
            // 사용자에게 입력란이 즉시 안 보이는 문제가 있음. 항상 노출이 더 안전하고 일관됨.
            metaEditableRow("완료일") {
                DatePicker("", selection: $completedAt, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .disabled(status != .completed)
                    .opacity(status == .completed ? 1.0 : 0.45)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func metaEditableRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func metaRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var memoField: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel("메모")
            // 메모는 패널의 남은 세로 영역을 모두 차지. 내용이 길면 TextEditor 내부에서 스크롤.
            TextEditor(text: $memoText)
                .font(.body)
                .focused($memoFocused)
                .frame(minHeight: 120, maxHeight: .infinity)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .scrollContentBackground(.hidden)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func loadFromTask() {
        // 새 task의 값을 버퍼에 채우고 loadedTask도 함께 갱신.
        // 순서가 중요: assignedDate 대입이 .onChange(of: assignedDate)를 깨워
        // loadedTask 기준으로 쓰기 때문에, loadedTask를 먼저 갱신해야 안전함.
        loadedTask = task
        titleText = task.title
        memoText = task.memo
        assignedDate = task.assignedDate
        createdAt = task.createdAt
        originalDate = task.originalDate
        status = task.status
        // completedAt이 nil이면 DatePicker 상태값은 의미 없지만, 일관된 기본값(현재 시각) 유지.
        // 완료 상태가 아닐 때는 onChange 가드에서 무시되므로 안전.
        completedAt = task.completedAt ?? .now
        if let duration = task.plannedDuration, duration > 0 {
            durationMinutes = String(Int(duration / 60))
        } else {
            durationMinutes = ""
        }
    }

    private func commitAll() {
        commitTitle()
        commitMemo()
        commitDuration()
    }

    private func commitTitle() {
        guard let target = loadedTask else { return }
        TaskService.updateTitle(target, title: titleText, context: modelContext)
        // 빈 제목을 입력한 경우 원본으로 복귀.
        if titleText.trimmingCharacters(in: .whitespaces).isEmpty {
            titleText = target.title
        }
    }

    private func commitMemo() {
        guard let target = loadedTask else { return }
        TaskService.updateMemo(target, memo: memoText, context: modelContext)
    }

    private func commitDuration() {
        guard let target = loadedTask else { return }
        let trimmed = durationMinutes.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            if target.plannedDuration != nil {
                target.plannedDuration = nil
                try? modelContext.save()
            }
            return
        }
        guard let mins = Double(trimmed), mins > 0 else {
            // 잘못된 입력은 원복.
            if let duration = target.plannedDuration, duration > 0 {
                durationMinutes = String(Int(duration / 60))
            } else {
                durationMinutes = ""
            }
            return
        }
        TaskService.updatePlannedDuration(target, duration: mins * 60, context: modelContext)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f.string(from: date)
    }

    private func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: date)
    }
}

// 선택된 항목이 없을 때(또는 방금 삭제된 직후) 패널 자리를 채우는 placeholder.
// 실제 패널과 비슷한 레이아웃을 회색 막대로 표현해, 항목 삭제 시 popover 폭 점프 없이
// 부드러운 상태 전이를 만든다. 인터랙션은 비활성.
struct TaskDetailPanelSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("세부 정보")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                placeholder(width: 36, height: 14)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                fieldBlock(labelWidth: 24, fieldHeight: 28)
                Divider()
                fieldBlock(labelWidth: 56, fieldHeight: 24)
                fieldBlock(labelWidth: 80, fieldHeight: 28)
                VStack(alignment: .leading, spacing: 6) {
                    placeholder(width: 100, height: 10)
                    placeholder(width: 140, height: 10)
                    placeholder(width: 80, height: 10)
                }
                .padding(.top, 4)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    placeholder(width: 30, height: 10)
                    placeholder(maxWidth: true, height: 160)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Text("항목을 선택하세요")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func fieldBlock(labelWidth: CGFloat, fieldHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            placeholder(width: labelWidth, height: 10)
            placeholder(maxWidth: true, height: fieldHeight)
        }
    }

    @ViewBuilder
    private func placeholder(width: CGFloat? = nil, maxWidth: Bool = false, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.primary.opacity(0.08))
            .frame(width: maxWidth ? nil : width, height: height)
            .frame(maxWidth: maxWidth ? .infinity : nil, alignment: .leading)
    }
}

