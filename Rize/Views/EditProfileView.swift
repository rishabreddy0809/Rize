import SwiftUI
import SwiftData

/// Lets the user revisit and change every choice they made during onboarding —
/// name, goal, and focus-area tags — without having to go through onboarding
/// again. Mirrors the goal/goal-detail pages in `OnboardingView` so the two
/// stay visually consistent.
struct EditProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let profile: UserProfile

    @State private var name: String
    @State private var goal: String
    @State private var selectedGoalTags: Set<String>
    @State private var customGoalTags: [String]
    @State private var goalDetailInput = ""

    init(profile: UserProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _goal = State(initialValue: profile.goal)
        let existingTags = profile.goalDetail
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        _selectedGoalTags = State(initialValue: Set(existingTags))
        _customGoalTags = State(initialValue: existingTags)
    }

    private var goalDetailPresets: [String] {
        switch goal {
        case "fitness":
            return ["Running", "Gym & Strength", "Sports", "Cycling", "Swimming", "Yoga & Flexibility"]
        case "productivity":
            return ["Coding", "Studying", "Reading", "Writing", "Work Habits", "Deep Focus"]
        default:
            return ["Running", "Sports", "Coding", "Studying", "Gym & Strength", "Work Habits"]
        }
    }

    private var allGoalDetailOptions: [String] {
        goalDetailPresets + customGoalTags.filter { !goalDetailPresets.contains($0) }
    }

    private func addCustomGoalTag() {
        let trimmed = goalDetailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        goalDetailInput = ""
        withAnimation(Constants.springAnimation) {
            if !allGoalDetailOptions.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                customGoalTags.append(trimmed)
            }
            selectedGoalTags.insert(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PhoenixBackground()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        nameCard
                        goalCard
                        goalDetailCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Name

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NAME")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
            TextField("Your name", text: $name)
                .font(.system(.body, design: .rounded))
                .foregroundColor(PhoenixPalette.textPrimary)
                .padding(12)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
    }

    // MARK: - Goal

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GOAL")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
            VStack(spacing: 10) {
                goalOption("FITNESS", subtitle: "Running, gym, sports", value: "fitness", icon: "figure.run")
                goalOption("PRODUCTIVITY", subtitle: "Studying, work, habits", value: "productivity", icon: "brain.head.profile")
                goalOption("BOTH", subtitle: "The full flame", value: "both", icon: "sparkles")
            }
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
    }

    @ViewBuilder
    private func goalOption(_ label: String, subtitle: String, value: String, icon: String) -> some View {
        Button {
            withAnimation(Constants.springAnimation) { goal = value }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(goal == value ? PhoenixPalette.primary : PhoenixPalette.textSecondary.opacity(0.6))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundColor(PhoenixPalette.textPrimary)
                    Text(subtitle)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                }
                Spacer()
                if goal == value {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(PhoenixPalette.success)
                }
            }
            .padding(12)
            .background(goal == value ? PhoenixPalette.success.opacity(0.08) : Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(goal == value ? PhoenixPalette.success.opacity(0.5) : Color.white.opacity(0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Goal Detail

    private var goalDetailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FOCUS AREAS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))

            OnboardingFlowLayout(spacing: 10) {
                ForEach(allGoalDetailOptions, id: \.self) { option in
                    goalDetailChip(option)
                }
            }

            TextField("Type your goal", text: $goalDetailInput)
                .font(.system(.body, design: .rounded))
                .foregroundColor(PhoenixPalette.textPrimary)
                .padding(12)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .submitLabel(.done)
                .onSubmit { addCustomGoalTag() }
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
    }

    @ViewBuilder
    private func goalDetailChip(_ label: String) -> some View {
        let isSelected = selectedGoalTags.contains(label)
        Button {
            withAnimation(Constants.springAnimation) {
                if isSelected {
                    selectedGoalTags.remove(label)
                } else {
                    selectedGoalTags.insert(label)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(label)
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundColor(isSelected ? PhoenixPalette.textPrimary : PhoenixPalette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? PhoenixPalette.success.opacity(0.18) : Color.white.opacity(0.03))
            .overlay(
                Capsule()
                    .stroke(isSelected ? PhoenixPalette.success.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }

    // MARK: - Save

    private func save() {
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.goal = goal
        profile.goalDetail = allGoalDetailOptions.filter(selectedGoalTags.contains).joined(separator: ", ")
        try? modelContext.save()
        dismiss()
    }
}
