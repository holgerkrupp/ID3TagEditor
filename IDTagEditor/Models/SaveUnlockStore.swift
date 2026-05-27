import Foundation
import Observation
import StoreKit

@Observable
@MainActor
final class SaveUnlockStore {
    static let productID = "de.holgerkrupp.IDTagEditor.saveUnlock"
    private static let unlockedDefaultsKey = "SaveUnlockStore.isUnlocked"

    private(set) var product: Product?
    private(set) var isUnlocked = UserDefaults.standard.bool(forKey: SaveUnlockStore.unlockedDefaultsKey) {
        didSet {
            UserDefaults.standard.set(isUnlocked, forKey: Self.unlockedDefaultsKey)
        }
    }
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    var errorMessage: String?

    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func configure() async {
        await refreshPurchasedState()
        await loadProduct()
    }

    func loadProduct() async {
        guard product == nil, !isLoading else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil {
                errorMessage = "The save unlock purchase is not available."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func purchase() async -> Bool {
        if product == nil {
            await loadProduct()
        }

        guard let product else {
            return false
        }

        isPurchasing = true
        defer {
            isPurchasing = false
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verificationResult):
                let transaction = try verifiedTransaction(from: verificationResult)
                if transaction.productID == Self.productID {
                    isUnlocked = true
                }
                await transaction.finish()
                return isUnlocked
            case .pending:
                errorMessage = "The purchase is pending approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshPurchasedState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshPurchasedState() async {
        var hasSaveUnlock = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verifiedTransaction(from: result) else {
                continue
            }

            if transaction.productID == Self.productID {
                hasSaveUnlock = true
                break
            }
        }

        isUnlocked = hasSaveUnlock
    }

    private func handle(transactionResult result: VerificationResult<Transaction>) async {
        guard let transaction = try? verifiedTransaction(from: result) else {
            return
        }

        if transaction.productID == Self.productID {
            isUnlocked = true
        }

        await transaction.finish()
    }

    private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw error
        }
    }
}
