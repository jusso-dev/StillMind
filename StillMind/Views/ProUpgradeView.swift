import SwiftUI

/// Paywall sheet shown when free-tier users hit a restriction.
struct ProUpgradeView: View {
    let storeService: StoreKitService
    @Environment(\.dismiss) private var dismiss

    /// Describes which feature triggered the paywall.
    let feature: Feature

    enum Feature {
        case entries
        case projects
        case backup
        case pdfExport

        var title: String {
            switch self {
            case .entries: return "Entry Limit Reached"
            case .projects: return "Projects Are a Pro Feature"
            case .backup: return "Backup & Restore Are Pro Features"
            case .pdfExport: return "PDF Export Is a Pro Feature"
            }
        }

        var description: String {
            switch self {
            case .entries:
                return "Free accounts are limited to \(StoreKitService.freeEntryLimit) journal entries. Upgrade to Pro for unlimited entries."
            case .projects:
                return "Organize your entries into projects with StillMind Pro."
            case .backup:
                return "Keep your journal safe with encrypted backups. Upgrade to Pro to enable backup and restore."
            case .pdfExport:
                return "Export your journal entries as beautifully formatted PDFs with mood insights. Upgrade to Pro to unlock PDF export."
            }
        }

        var icon: String {
            switch self {
            case .entries: return "book.closed.fill"
            case .projects: return "folder.fill"
            case .backup: return "arrow.up.doc.fill"
            case .pdfExport: return "doc.richtext.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: feature.icon)
                    .font(.system(size: 56))
                    .foregroundStyle(Color.smAccent)

                Text(feature.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(feature.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Feature list
                VStack(alignment: .leading, spacing: 12) {
                    proFeatureRow("Unlimited journal entries", icon: "infinity")
                    proFeatureRow("Create & manage projects", icon: "folder.fill")
                    proFeatureRow("PDF export with mood insights", icon: "doc.richtext.fill")
                    proFeatureRow("Encrypted backup & restore", icon: "lock.shield.fill")
                    proFeatureRow("Automatic nightly backups", icon: "moon.fill")
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)

                Spacer()

                // Purchase button
                if let product = storeService.proProduct {
                    Button {
                        Task { await storeService.purchasePro() }
                    } label: {
                        Text("Upgrade to Pro — \(product.displayPrice)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.smAccent)
                    .controlSize(.large)
                    .padding(.horizontal, 24)
                } else {
                    ProgressView("Loading...")
                }

                if let error = storeService.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Button("Restore Purchase") {
                    Task { await storeService.restorePurchases() }
                }
                .font(.footnote)
                .padding(.bottom, 8)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: storeService.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
    }

    private func proFeatureRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.smAccent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}
