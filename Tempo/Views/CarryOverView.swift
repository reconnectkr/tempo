import SwiftUI
import SwiftData

struct CarryOverView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<TodoTask> { $0.needsCarryOverDecision == true },
        sort: \TodoTask.sortOrder
    ) private var pendingTasks: [TodoTask]

    var body: some View {
        VStack(spacing: 0) {
            CarryOverHeaderView()

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    Text("어제 못 끝낸 일이 \(pendingTasks.count)개 있어요")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                    ForEach(pendingTasks) { task in
                        carryOverItem(task)
                        if task.id != pendingTasks.last?.id {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 0) {
                Button("모두 가져오기") {
                    withAnimation {
                        for task in pendingTasks {
                            TaskService.carryOverToToday(task, context: modelContext)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)

                Divider()
                    .frame(height: 20)

                Button("모두 완료") {
                    withAnimation {
                        for task in pendingTasks {
                            TaskService.completeCarryOver(task, context: modelContext)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func carryOverItem(_ task: TodoTask) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(task.title)
                    .font(.body)
                    .lineLimit(1)

                Spacer()

                Text("\(task.daysActive)일째")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Button("오늘로 가져오기") {
                    withAnimation {
                        TaskService.carryOverToToday(task, context: modelContext)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("완료 처리") {
                    withAnimation {
                        TaskService.completeCarryOver(task, context: modelContext)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct CarryOverHeaderView: View {
    private var todayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd (E)"
        return formatter.string(from: .now)
    }

    var body: some View {
        HStack {
            Text("Tempo")
                .font(.headline)
            Spacer()
            Text(todayString)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
