import SwiftUI

// MARK: - Color Palette

extension Color {
    /// Muted sage — warm, natural, calming. The app's signature color.
    static let smAccent = Color(red: 0.38, green: 0.61, blue: 0.55)

    /// Light accent for tag/chip backgrounds and subtle highlights.
    static let smAccentSoft = Color(red: 0.38, green: 0.61, blue: 0.55).opacity(0.12)

    /// Foreground color for tags and chips.
    static let smTagText = Color(red: 0.26, green: 0.46, blue: 0.41)

    /// Maps a numeric mood value (1–5) to a vibrant but warm tone.
    /// Every mood feels alive — even low moods are gentle and inviting, never grim.
    static func forMoodValue(_ value: Double) -> Color {
        switch value {
        case 4.5...5: return Color(red: 0.30, green: 0.80, blue: 0.62) // vivid mint
        case 3.5..<4.5: return Color(red: 0.35, green: 0.68, blue: 0.85) // bright sky
        case 2.5..<3.5: return Color(red: 0.72, green: 0.74, blue: 0.42) // warm chartreuse
        case 1.5..<2.5: return Color(red: 0.90, green: 0.65, blue: 0.40) // amber glow
        default: return Color(red: 0.88, green: 0.48, blue: 0.55)        // rose
        }
    }
}

// MARK: - Spacing (8pt Grid)

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Haptic Feedback

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Reusable Components

/// A tag chip with the app's signature style.
struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.smTagText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.smAccentSoft)
            .clipShape(Capsule())
    }
}

/// Mood indicator pill — shows a mood string with a colored dot.
struct MoodPill: View {
    let mood: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.forMoodValue(MoodMapping.value(for: mood)))
                .frame(width: 6, height: 6)
            Text(mood)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Card-style modifier for consistent surfaces.
extension View {
    func cardStyle(cornerRadius: CGFloat = 20) -> some View {
        self
            .padding(Spacing.md)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: cornerRadius))
    }

    /// Caps content at a comfortable reading width and centers it, so wide
    /// windows (e.g. an unfolded iPhone Duo in landscape) don't stretch it edge to edge.
    func readableWidth(_ maxWidth: CGFloat = 640) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Date Formatting

extension Date {
    /// "Today", "Yesterday", or "Mar 15"
    var relativeShort: String {
        if Calendar.current.isDateInToday(self) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(self) {
            return "Yesterday"
        } else {
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: self)
        }
    }
}

// MARK: - Duration Formatting

func formatDuration(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
}
