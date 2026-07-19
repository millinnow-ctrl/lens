// ExposureRoll — the loaded-film economics of a locked camera.
//
// Design: R76 gate redesign ("the camera comes loaded"). Every Plus camera
// carries a short roll of real exposures. Spending one develops the
// photograph in full — full ceremony, full resolution, kept on the Roll,
// saved and shared freely — identical in every way to a free camera's
// develop. When the roll is spent the camera stops firing: no develop, no
// staged render, nothing left to screenshot. Buying Plus is buying the
// camera, not removing a nag.
//
// The roll is finite on purpose and never replenishes: film does not
// respawn, and a regenerating meter is software scarcity wearing film's
// clothes. The count is stated plainly wherever it appears — no urgency, no
// countdowns, no guilt copy (docs/PROFIT_ENGINE.md never-list #5).
//
// Entirely inert while Store.everythingFreeForNow is true: access() answers
// .open before the ledger is ever consulted.

import Foundation

// MARK: - Policy (pure, testable — the PlusCatalog pattern)

enum ExposureRoll {
  /// How many exposures a locked camera comes loaded with. Small enough
  /// that a loved camera runs dry within one real session (a taste, never a
  /// solution); large enough to prove the camera on more than one photograph.
  static let loadedExposures = 3

  /// What stands between a camera and a develop.
  enum Access: Equatable {
    /// Develops without limit: free-forever camera, Plus member, or every
    /// gate open.
    case open
    /// Locked camera with film in it (`remaining` ≥ 1) — developing spends
    /// one exposure and the photograph is kept.
    case loaded(remaining: Int)
    /// Locked camera, roll spent — the camera doesn't fire.
    case spent
  }

  /// The one film-door check. `everythingFree` mirrors the PlusCatalog
  /// parameter so tests can simulate the flip without touching the flag.
  static func access(
    stockID: String,
    entitlement: PlusCatalog.Entitlement,
    everythingFree: Bool,
    spentExposures: Int
  ) -> Access {
    if PlusCatalog.isStockUnlocked(
      stockID, entitlement: entitlement, everythingFree: everythingFree
    ) {
      return .open
    }
    let remaining = max(0, loadedExposures - spentExposures)
    return remaining > 0 ? .loaded(remaining: remaining) : .spent
  }
}

// MARK: - Ledger (persistence)

/// Where spent exposures are remembered, per camera. UserDefaults-backed
/// with an injectable suite so tests never touch the real ledger.
final class ExposureLedger {
  static let shared = ExposureLedger()

  private static let key = "exposures.spentByCamera"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func spent(on stockID: String) -> Int {
    (defaults.dictionary(forKey: Self.key)?[stockID] as? Int) ?? 0
  }

  func recordSpend(on stockID: String) {
    var table = defaults.dictionary(forKey: Self.key) ?? [:]
    table[stockID] = spent(on: stockID) + 1
    defaults.set(table, forKey: Self.key)
  }

  /// Give a frame back when its develop never landed (render failure or
  /// abandonment mid-develop) — the camera never eats film it didn't
  /// deliver. Floors at zero.
  func refundSpend(on stockID: String) {
    var table = defaults.dictionary(forKey: Self.key) ?? [:]
    table[stockID] = max(0, spent(on: stockID) - 1)
    defaults.set(table, forKey: Self.key)
  }

  // MARK: Pending spends (crash-safe reconciliation)
  //
  // A spend is written to the ledger the instant the shutter (or film door)
  // fires, but the frame it buys lands seconds later — a full read + render.
  // If the process dies in that window the in-memory refund paths never run
  // and the exposure is eaten with nothing delivered. So every spend also
  // parks a pending marker keyed by the id the delivered frame WILL carry;
  // an in-session refund drops the marker, and at the next launch any marker
  // whose frame is not on the Roll is refunded. The delivered-marker check is
  // the reader's job (reconcile), so a frame that did land is never re-minted.

  private static let pendingKey = "exposures.pendingSpends"

  /// The outstanding spends, `frame id → camera id`.
  var pendingSpends: [UUID: String] {
    let table = (defaults.dictionary(forKey: Self.pendingKey) as? [String: String]) ?? [:]
    return Dictionary(uniqueKeysWithValues: table.compactMap { key, value in
      UUID(uuidString: key).map { ($0, value) }
    })
  }

  /// Park a spend as outstanding, keyed by the id its delivered frame will use.
  func recordPendingSpend(assetID: UUID, on stockID: String) {
    var table = (defaults.dictionary(forKey: Self.pendingKey) as? [String: String]) ?? [:]
    table[assetID.uuidString] = stockID
    defaults.set(table, forKey: Self.pendingKey)
  }

  /// Drop a pending marker whose spend was already reconciled in-session
  /// (a render failure or an abandonment refunded it) so launch cannot refund
  /// the same spend twice.
  func clearPendingSpend(assetID: UUID) {
    var table = (defaults.dictionary(forKey: Self.pendingKey) as? [String: String]) ?? [:]
    guard table[assetID.uuidString] != nil else { return }
    table[assetID.uuidString] = nil
    defaults.set(table, forKey: Self.pendingKey)
  }

  /// Reconcile every outstanding spend at launch: one whose frame is not among
  /// `deliveredAssetIDs` (the Roll that survived to disk) never delivered —
  /// give that exposure back. Delivered ones are simply retired. Clears the
  /// pending store. Returns the camera ids refunded (for tests).
  @discardableResult
  func reconcilePendingSpends(deliveredAssetIDs: Set<UUID>) -> [String] {
    let pending = pendingSpends
    guard !pending.isEmpty else { return [] }
    var refunded: [String] = []
    for (assetID, stockID) in pending where !deliveredAssetIDs.contains(assetID) {
      refundSpend(on: stockID)
      refunded.append(stockID)
    }
    defaults.removeObject(forKey: Self.pendingKey)
    return refunded
  }
}
