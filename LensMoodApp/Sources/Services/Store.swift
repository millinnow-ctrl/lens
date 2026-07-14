import StoreKit

/// StoreKit 2 scaffold for LensMood Premium.
///
/// Monetization is intentionally **OFF** for now (`EVERYTHING_FREE_FOR_NOW`):
/// `isPro` defaults to `true`, so nothing is gated. This type exists so the
/// paywall, product loading, purchase, and restore paths are all in place and
/// StoreKit-correct; when pricing is finalized in App Store Connect, flip the
/// default and let `isPro` reflect real entitlements (see `refreshEntitlements`).
///
/// Product ids are constants here but are meant to be **remote-configurable** so
/// pricing/packaging can be tested without an app release.
@MainActor
final class Store: ObservableObject {
  static let annualID = "app.lensmood.pro.annual"
  static let monthlyID = "app.lensmood.pro.monthly"
  static let productIDs = [annualID, monthlyID]

  /// While EVERYTHING_FREE_FOR_NOW this stays true and gates nothing.
  @Published private(set) var isPro = true
  @Published private(set) var products: [Product] = []
  @Published var purchasing = false
  @Published var loadFailed = false

  /// Annual first — the value anchor the paywall defaults to.
  var annual: Product? { products.first { $0.id == Store.annualID } }
  var monthly: Product? { products.first { $0.id == Store.monthlyID } }

  func loadProducts() async {
    do {
      let loaded = try await Product.products(for: Store.productIDs)
      products = loaded.sorted { $0.price > $1.price }
      loadFailed = false
    } catch {
      // No App Store Connect configuration yet — the paywall shows its layout
      // with placeholder pricing until products exist.
      products = []
      loadFailed = true
    }
  }

  @discardableResult
  func purchase(_ product: Product) async -> Bool {
    purchasing = true
    defer { purchasing = false }
    do {
      let result = try await product.purchase()
      switch result {
      case let .success(verification):
        if case let .verified(transaction) = verification {
          await transaction.finish()
          await refreshEntitlements()
          return true
        }
        return false
      case .userCancelled, .pending:
        return false
      @unknown default:
        return false
      }
    } catch {
      return false
    }
  }

  func restore() async {
    try? await AppStore.sync()
    await refreshEntitlements()
  }

  /// Reads real entitlements. While free-for-now this records ownership without
  /// gating; when monetization turns on, set `isPro = owned` here.
  func refreshEntitlements() async {
    var owned = false
    for await result in Transaction.currentEntitlements {
      if case let .verified(transaction) = result,
         Store.productIDs.contains(transaction.productID) {
        owned = true
      }
    }
    _ = owned  // EVERYTHING_FREE_FOR_NOW — do not gate yet
  }
}
