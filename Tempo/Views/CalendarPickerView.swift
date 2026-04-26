import SwiftUI
import SwiftData

struct CalendarPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedDate: Date
    var onSelect: () -> Void

    @Query(sort: \TodoTask.assignedDate) private var allTasks: [TodoTask]

    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: .now)

    private let calendar = Calendar.current
    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: displayedMonth)
    }

    private var taskCountByDay: [Date: Int] {
        var counts: [Date: Int] = [:]
        for task in allTasks {
            let day = calendar.startOfDay(for: task.assignedDate)
            counts[day, default: 0] += 1
        }
        return counts
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthYearString)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdaySymbols[i])
                        .font(.caption2)
                        .foregroundStyle(weekdayColor(i))
                        .frame(maxWidth: .infinity)
                }

                ForEach(daysInMonth, id: \.self) { date in
                    if let date {
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let isToday = calendar.isDateInToday(date)
                        let weekday = calendar.component(.weekday, from: date)
                        let day = calendar.startOfDay(for: date)
                        let count = taskCountByDay[day] ?? 0

                        Button(action: {
                            selectedDate = calendar.startOfDay(for: date)
                            onSelect()
                        }) {
                            VStack(spacing: 1) {
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(dayTextColor(isSelected: isSelected, weekday: weekday))

                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 8))
                                        .foregroundStyle(isSelected ? .white : .secondary)
                                } else {
                                    Text(" ")
                                        .font(.system(size: 8))
                                }
                            }
                            .frame(width: 28, height: 34)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor)
                                } else if isToday {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.accentColor, lineWidth: 1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("")
                            .frame(width: 28, height: 34)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 250)
        .onAppear {
            displayedMonth = calendar.startOfDay(for: selectedDate)
        }
    }

    private func weekdayColor(_ index: Int) -> Color {
        if index == 0 { return .red }
        if index == 6 { return .red }
        return .secondary
    }

    private func dayTextColor(isSelected: Bool, weekday: Int) -> Color {
        if isSelected { return .white }
        if weekday == 1 || weekday == 7 { return .red }
        return .primary
    }

    private var daysInMonth: [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = firstWeekday - 1

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)

        for day in range {
            var dc = comps
            dc.day = day
            days.append(calendar.date(from: dc))
        }

        return days
    }

    private func previousMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth)!
    }

    private func nextMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth)!
    }
}
