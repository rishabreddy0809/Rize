import StoreKit
import SwiftUI

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    static let monthlyID = "com.rize.pro.monthly"
    static let yearlyID = "com.rize.pro.yearly"

    @Published var isPro: Bool = false
    @Published var products: [Product] = []
    @Published var purchaseError: String? = nil
    @Published var isLoading: Bool = false

    private var transactionListener: Task<Void, Error>? = nil

    private init() {
        transactionListener = listenForTransactions()
        // Restore cached status
        isPro = UserDefaults.standard.bool(forKey: "rize_isPro_cache")
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let ids = [SubscriptionManager.monthlyID, SubscriptionManager.yearlyID]
            products = try await Product.products(for: ids)
                .sorted { $0.price < $1.price }
        } catch {
            products = []
        }
    }

    // MARK: - Purchase

    func purchase(productID: String) async -> Bool {
        #if DEBUG
        isPro = true
        UserDefaults.standard.set(true, forKey: "rize_isPro_cache")
        return true
        #else
        guard let product = products.first(where: { $0.id == productID }) else { return false }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                isPro = true
                UserDefaults.standard.set(true, forKey: "rize_isPro_cache")
                return true
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
        #endif
    }

    // MARK: - Restore

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await checkSubscriptionStatus()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Check Status

    func checkSubscriptionStatus() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                let ids = [SubscriptionManager.monthlyID, SubscriptionManager.yearlyID]
                if ids.contains(transaction.productID) && transaction.revocationDate == nil {
                    found = true
                    break
                }
            }
        }
        isPro = found
        UserDefaults.standard.set(found, forKey: "rize_isPro_cache")
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await MainActor.run {
                        let ids = [SubscriptionManager.monthlyID, SubscriptionManager.yearlyID]
                        if ids.contains(transaction.productID) {
                            self.isPro = transaction.revocationDate == nil
                        }
                    }
                    await transaction.finish()
                } catch {
                    // Transaction verification failed
                }
            }
        }
    }

    // MARK: - Verification

    // nonisolated so it can be called from Task.detached without crossing actor boundaries
    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let value):
            return value
        }
    }
}

enum StoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "Transaction verification failed."
    }
}
