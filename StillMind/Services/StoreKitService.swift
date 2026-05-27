import Foundation
import Observation
import StoreKit

/// Manages the Pro in-app purchase using StoreKit 2.
/// Free tier: 3 journal entries, no projects, no backup/restore.
/// Pro tier: Unlimited entries, projects, backup & restore.
@Observable
@MainActor
final class StoreKitService {
    nonisolated static let proProductId = "com.stillmind.pro"

    private(set) var isPro = false
    private(set) var proProduct: Product?
    private(set) var purchaseError: String?

    /// Maximum journal entries allowed on the free tier.
    nonisolated static let freeEntryLimit = 3

    @ObservationIgnored private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProduct()
            await refreshPurchaseStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Product Loading

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductId])
            proProduct = products.first
        } catch {
            purchaseError = "Failed to load products: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase

    func purchasePro() async {
        guard let product = proProduct else {
            purchaseError = "Product not available. Please try again later."
            return
        }

        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                isPro = true
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshPurchaseStatus()
    }

    // MARK: - Status

    func refreshPurchaseStatus() async {
        #if DEBUG
        isPro = true
        #else
        if Self.isTestFlight {
            isPro = true
            return
        }

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.proProductId {
                isPro = true
                return
            }
        }
        isPro = false
        #endif
    }

    // MARK: - Environment Detection

    /// Returns `true` when the app was installed via TestFlight (sandbox receipt present).
    nonisolated static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    // MARK: - Helpers

    /// Whether the user can create a new journal entry given the current count.
    func canCreateEntry(currentCount: Int) -> Bool {
        isPro || currentCount < Self.freeEntryLimit
    }

    /// Whether the user can create projects.
    var canCreateProjects: Bool { isPro }

    /// Whether the user can use backup/restore.
    var canBackup: Bool { isPro }

    /// Whether the user can export journal as PDF.
    var canExportPDF: Bool { isPro }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    if transaction.productID == StoreKitService.proProductId {
                        await MainActor.run { [weak self] in
                            self?.isPro = true
                        }
                    }
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
