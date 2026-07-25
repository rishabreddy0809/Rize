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
                        onAdd(CustomTaskRequest(title: trimmed, dueDate: hasTime ? dueDate : nil))
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
