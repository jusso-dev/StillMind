import LocalAuthentication
import SwiftUI

/// Atmospheric biometric lock screen for private journal access.
struct LockScreenView: View {
    @Binding var isUnlocked: Bool
    @State private var authError: String?
    @State private var isAuthenticating = false
    @State private var breatheAnimation = false
    @State private var promptOnActive = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // Soft gradient background
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.smAccent.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                Spacer()

                // Animated lock icon
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56, weight: .ultraLight))
                    .foregroundStyle(Color.smAccent)
                    .scaleEffect(breatheAnimation ? 1.05 : 1.0)
                    .opacity(breatheAnimation ? 1.0 : 0.7)
                    .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: breatheAnimation)

                VStack(spacing: Spacing.sm) {
                    Text("StillMind")
                        .font(.largeTitle.weight(.semibold))

                    Text("Your private journal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Unlock button
                Button {
                    Task { await authenticate() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 400)
                .buttonStyle(.borderedProminent)
                .tint(Color.smAccent)
                .controlSize(.large)
                .disabled(isAuthenticating)
                .padding(.horizontal, Spacing.xxl)

                if let error = authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, Spacing.lg)
                }

                Spacer()
                    .frame(height: Spacing.xxl)
            }
        }
        .onAppear { breatheAnimation = true }
        // Auto-prompt only on launch or a real return from background. Plain
        // inactive → active hops (the Face ID sheet itself, Control Center, an
        // iPhone Duo moving between displays) must not re-prompt.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                promptOnActive = true
            } else if newPhase == .active && promptOnActive && !isUnlocked {
                promptOnActive = false
                Task { await authenticate() }
            }
        }
        .task {
            if scenePhase == .active {
                await authenticate()
            } else {
                promptOnActive = true
            }
        }
    }

    private func authenticate() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil

        do {
            let success = try await BiometricService.shared.authenticate()
            if success {
                Haptics.success()
                withAnimation(.easeOut(duration: 0.3)) { isUnlocked = true }
            }
        } catch let error as LAError where error.code == .userCancel || error.code == .systemCancel || error.code == .appCancel {
            // User dismissed — no error
        } catch {
            authError = error.localizedDescription
        }
        isAuthenticating = false
    }
}
