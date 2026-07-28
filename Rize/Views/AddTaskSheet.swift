import SwiftUI

/// Sheet for adding a custom task. The category (Workouts / Classes / Work
/// Blocks / Personal) isn't chosen here — `PlanCategory.classify` infers it
/// from the title, same as real calendar events, so the task lands in the
/// right section automatically once added.
struct AddTaskSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: (CustomTaskRequest) -> Void

    @State private var title = ""
    @State private var hasTime = false
    @State private var dueDate = Date()
    @State private var recurrenceDays: Set<Int> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What do you need to do?", text: $title)
                }

                Section {
                    Toggle("Set a time", isOn: $hasTime.animation(Constants.springAnimation))
                    if hasTime {
                        DatePicker("When", selection: $dueDate)
                            .datePickerStyle(.compact)
                    }
                } footer: {
                    Text("Rize sorts it into Workouts, Classes, Work Blocks, or Personal based on what it's about.")
                }

                Section {
                    RepeatDaysPicker(selectedDays: $recurrenceDays)
                } header: {
                    Text("Repeat")
                } footer: {
                    Text(recurrenceDays.isEmpty ? "One-time task." : "Rize will add this back on the days you picked.")
                }
            }
            .navigationTitle("Add Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onAdd(CustomTaskRequest(
                            title: trimmed,
                            dueDate: hasTime ? dueDate : nil,
                            recurrenceDays: recurrenceDays
                        ))
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Seven-day-of-week toggle row shared by `AddTaskSheet` and `EditTaskSheet`.
/// Days are `Calendar` weekday numbers (Sun=1...Sat=7) so they line up
/// directly with `Calendar.current.component(.weekday, from:)` at generation
/// time — no Sun-first-vs-Mon-first remapping needed anywhere else.
struct RepeatDaysPicker: View {
    @Binding var selectedDays: Set<Int>

    private let symbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { weekday in
                let isOn = selectedDays.contains(weekday)
                Button {
                    withAnimation(Constants.springAnimation) {
                        if isOn {
                            selectedDays.remove(weekday)
                        } else {
                            selectedDays.insert(weekday)
                        }
                    }
                } label: {
                    Text(symbols[weekday - 1])
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(isOn ? .white : PhoenixPalette.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(isOn ? PhoenixPalette.primary : PhoenixPalette.textSecondary.opacity(0.12))
                        .clipShape(Circle())
                }
                .accessibilityLabel(Text(weekdayFullName(weekday)))
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func weekdayFullName(_ weekday: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names[weekday - 1]
    }
}
