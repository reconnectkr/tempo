import SwiftUI

struct HeaderView: View {
    @Binding var selectedDate: Date
    @State private var showCalendar = false

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd (E)"
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Tempo")
                .font(.headline)

            Spacer()

            Button(action: goToPreviousDay) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: { showCalendar.toggle() }) {
                Text(dateString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                CalendarPickerView(selectedDate: $selectedDate, onSelect: {
                    showCalendar = false
                })
            }

            Button(action: goToNextDay) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func goToPreviousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
    }

    private func goToNextDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
    }
}
