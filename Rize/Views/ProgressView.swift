import SwiftUI
import SwiftData
import Charts

struct RizeProgressScreen: View {
    @Query private var profiles: [UserProfile]
    @Query private var entries: [DailyEntry]
    @EnvironmentObject private var xpManager: XPManager

    @State private var weeklyInsight: String = ""
    @State private var loadingInsight = false

    private var profile: UserProfile? { profiles.first }

    private var last7Entries: [DailyEntry] {
        let sorted = entries.sorted { $0.date > $1.date }
        return Array(sorted.prefix(7).reversed())
    }

    private var averageEnergy: Double {
        let withEnergy = last7Entries.compactMap { $0.energyScore }
        guard !withEnergy.isEmpty else { return 0 }
        return Double(withEnergy.reduce(0, +)) / Double(withEnergy.count)
    }

    var body: some View {
        ZStack {
            PhoenixBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    header
                    statsRow
                    energyChartCard
                    weeklyInsightCard
                    personalBestsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("WATCH YOURSELF")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
            Text("GROW")
                .font(.phoenixHero(32))
                .foregroundColor(PhoenixPalette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            miniStat("TASKS", value: "\(entries.reduce(0) { $0 + $1.tasksCompleted })")
            miniStat("LEVEL", value: "LV \(PhoenixDesign.playerLevel(for: xpManager.totalXP))")
            miniStat("STREAK", value: "\(profile?.currentStreak ?? 0)d")
            miniStat("BEST DAY", value: "\(profile?.bestXPDay ?? 0) XP")
        }
    }

    @ViewBuilder
    private func miniStat(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.6))
            Text(value)
                .font(.phoenixHeadline())
                .fontWeight(.bold)
                .foregroundColor(PhoenixPalette.textPrimary)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .phoenixGlass(cornerRadius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Energy Chart

    private var energyChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ENERGY LAST 7 DAYS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                .accessibilityAddTraits(.isHeader)

            if last7Entries.isEmpty {
                Text("No data yet. Start logging your energy!")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.5))
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(Array(last7Entries.enumerated()), id: \.offset) { index, entry in
                        if let energy = entry.energyScore {
                            BarMark(
                                x: .value("Day", dayLabel(entry.date)),
                                y: .value("Energy", energy)
                            )
                            .foregroundStyle(Constants.energyColor(for: energy))
                            .cornerRadius(6)
                        }
                    }

                    // Average line
                    RuleMark(y: .value("Average", averageEnergy))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.25))
                        .annotation(position: .trailing) {
                            Text("avg")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                }
                .chartYScale(domain: 0...10)
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisValueLabel {
                            if let str = value.as(String.self) {
                                Text(str)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.05))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 5, 10]) { value in
                        AxisValueLabel {
                            if let int = value.as(Int.self) {
                                Text("\(int)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.05))
                    }
                }
                .frame(height: 160)
                // Swift Charts doesn't expose individual bars to VoiceOver in a
                // useful way by default — treat the whole chart as one element
                // with a spoken-out summary instead of silent/per-mark noise.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Energy over the last 7 days")
                .accessibilityValue(energyChartSummary)
            }
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
    }

    /// "Monday 6, Tuesday 8, ..." — the same data the bar chart plots, read
    /// as a sentence for the `accessibilityValue` above.
    private var energyChartSummary: String {
        last7Entries.compactMap { entry in
            guard let energy = entry.energyScore else { return nil }
            return "\(dayLabel(entry.date)) \(energy)"
        }.joined(separator: ", ")
    }

    // MARK: - Weekly Insight

    private var weeklyInsightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WEEKLY INSIGHT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    fetchInsight()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                }
                .accessibilityLabel("Refresh weekly insight")
            }

            if loadingInsight {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading weekly insight")
            } else if weeklyInsight.isEmpty {
                Text("Tap refresh to get your weekly AI insight.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(PhoenixPalette.textSecondary.opacity(0.5))
            } else {
                Text(weeklyInsight)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(PhoenixPalette.textPrimary.opacity(0.85))
                    .lineSpacing(4)
            }
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
        .onAppear { if weeklyInsight.isEmpty { fetchInsight() } }
    }

    // MARK: - Personal Bests

    private var personalBestsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PERSONAL BESTS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PhoenixPalette.textSecondary.opacity(0.7))
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 10) {
                bestRow("Best XP day", value: "\(profile?.bestXPDay ?? 0) XP", icon: "sparkles")
                bestRow("Longest streak", value: "\(profile?.bestStreak ?? 0) days", icon: "flame.fill")
                bestRow("Best week tasks", value: "\(profile?.bestTasksCompletedInWeek ?? 0)", icon: "checkmark.seal.fill")
            }
        }
        .padding(16)
        .phoenixGlass(cornerRadius: 16)
    }

    @ViewBuilder
    private func bestRow(_ label: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Constants.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(PhoenixPalette.textPrimary.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(PhoenixPalette.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private func fetchInsight() {
        guard !last7Entries.isEmpty else { return }
        loadingInsight = true
        let energyHistory = last7Entries.map { $0.energyScore ?? 0 }
        let completionHistory = last7Entries.map { $0.completionRate }
        Task {
            let insight = await CoachingNarrator.shared.weeklyInsight(
                energyHistory: energyHistory,
                completionHistory: completionHistory
            )
            await MainActor.run {
                weeklyInsight = insight
                loadingInsight = false
            }
        }
    }
}
