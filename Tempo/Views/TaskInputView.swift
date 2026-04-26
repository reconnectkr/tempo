import SwiftUI
import SwiftData

struct TaskInputView: View {
    @Environment(\.modelContext) private var modelContext
    let selectedTask: TodoTask?
    let editingTask: TodoTask?
    let assignedDate: Date
    let onClearSelection: () -> Void
    let onFinishEditing: () -> Void

    @State private var inputText = ""
    @State private var durationMinutes = ""
    @FocusState private var isInputFocused: Bool

    private var isEditing: Bool { editingTask != nil }

    private var isDepthLimitReached: Bool {
        guard !isEditing else { return false }
        guard let selected = selectedTask else { return false }
        return selected.depth >= 2
    }

    private var modeLabel: String {
        if isEditing { return "수정" }
        return selectedTask == nil ? "메인" : "하위"
    }

    private var modeLabelIsAccent: Bool {
        isEditing || selectedTask != nil
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(modeLabel)
                    .font(.caption2)
                    .foregroundStyle(modeLabelIsAccent ? Color.accentColor : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(modeLabelIsAccent ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.12))
                    )

                TextField("새 할 일", text: $inputText)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .disabled(isDepthLimitReached)
                    .onSubmit { submit() }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    )

                TextField("분", text: $durationMinutes)
                    .textFieldStyle(.plain)
                    .frame(width: 36)
                    .disabled(isDepthLimitReached)
                    .onSubmit { submit() }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    )

                Button(action: submit) {
                    Image(systemName: "return")
                        .font(.system(size: 12))
                        .foregroundStyle(inputText.isEmpty || isDepthLimitReached ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isDepthLimitReached)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onKeyPress(.escape) {
            if isEditing {
                onFinishEditing()
            } else {
                onClearSelection()
            }
            return .handled
        }
        .onChange(of: editingTask?.id) {
            if let task = editingTask {
                inputText = task.title
                if let duration = task.plannedDuration, duration > 0 {
                    durationMinutes = "\(Int(duration / 60))"
                } else {
                    durationMinutes = ""
                }
                isInputFocused = true
            }
        }
    }

    private func submit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let duration: TimeInterval?
        if let mins = Double(durationMinutes), mins > 0 {
            duration = mins * 60
        } else {
            duration = nil
        }

        if let task = editingTask {
            task.title = trimmed
            if let d = duration {
                TaskService.updatePlannedDuration(task, duration: d, context: modelContext)
            } else {
                task.plannedDuration = nil
                try? modelContext.save()
            }
            onFinishEditing()
        } else {
            TaskService.createTask(
                title: trimmed,
                parent: selectedTask,
                assignedDate: assignedDate,
                plannedDuration: duration,
                context: modelContext
            )
        }

        inputText = ""
        durationMinutes = ""
    }
}
