import SwiftUI

/// First-launch onboarding that introduces key features of StillMind.
struct OnboardingView: View {
    @Binding var isComplete: Bool

    @State private var currentPage = 0
    @State private var appeared = false

    private let pages = OnboardingPage.all
    private let pageCount = OnboardingPage.all.count

    var body: some View {
        ZStack {
            // Warm background matching the app's aesthetic
            Color(red: 0.988, green: 0.973, blue: 0.961)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < pageCount - 1 {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.smAccent)
                        .padding(.trailing, Spacing.lg)
                        .padding(.top, Spacing.sm)
                    }
                }
                .frame(height: 44)

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page, isActive: currentPage == index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: currentPage)

                // Page indicator + button
                VStack(spacing: Spacing.xl) {
                    // Custom page dots
                    HStack(spacing: Spacing.sm) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            Capsule()
                                .fill(index == currentPage ? Color.smAccent : Color.smAccent.opacity(0.25))
                                .frame(width: index == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentPage)
                        }
                    }

                    // Action button
                    Button {
                        if currentPage < pageCount - 1 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                currentPage += 1
                            }
                            Haptics.light()
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        Text(currentPage < pageCount - 1 ? "Continue" : "Get Started")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.smAccent)
                            .clipShape(.rect(cornerRadius: 16))
                    }
                    .padding(.horizontal, Spacing.xl)
                }
                .padding(.bottom, Spacing.xxl)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    private func completeOnboarding() {
        Haptics.success()
        withAnimation(.easeOut(duration: 0.35)) {
            isComplete = true
        }
    }
}

// MARK: - Page Model

private struct OnboardingPage {
    let icon: String
    let iconColors: [Color]
    let title: String
    let subtitle: String
    let accentColor: Color

    static let all: [OnboardingPage] = [
        OnboardingPage(
            icon: "leaf.fill",
            iconColors: [Color.smAccent, Color(red: 0.30, green: 0.80, blue: 0.62)],
            title: "Welcome to\nStillMind",
            subtitle: "A quiet space for your thoughts.\nCapture what matters, understand how you feel.",
            accentColor: Color.smAccent
        ),
        OnboardingPage(
            icon: "waveform",
            iconColors: [Color(red: 0.35, green: 0.68, blue: 0.85), Color.smAccent],
            title: "Speak Freely",
            subtitle: "Record a voice note and your words are transcribed instantly. No typing needed — just talk.",
            accentColor: Color(red: 0.35, green: 0.68, blue: 0.85)
        ),
        OnboardingPage(
            icon: "sparkles",
            iconColors: [Color(red: 0.72, green: 0.74, blue: 0.42), Color(red: 0.90, green: 0.65, blue: 0.40)],
            title: "Gentle Insights",
            subtitle: "Your entries are summarised, tagged, and mood-mapped — all on your device. Over time, patterns emerge.",
            accentColor: Color(red: 0.90, green: 0.65, blue: 0.40)
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            iconColors: [Color.smAccent, Color(red: 0.88, green: 0.48, blue: 0.55)],
            title: "Completely Private",
            subtitle: "Everything stays on your iPhone.\nAES-256 encryption. No cloud. No accounts. Just you.",
            accentColor: Color(red: 0.88, green: 0.48, blue: 0.55)
        ),
        OnboardingPage(
            icon: "heart.fill",
            iconColors: [Color(red: 0.30, green: 0.80, blue: 0.62), Color(red: 0.35, green: 0.68, blue: 0.85)],
            title: "Your Journey\nStarts Here",
            subtitle: "Take a moment each day to check in with yourself. Small reflections lead to big understanding.",
            accentColor: Color.smAccent
        ),
    ]
}

// MARK: - Page View

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool

    @State private var iconAnimating = false

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Animated icon with gradient circle background
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [page.accentColor.opacity(0.15), .clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .scaleEffect(iconAnimating ? 1.05 : 0.95)
                    .animation(
                        .easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                        value: iconAnimating
                    )

                // Inner circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: page.iconColors.map { $0.opacity(0.12) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)

                // Icon
                Image(systemName: page.icon)
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: page.iconColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(isActive ? 1.0 : 0.8)
                    .opacity(isActive ? 1.0 : 0.5)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isActive)
            }

            VStack(spacing: Spacing.md) {
                Text(page.title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color(red: 0.165, green: 0.165, blue: 0.165))
                    .multilineTextAlignment(.center)
                    .offset(y: isActive ? 0 : 20)
                    .opacity(isActive ? 1.0 : 0.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: isActive)

                Text(page.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.xl)
                    .offset(y: isActive ? 0 : 20)
                    .opacity(isActive ? 1.0 : 0.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: isActive)
            }

            Spacer()
            Spacer()
        }
        .onAppear {
            iconAnimating = true
        }
    }
}
