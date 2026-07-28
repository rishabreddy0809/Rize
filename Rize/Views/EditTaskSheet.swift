import SwiftUI

/// What changed about an already-added task. Mirrors `CustomTaskRequest`
/// (`AddTaskSheet`) but the sheet pre-fills from the task's current values
/// and reports the result rather than mutating `RizeTask` directly —
/// `TodayView.applyTaskEdits` is the only place allowed to touch
/// persistence/notifications for it.
struct EditedTaskFields {
    let title: String
    let dueDate: Date?
    let recurrenceDays: Set<Int>
}

struct EditTaskSheet: View {
    @Environment(\.dismiss) private var dismiss

    let task: RizeTask
    let onSave: (EditedTaskFields) -> Void

    @State private var title: String
    @State private var hasTime: Bool
    @State private var dueDate: Date
    @State private var recurrenceDays: Set<Int>

    init(task: RizeTask, onSave: @escaping (EditedTaskFields) -> Void) {
        self.task = task
        self.onSave = onSave
        _title = State(initialValue: task.title)
        _hasTime = State(initialValue: task.dueDate != nil)
        _dueDate = State(initialValue: task.dueDate ?? Date())
        _recurrenceDays = State(initialValue: task.recurrenceDays)
    }

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
                }

                Section {
                    RepeatDaysPicker(selectedDays: $recurrenceDays)
                } header: {
                    Text("Repeat")
                } footer: {
                    Text(recurrenceDays.isEmpty ? "One-time task." : "Rize will add this back on the days you picked.")
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(EditedTaskFields(
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
