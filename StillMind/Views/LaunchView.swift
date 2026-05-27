import SwiftUI

/// Pixel-perfect replica of the OS launch screen plus the "StillMind" text.
/// Shown as a full-screen overlay that fades out once the app is ready,
/// giving a seamless launch → app transition.
struct LaunchView: View {
    @Binding var isFinished: Bool

    @State private var opacity: Double = 1

    private let backgroundColor = Color(red: 0.988, green: 0.973, blue: 0.961) // #FCF8F5
    private let textColor = Color(red: 0.165, green: 0.165, blue: 0.165) // #2A2A2A

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)

                Text("StillMind")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(textColor)
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .task {
            // Brief hold so the launch image and this view overlap seamlessly,
            // then fade out.
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeOut(duration: 0.4)) {
                opacity = 0
            }
            try? await Task.sleep(for: .seconds(0.4))
            isFinished = true
        }
    }
}
