import SwiftUI
import Charts

/// Reflective insights — calm visualizations that support reflection, not evaluation.
struct InsightsView: View {
    let entryRepository: EntryRepository
    let projectRepository: ProjectRepository

    @State private var entries: [VoiceEntry] = []
    @State private var projects: [Project] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                if entries.isEmpty {
                    emptyState
                        .padding(.top, Spacing.xxl)
                } else {
                    VStack(spacing: Spacing.xl) {
                        // Gentle insight text
                        insightMessage
                            .padding(.horizontal, Spacing.md)

                        // Mood river
                        if !moodDataPoints.isEmpty {
                            MoodRiverChart(dataPoints: moodDataPoints)
                                .padding(.horizontal, Spacing.md)
                        }

                        // Presence calendar
                        PresenceCalendar(entries: entries)
                            .padding(.horizontal, Spacing.md)

                        // Recent moods as soft dots
                        if !recentMoods.isEmpty {
                            recentMoodFlow
                                .padding(.horizontal, Spacing.md)
                        }

                        // Weekly cards
                        if !weeklyGroups.isEmpty {
                            weeksSection
                        }

                        Spacer(minLength: Spacing.xxl)
                    }
                    .padding(.top, Spacing.md)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reflect")
            .task {
                entries = (try? await entryRepository.allEntries()) ?? []
                projects = (try? await projectRepository.allProjects()) ?? []
            }
            .refreshable {
                entries = (try? await entryRepository.allEntries()) ?? []
                projects = (try? await projectRepository.allProjects()) ?? []
            }
        }
    }

    // MARK: - Insight Message

    private var insightMessage: some View {
        let thisWeekCount = entries.filter {
            Calendar.current.isDate($0.createdAt, equalTo: Date(), toGranularity: .weekOfYear)
        }.count

        let text: String = {
            if thisWeekCount == 0 {
                return "Start your week with a reflection."
            } else if thisWeekCount == 1 {
                return "You've reflected once this week. Every entry matters."
            } else if thisWeekCount < 4 {
                return "You've journaled \(thisWeekCount) times this week. A gentle rhythm."
            } else {
                return "You've been showing up consistently. That takes intention."
            }
        }()

        return Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Recent Moods Flow

    private var recentMoods: [(date: Date, mood: String, value: Double)] {
        entries.prefix(10).compactMap { entry in
            guard let mood = entry.mood else { return nil }
            return (entry.createdAt, mood, MoodMapping.value(for: mood))
        }
    }

    private var recentMoodFlow: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recent moods")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(recentMoods, id: \.date) { item in
                        VStack(spacing: Spacing.xs) {
                            Circle()
                                .fill(Color.forMoodValue(item.value))
                                .frame(width: 28, height: 28)

                            Text(item.mood)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Weeks Section

    private var weeksSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Your weeks")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.md)

            ForEach(weeklyGroups.prefix(6), id: \.weekStart) { group in
                WeekCard(group: group)
                    .padding(.horizontal, Spacing.md)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "leaf")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Color.smAccent.opacity(0.5))

            Text("Nothing here yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Your reflections will appear here as gentle patterns over time.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
        }
    }

    // MARK: - Data

    private var moodDataPoints: [MoodDataPoint] {
        entries.compactMap { entry -> MoodDataPoint? in
            guard let mood = entry.mood else { return nil }
            return MoodDataPoint(
                date: entry.createdAt,
                mood: mood,
                numericValue: MoodMapping.value(for: mood)
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var weeklyGroups: [WeeklyGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { entry in
            calendar.dateInterval(of: .weekOfYear, for: entry.createdAt)?.start ?? entry.createdAt
        }

        return grouped.map { (weekStart, entries) in
            let moods = entries.compactMap { $0.mood }
            let totalDuration = entries.reduce(0) { $0 + $1.durationSeconds }
            let allTags = entries.flatMap { $0.tags }
            let tagCounts = Dictionary(allTags.map { ($0, 1) }, uniquingKeysWith: +)
            let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(5).map(\.key)

            return WeeklyGroup(
                weekStart: weekStart,
                entries: entries.sorted { $0.createdAt < $1.createdAt },
                entryCount: entries.count,
                totalDuration: totalDuration,
                moods: moods,
                dominantMood: MoodMapping.mostFrequent(moods),
                topTags: Array(topTags)
            )
        }
        .sorted { $0.weekStart > $1.weekStart }
    }
}

// MARK: - Mood River Chart

/// A soft, ambient area chart — shows emotional flow without judgment.
struct MoodRiverChart: View {
    let dataPoints: [MoodDataPoint]
    @State private var rawSelectedDate: Date?
    @State private var stickyPoint: MoodDataPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("How you've been feeling")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Chart(dataPoints) { point in
                // Area fill colored by mood
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Base", 0.5),
                    yEnd: .value("Mood", point.numericValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.forMoodValue(point.numericValue).opacity(0.35),
                            Color.forMoodValue(point.numericValue).opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Flowing line colored by mood
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Mood", point.numericValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.forMoodValue(point.numericValue).opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                // Vibrant dots at each point
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Mood", point.numericValue)
                )
                .foregroundStyle(Color.forMoodValue(point.numericValue))
                .symbolSize(36)
            }
            .chartYScale(domain: 0.5...5.5)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartXSelection(value: $rawSelectedDate)
            .frame(height: 140)
            .accessibilityLabel("Mood flow showing \(dataPoints.count) reflections")
            .onChange(of: rawSelectedDate) { _, newDate in
                // Snap to nearest data point and keep it visible (sticky)
                guard let date = newDate else { return }
                if let nearest = dataPoints.min(by: {
                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                }) {
                    Haptics.selection()
                    stickyPoint = nearest
                }
            }

            // Detail label — always reserves space, uses opacity to show/hide
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color.forMoodValue(stickyPoint?.numericValue ?? 3))
                    .frame(width: 8, height: 8)
                Text(stickyPoint?.mood ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(stickyPoint?.date ?? .now, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .opacity(stickyPoint != nil ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: stickyPoint?.id)
        }
        .cardStyle()
    }
}

// MARK: - Presence Calendar

/// A 4-week dot grid — shows when you journaled, colored softly by mood. No numbers.
struct PresenceCalendar: View {
    let entries: [VoiceEntry]

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    private var calendarDays: [CalendarDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Find the Monday 4 weeks ago
        let todayWeekday = calendar.component(.weekday, from: today)
        // Convert to Monday=0 system (Apple: Sunday=1)
        let daysFromMonday = (todayWeekday + 5) % 7
        let thisMonday = calendar.date(byAdding: .day, value: -daysFromMonday, to: today)!
        let startMonday = calendar.date(byAdding: .weekOfYear, value: -3, to: thisMonday)!

        return (0..<28).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: startMonday)!
            let dayEntries = entries.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
            let mood = dayEntries.first?.mood
            let isToday = calendar.isDateInToday(date)
            let isFuture = date > today
            return CalendarDay(date: date, entryCount: dayEntries.count, mood: mood, isToday: isToday, isFuture: isFuture)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Your presence")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            // Day-of-week labels
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(dayLabels.indices, id: \.self) { i in
                    Text(dayLabels[i])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .frame(maxWidth: .infinity)
                }

                // Calendar dots
                ForEach(calendarDays, id: \.date) { day in
                    if day.isFuture {
                        Circle()
                            .fill(Color.clear)
                            .frame(height: 24)
                    } else {
                        calendarDot(for: day)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func calendarDot(for day: CalendarDay) -> some View {
        let hasEntry = day.entryCount > 0
        let moodValue = day.mood.map { MoodMapping.value(for: $0) } ?? 3.0
        let fillColor: Color = hasEntry
            ? Color.forMoodValue(moodValue).opacity(0.85)
            : Color(.quaternarySystemFill)

        return Circle()
            .fill(fillColor)
            .frame(height: 24)
            .overlay {
                if day.isToday {
                    Circle()
                        .strokeBorder(Color.smAccent.opacity(0.6), lineWidth: 1.5)
                }
            }
    }
}

private struct CalendarDay {
    let date: Date
    let entryCount: Int
    let mood: String?
    let isToday: Bool
    let isFuture: Bool
}

// MARK: - Week Card

/// A calm summary of a week — moods as colored dots, no metrics.
struct WeekCard: View {
    let group: WeeklyGroup

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Week label
            HStack {
                Text(weekLabel)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(presenceText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Mood dots — a gentle row of colored circles
            if !group.moods.isEmpty {
                HStack(spacing: 6) {
                    ForEach(group.entries.prefix(7)) { entry in
                        Circle()
                            .fill(dotColor(for: entry))
                            .frame(width: 12, height: 12)
                    }
                }
            }

            // Top tags
            if !group.topTags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(group.topTags.prefix(3), id: \.self) { tag in
                        TagChip(text: tag)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func dotColor(for entry: VoiceEntry) -> Color {
        guard let mood = entry.mood else {
            return Color(.quaternarySystemFill)
        }
        return Color.forMoodValue(MoodMapping.value(for: mood))
    }

    private var presenceText: String {
        let days = Set(group.entries.map {
            Calendar.current.startOfDay(for: $0.createdAt)
        }).count
        return days == 1 ? "1 day" : "\(days) days"
    }

    private var weekLabel: String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDate(group.weekStart, equalTo: now, toGranularity: .weekOfYear) {
            return "This week"
        }
        let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        if calendar.isDate(group.weekStart, equalTo: lastWeek, toGranularity: .weekOfYear) {
            return "Last week"
        }
        let end = calendar.date(byAdding: .day, value: 6, to: group.weekStart) ?? group.weekStart
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: group.weekStart)) – \(f.string(from: end))"
    }
}

// MARK: - Compact Presence Strip (for HomeView)

/// A minimal row of dots showing the last 14 days of journaling presence.
struct PresenceStrip: View {
    let entries: [VoiceEntry]

    private var last14Days: [(date: Date, hasEntry: Bool, moodValue: Double?)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<14).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let dayEntries = entries.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
            let mood = dayEntries.first?.mood.map { MoodMapping.value(for: $0) }
            return (date, !dayEntries.isEmpty, mood)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(last14Days, id: \.date) { day in
                Circle()
                    .fill(day.hasEntry
                        ? Color.forMoodValue(day.moodValue ?? 3).opacity(0.85)
                        : Color(.quaternarySystemFill)
                    )
                    .frame(width: 14, height: 14)
            }
        }
    }
}

// MARK: - Data Models

struct MoodDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let mood: String
    let numericValue: Double
}

struct WeeklyGroup {
    let weekStart: Date
    let entries: [VoiceEntry]
    let entryCount: Int
    let totalDuration: Double
    let moods: [String]
    let dominantMood: String?
    let topTags: [String]
}

// MARK: - Helpers

enum MoodMapping {
    /// Common mood words mapped to 1-5 scale.
    static let moodMap: [String: Double] = [
        // 5 - Great
        "great": 5, "amazing": 5, "fantastic": 5, "wonderful": 5, "elated": 5, "ecstatic": 5, "joyful": 5, "thrilled": 5, "euphoric": 5, "excellent": 5,
        // 4 - Good
        "good": 4, "happy": 4, "positive": 4, "content": 4, "pleased": 4, "cheerful": 4, "optimistic": 4, "hopeful": 4, "grateful": 4, "calm": 4, "peaceful": 4, "relaxed": 4, "motivated": 4, "energetic": 4, "excited": 4, "confident": 4,
        // 3 - Okay
        "okay": 3, "ok": 3, "neutral": 3, "fine": 3, "alright": 3, "mixed": 3, "so-so": 3, "meh": 3, "indifferent": 3, "reflective": 3, "thoughtful": 3, "contemplative": 3,
        // 2 - Low
        "low": 2, "sad": 2, "down": 2, "tired": 2, "exhausted": 2, "stressed": 2, "anxious": 2, "worried": 2, "frustrated": 2, "overwhelmed": 2, "melancholy": 2, "disappointed": 2, "lonely": 2, "uncertain": 2, "uneasy": 2,
        // 1 - Bad
        "bad": 1, "terrible": 1, "awful": 1, "depressed": 1, "angry": 1, "furious": 1, "hopeless": 1, "devastated": 1, "miserable": 1, "despairing": 1
    ]

    /// Maps a mood string to a numeric value for charting.
    static func value(for mood: String) -> Double {
        let lowered = mood.lowercased().trimmingCharacters(in: .whitespaces)

        if let value = moodMap[lowered] {
            return value
        }

        for (key, value) in moodMap where lowered.contains(key) {
            return value
        }

        return 3 // Default to neutral
    }

    /// Returns the most frequent element in an array.
    static func mostFrequent(_ items: [String]) -> String? {
        guard !items.isEmpty else { return nil }
        let counts = Dictionary(items.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
