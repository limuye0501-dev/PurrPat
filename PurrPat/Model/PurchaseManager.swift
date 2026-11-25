import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let proProductID = "com.limuye.purrpat.pro"
    /// Shown when App Store Connect has no product yet, or the store request fails.
    static let fallbackPrice = "US$2.99"

    @Published private(set) var isPro: Bool
    @Published private(set) var displayPrice: String?
    @Published private(set) var isBusy = false
    @Published var lastMessage: String?

    private var product: Product?
    private var updates: Task<Void, Never>?
    private let unlockedByDemo: Bool
    private let paywallShot: Bool

    init() {
        let args = ProcessInfo.processInfo.arguments
        unlockedByDemo = args.contains("-PurrPatUnlock")
        paywallShot = Self.argument("paywall", in: args)
        let cached = UserDefaults.standard.bool(forKey: "purrpat.isPro")
        isPro = !paywallShot && (unlockedByDemo || cached)
        displayPrice = Self.resolvedFallbackPrice()
    }

    func start() {
        guard updates == nil else { return }
        if displayPrice == nil {
            displayPrice = Self.resolvedFallbackPrice()
        }
        updates = Task { [weak self] in
            guard let self else { return }
            do {
                for await update in Transaction.updates {
                    await self.handle(update)
                }
            } catch {
                // No transaction stream when the product is not in App Store Connect yet.
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
        let found = await Self.products(id: Self.proProductID)
        product = found.first
        if let price = found.first?.displayPrice, !price.isEmpty {
            displayPrice = price
        } else {
            displayPrice = Self.resolvedFallbackPrice()
        }
    }

    /// StoreKit's product request has no timeout and never returns when the
    /// configuration file is not attached. The screenshot cannot wait on that.
    private static func products(id: String) async -> [Product] {
        await withTaskGroup(of: [Product]?.self) { group in
            group.addTask { try? await Product.products(for: [id]) }
            group.addTask {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
    }

    /// Reads the price out of the StoreKit configuration shipped with the app.
    private static func priceFromStoreKitFile() -> String? {
        guard let url = Bundle.main.url(forResource: "Products", withExtension: "storekit"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]],
              let price = products.first?["displayPrice"] as? String,
              !price.isEmpty else { return nil }
        if price.contains("$") || price.contains("¥") || price.contains("￥") { return price }
        let storefront = (json["settings"] as? [String: Any])?["_storefront"] as? String
        return storefront == "USA" ? "US$\(price)" : price
    }

    private static func resolvedFallbackPrice() -> String {
        priceFromStoreKitFile() ?? fallbackPrice
    }

    private static func argument(_ name: String, in args: [String]) -> Bool {
        guard let index = args.firstIndex(of: "-PurrPatShot"), index + 1 < args.count else { return false }
        return args[index + 1] == name
    }

    private func refresh() async {
        if unlockedByDemo || paywallShot { return }
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
