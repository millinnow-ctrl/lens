// Store — the profit engine's plumbing, with every gate hard-wired OPEN.
//
// Mirrors EVERYTHING_FREE_FOR_NOW in the frozen reference
// (lensmood-native/src/store/store.tsx): while the product is being shaped,
// nothing locks, nothing meters, nothing says "Pro". What is actually paid
// gets decided at the end; the owner flips `everythingFreeForNow` then.
//
// Design source: docs/PROFIT_ENGINE.md. One membership ("Plus"), two ways to
// buy it (yearly auto-renewable + lifetime non-consumable), and a catalog
// that splits the 18 cameras into a free-forever set and the Plus set.
// Import/export and full-resolution output are never gated at any tier.
//
// No App Store Connect products exist yet (no paid Apple account), so every
// StoreKit call degrades gracefully: products fail to load -> the paywall
// shows the design with placeholder prices, and nothing crashes.

import Foundation
import StoreKit

// MARK: - Catalog + entitlement logic (pure, testable, actor-free)

enum PlusCatalog {
  /// StoreKit 2 product identifiers, following the bundle-id convention
  /// already documented in docs/APP_STORE_CHECKLIST.md.
  static let yearlyID = "app.lensmood.ios.plus.yearly"
  static let lifetimeID = "app.lensmood.ios.plus.lifetime"
  static let productIDs: [String] = [yearlyID, lifetimeID]

  /// Cameras that are free forever — a real product on their own, spanning
  /// the aesthetic range (party flash, tape video, classic street, instant,
  /// monochrome, night neon). Per docs/PROFIT_ENGINE.md never-list #6,
  /// nothing ever leaves this set once shipped.
  static let freeForeverStockIDs: Set<String> = [
    "disposable",
    "camcorder-90s",
    "leica-street",
    "polaroid",
    "film-noir",
    "tokyo-neon",
  ]

  /// Design-time placeholder price strings. Shown ONLY when StoreKit has no
  /// products to offer (no App Store Connect setup yet, or offline on first
  /// run). Real, localized prices always come from Product.displayPrice —
  /// App Review flags hard-coded USD on a live purchase path, so these must
  /// never render once real products load.
  enum PlaceholderPrice {
    static let yearly = "$19.99"
    static let lifetime = "$49.99"
  }

  enum Entitlement: String {
    case free
    case plus
  }

  /// The Plus set is everything that is not free forever, derived so a new
  /// stock can never silently fall through the gate.
  static func plusStockIDs(allStockIDs: [String]) -> Set<String> {
    Set(allStockIDs).subtracting(freeForeverStockIDs)
  }

  /// The single gate every lock check goes through. `everythingFree` is
  /// `Store.everythingFreeForNow` in production and a plain parameter here
  /// so tests can simulate the flip without touching the flag.
  static func isStockUnlocked(
    _ stockID: String,
    entitlement: Entitlement,
    everythingFree: Bool
  ) -> Bool {
    if everythingFree { return true }
    if entitlement == .plus { return true }
    return freeForeverStockIDs.contains(stockID)
  }

  /// Exactly which cameras are locked for a given state — the paywall and
  /// tests both key off this, so the lock set has one definition.
  static func lockedStockIDs(
    allStockIDs: [String],
    entitlement: Entitlement,
    everythingFree: Bool
  ) -> Set<String> {
    Set(allStockIDs).filter {
      !isStockUnlocked($0, entitlement: entitlement, everythingFree: everythingFree)
    }
  }
}

// MARK: - Store (StoreKit 2)

@MainActor
final class Store: ObservableObject {
  static let shared = Store()

  /// THE gate. True while the product is being shaped: no locks anywhere,
  /// the paywall is reachable only from AccountView as a design preview.
  /// The owner flips this to false when pricing is decided at the end —
  /// mirroring EVERYTHING_FREE_FOR_NOW in the reference store.
  static let everythingFreeForNow = true

  /// DEBUG-only gate rehearsal: launching with LENSMOOD_REHEARSAL=gate-on
  /// renders the app exactly as it will behave after the owner flips the
  /// gate — for design review and screenshot evidence only ("done means
  /// seen": the gate work is otherwise invisible while inert). Follows the
  /// precedent of AccountView's DEBUG-only paywall preview and the
  /// LENSMOOD_AD_MODE harness. Compiled out of release builds entirely; the
  /// shipped flag above is never touched.
  static let gateRehearsal: Bool = {
    #if DEBUG
      return ProcessInfo.processInfo.environment["LENSMOOD_REHEARSAL"] == "gate-on"
    #else
      return false
    #endif
  }()

  /// The effective openness every gate check reads: the shipped flag, minus
  /// the DEBUG rehearsal. Identical to `everythingFreeForNow` in release.
  static var allGatesOpen: Bool {
    everythingFreeForNow && !gateRehearsal
  }

  /// Loaded App Store products, cheapest first. Empty until
  /// App Store Connect products exist and load — the paywall then falls
  /// back to PlusCatalog.PlaceholderPrice.
  @Published private(set) var products: [Product] = []

  /// True once a load attempt finished (success or failure), so the paywall
  /// can tell "still loading" apart from "nothing to load".
  @Published private(set) var productsLoaded = false

  /// What the user actually owns, from verified StoreKit transactions.
  /// Independent of the global gate: while everythingFreeForNow is true a
  /// `free` entitlement still unlocks everything.
  @Published private(set) var entitlement: PlusCatalog.Entitlement = .free

  private var updatesTask: Task<Void, Never>?

  private init() {
    // Keep entitlement fresh across renewals, refunds, and Ask to Buy —
    // safe with zero products configured: the sequence just stays quiet.
    updatesTask = Task { [weak self] in
      for await update in StoreKit.Transaction.updates {
        guard case .verified(let transaction) = update else { continue }
        await transaction.finish()
        await self?.refreshEntitlement()
      }
    }
  }

  // MARK: Gate checks (every lock in the app goes through these)

  var isPlus: Bool {
    Self.allGatesOpen || entitlement == .plus
  }

  func isUnlocked(_ stock: Stock) -> Bool {
    PlusCatalog.isStockUnlocked(
      stock.id,
      entitlement: entitlement,
      everythingFree: Self.allGatesOpen
    )
  }

  // MARK: The loaded roll (film-door checks — see ExposureRoll.swift)

  /// What stands between this camera and a develop right now. `.open` for
  /// every camera while Store.everythingFreeForNow.
  func developAccess(for stock: Stock) -> ExposureRoll.Access {
    ExposureRoll.access(
      stockID: stock.id,
      entitlement: entitlement,
      everythingFree: Self.allGatesOpen,
      spentExposures: ExposureLedger.shared.spent(on: stock.id)
    )
  }

  /// Spend one loaded exposure on a locked camera. Returns false when the
  /// roll is spent — and when the camera is open, because an open camera
  /// never spends film.
  func spendExposure(on stock: Stock) -> Bool {
    guard case .loaded = developAccess(for: stock) else { return false }
    ExposureLedger.shared.recordSpend(on: stock.id)
    objectWillChange.send()
    return true
  }

  /// Give a spent exposure back when its develop never landed — the camera
  /// never eats a frame it didn't deliver.
  func refundExposure(on stock: Stock) {
    ExposureLedger.shared.refundSpend(on: stock.id)
    objectWillChange.send()
  }

  // MARK: Products

  var yearlyProduct: Product? {
    products.first { $0.id == PlusCatalog.yearlyID }
  }

  var lifetimeProduct: Product? {
    products.first { $0.id == PlusCatalog.lifetimeID }
  }

  /// Load products and refresh ownership. Call from the paywall's .task —
  /// never blocks UI, never throws out, tolerates total StoreKit absence.
  func start() async {
    await loadProducts()
    await refreshEntitlement()
  }

  func loadProducts() async {
    do {
      let loaded = try await Product.products(for: PlusCatalog.productIDs)
      products = loaded.sorted { $0.price < $1.price }
    } catch {
      // No App Store Connect setup yet, or no network: the paywall renders
      // its design with placeholder prices instead.
      products = []
    }
    productsLoaded = true
  }

  func refreshEntitlement() async {
    var ownsPlus = false
    for await result in StoreKit.Transaction.currentEntitlements {
      guard case .verified(let transaction) = result else { continue }
      guard transaction.revocationDate == nil else { continue }
      if PlusCatalog.productIDs.contains(transaction.productID) {
        ownsPlus = true
      }
    }
    entitlement = ownsPlus ? .plus : .free
  }

  // MARK: Purchasing

  enum PurchaseOutcome: Equatable {
    case success
    case cancelled
    case pending
    case unavailable
    case failed
  }

  func purchase(_ product: Product) async -> PurchaseOutcome {
    do {
      let result = try await product.purchase()
      switch result {
      case .success(let verification):
        guard case .verified(let transaction) = verification else { return .failed }
        await transaction.finish()
        await refreshEntitlement()
        return .success
      case .userCancelled:
        return .cancelled
      case .pending:
        // Ask to Buy / deferred — the updates listener completes it later.
        return .pending
      @unknown default:
        return .failed
      }
    } catch {
      return .failed
    }
  }

  /// Restore is always offered on the paywall (App Review requires the
  /// affordance) and quietly re-reads ownership even when sync fails.
  func restore() async -> Bool {
    do {
      try await AppStore.sync()
    } catch {
      // User cancelled the sign-in sheet or nothing is configured yet.
    }
    await refreshEntitlement()
    return entitlement == .plus
  }
}
