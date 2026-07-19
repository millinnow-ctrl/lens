// ExposureRoll tests — the loaded-film policy and its ledger.
//
// The policy is pure (the PlusCatalog pattern) so the film door can be
// tested exactly as it will behave after the owner flips
// Store.everythingFreeForNow, without touching the flag itself. The ledger
// tests run against an isolated UserDefaults suite.

import XCTest

@testable import LensMood

final class ExposureRollTests: XCTestCase {
  private var allIDs: [String] { Stock.all.map(\.id) }
  private var aPlusID: String {
    PlusCatalog.plusStockIDs(allStockIDs: allIDs).sorted().first!
  }

  // MARK: - Policy (pure)

  /// Gates off (today's shipped state): every camera is .open for a free
  /// user regardless of any spent count — the roll is entirely inert.
  func testEverythingFreeIsAlwaysOpen() {
    for id in allIDs {
      XCTAssertEqual(
        ExposureRoll.access(
          stockID: id, entitlement: .free, everythingFree: true,
          spentExposures: 999),
        .open,
        "\(id) must be open while everything is free"
      )
    }
  }

  /// Simulated flip: Plus opens every camera; free-forever cameras stay
  /// open for a free user; the roll never meters either.
  func testOpenCamerasNeverMeter() {
    for id in allIDs {
      XCTAssertEqual(
        ExposureRoll.access(
          stockID: id, entitlement: .plus, everythingFree: false,
          spentExposures: 999),
        .open, "\(id) must be open for Plus")
    }
    for id in PlusCatalog.freeForeverStockIDs {
      XCTAssertEqual(
        ExposureRoll.access(
          stockID: id, entitlement: .free, everythingFree: false,
          spentExposures: 999),
        .open, "\(id) is promised free forever — no meter, ever")
    }
  }

  /// Simulated flip: a locked camera comes loaded, counts down as film is
  /// spent, and stops firing at zero.
  func testLockedCameraCountsDownToSpent() {
    let id = aPlusID
    XCTAssertEqual(
      ExposureRoll.access(
        stockID: id, entitlement: .free, everythingFree: false,
        spentExposures: 0),
      .loaded(remaining: ExposureRoll.loadedExposures)
    )
    XCTAssertEqual(
      ExposureRoll.access(
        stockID: id, entitlement: .free, everythingFree: false,
        spentExposures: ExposureRoll.loadedExposures - 1),
      .loaded(remaining: 1)
    )
    XCTAssertEqual(
      ExposureRoll.access(
        stockID: id, entitlement: .free, everythingFree: false,
        spentExposures: ExposureRoll.loadedExposures),
      .spent
    )
    // over-spend (defensive: e.g. the constant was lowered between runs)
    XCTAssertEqual(
      ExposureRoll.access(
        stockID: id, entitlement: .free, everythingFree: false,
        spentExposures: ExposureRoll.loadedExposures + 5),
      .spent
    )
  }

  /// The roll is a taste, never a solution: small, and at least one frame.
  func testLoadedExposuresIsAFewNotAProduct() {
    XCTAssertGreaterThanOrEqual(ExposureRoll.loadedExposures, 1)
    XCTAssertLessThanOrEqual(
      ExposureRoll.loadedExposures, 5,
      "a loved camera must run dry within one real session"
    )
  }

  /// An unknown stock id (e.g. a future seasonal drop) meters like any
  /// locked camera — never silently unlimited.
  func testUnknownStockIsMeteredWhenLocked() {
    XCTAssertEqual(
      ExposureRoll.access(
        stockID: "seasonal-drop-2027", entitlement: .free,
        everythingFree: false, spentExposures: 0),
      .loaded(remaining: ExposureRoll.loadedExposures)
    )
  }

  /// Ported from the tournament's sample-film suite: the .plus
  /// entitlement answers .open whatever the ledger says — a member's spend
  /// history is history, never a meter.
  func testPlusEntitlementOpensEveryCameraAtAnySpendCount() {
    let counts = [
      0, ExposureRoll.loadedExposures - 1, ExposureRoll.loadedExposures,
      ExposureRoll.loadedExposures + 9,
    ]
    for spent in counts {
      for id in allIDs {
        XCTAssertEqual(
          ExposureRoll.access(
            stockID: id, entitlement: .plus, everythingFree: false,
            spentExposures: spent),
          .open,
          "\(id) must be open for Plus at \(spent) recorded spends"
        )
      }
    }
  }

  // MARK: - Ledger (isolated suite)

  private func freshLedger(_ name: String = #function) -> (ExposureLedger, UserDefaults) {
    let suite = "test.exposures.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (ExposureLedger(defaults: defaults), defaults)
  }

  func testLedgerCountsPerCameraIndependently() {
    let (ledger, _) = freshLedger()
    XCTAssertEqual(ledger.spent(on: "tintype"), 0)
    ledger.recordSpend(on: "tintype")
    ledger.recordSpend(on: "tintype")
    ledger.recordSpend(on: "lomo")
    XCTAssertEqual(ledger.spent(on: "tintype"), 2)
    XCTAssertEqual(ledger.spent(on: "lomo"), 1)
    XCTAssertEqual(ledger.spent(on: "kodachrome"), 0, "rolls are per camera")
  }

  func testLedgerRefundFloorsAtZero() {
    let (ledger, _) = freshLedger()
    ledger.recordSpend(on: "tintype")
    ledger.refundSpend(on: "tintype")
    XCTAssertEqual(ledger.spent(on: "tintype"), 0)
    ledger.refundSpend(on: "tintype")
    XCTAssertEqual(ledger.spent(on: "tintype"), 0, "a refund can never mint film")
  }

  /// Ported from the tournament's trial-roll suite: the roll is bounded
  /// at capacity. The ledger records raw counts on purpose (the truth of
  /// what happened); the clamp lives at read time — a ledger that recorded
  /// one spend past the roll still reads .spent, never a negative remaining.
  func testOverRecordedLedgerStillReadsSpentNeverNegative() {
    let (ledger, _) = freshLedger()
    for _ in 0...ExposureRoll.loadedExposures {   // N + 1 recorded spends
      ledger.recordSpend(on: "tintype")
    }
    XCTAssertEqual(
      ledger.spent(on: "tintype"), ExposureRoll.loadedExposures + 1,
      "the ledger records raw truth; clamping is the reader's job"
    )
    XCTAssertEqual(
      ExposureRoll.access(
        stockID: "tintype", entitlement: .free, everythingFree: false,
        spentExposures: ledger.spent(on: "tintype")),
      .spent
    )
  }

  func testLedgerPersistsAcrossInstances() {
    let suite = "test.exposures.persistence"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    ExposureLedger(defaults: defaults).recordSpend(on: "super-8")
    XCTAssertEqual(
      ExposureLedger(defaults: defaults).spent(on: "super-8"), 1,
      "spent film stays spent across launches"
    )
    defaults.removePersistentDomain(forName: suite)
  }

  // MARK: - The live configuration

  /// Ported from the tournament's test-roll suite: a spend is guarded
  /// on permission — spendExposure answers false unless the door is
  /// .loaded. In today's shipped state every camera is .open, so the live
  /// store must refuse all 18 and leave the shared ledger untouched; the
  /// same `guard case .loaded` refuses .spent, whose precondition is
  /// pinned here at policy level (a spent roll never reads as loaded).
  @MainActor
  func testSpendExposureRefusesWithoutALoadedRoll() {
    if !Store.gateRehearsal {   // rehearsal is a DEBUG launch choice, not CI state
      for stock in Stock.all {
        let before = ExposureLedger.shared.spent(on: stock.id)
        XCTAssertFalse(
          Store.shared.spendExposure(on: stock),
          "\(stock.id) is open — an open camera never spends film"
        )
        XCTAssertEqual(
          ExposureLedger.shared.spent(on: stock.id), before,
          "a refused spend must not touch the ledger"
        )
      }
    }
    if case .loaded = ExposureRoll.access(
      stockID: aPlusID, entitlement: .free, everythingFree: false,
      spentExposures: ExposureRoll.loadedExposures)
    {
      XCTFail("a spent roll must never read as loaded — the spend guard depends on it")
    }
  }

  /// This pass ships with every gate open and no rehearsal active: the
  /// effective flag equals the shipped flag, and the live store answers
  /// .open for all 18 cameras.
  @MainActor
  func testShippedConfigurationKeepsTheRollInert() {
    XCTAssertTrue(Store.everythingFreeForNow)
    if !Store.gateRehearsal {   // rehearsal is a DEBUG launch choice, not CI state
      XCTAssertTrue(Store.allGatesOpen)
      for stock in Stock.all {
        XCTAssertEqual(Store.shared.developAccess(for: stock), .open)
      }
    }
  }
}
