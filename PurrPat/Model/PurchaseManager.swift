import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let proProductID = "com.limuye.purrpat.pro"

    @Published private(set) var isPro: Bool
    @Published private(set) var displayPrice: String?
    @Published private(set) var isBusy = false
    @Published var lastMessage: String?

    private var product: Product?
    private var updates: Task<Void, Never>?
    private let unlockedByDemo: Bool

    init() {
        unlockedByDemo = ProcessInfo.processInfo.arguments.contains("-PurrPatUnlock")
        let cached = UserDefaults.standard.bool(forKey: "purrpat.isPro")
        isPro = unlockedByDemo || cached
    }

    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                await self.handle(update)
            }
        }
        Task { await loadProduct(); await refresh() }
    }

    func purchase() async {
        if product == nil { await loadProduct() }
        guard let product else {
            lastMessage = String(localized: "The App Store isn’t available right now.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                let transaction = try Self.check(verification)
                await transaction.finish()
                await refresh()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastMessage = String(localized: "Something went wrong.")
        }
    }

    func restore() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refresh()
            lastMessage = String(localized: "Purchases restored")
        } catch {
            lastMessage = String(localized: "The App Store isn’t available right now.")
        }
    }

    private func loadProduct() async {
        do {
            let found = try await Product.products(for: [Self.proProductID])
            product = found.first
            displayPrice = found.first?.displayPrice
        } catch {
            product = nil
        }
        #if DEBUG
        if displayPrice == nil, ProcessInfo.processInfo.arguments.contains("paywall") {
            displayPrice = "US$2.99"
        }
        #endif
    }

    private func refresh() async {
        if unlockedByDemo { return }
        var pro = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? Self.check(result), transaction.productID == Self.proProductID {
                pro = true
            }
        }
        isPro = pro
        UserDefaults.standard.set(pro, forKey: "purrpat.isPro")
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard let transaction = try? Self.check(update) else { return }
        await transaction.finish()
        await refresh()
    }

    private static func check<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
