// Profit-engine tests — entitlement logic, catalog integrity, copy hygiene.
//
// PlusCatalog is deliberately pure (no actor, no StoreKit state) so the
// gate can be tested exactly as it will behave after the owner flips
// Store.everythingFreeForNow, without touching the flag itself.
//
// NOTE: project.yml currently has no test target (owned by the CI
// workstream; XcodeGen edits were out of scope for this pass). To run these,
// add a LensMoodTests unit-test bundle target sourcing `Tests` with a
// dependency on LensMood, then `xcodebuild test`.

import XCTest

@testable import LensMood

final class ProfitEngineTests: XCTestCase {
  private var allIDs: [String] { Stock.all.map(\.id) }

  // MARK: - Entitlement logic

  /// Gates off (today's shipped state): every camera is unlocked for a
  /// free user — the flag overrides everything.
  func testGatesOffUnlocksEverythingForFree() {
    for id in allIDs {
      XCTAssertTrue(
        PlusCatalog.isStockUnlocked(id, entitlement: .free, everythingFree: true),
        "\(id) must be unlocked while everything is free"
      )
    }
    XCTAssertTrue(
      PlusCatalog.lockedStockIDs(allStockIDs: allIDs, entitlement: .free, everythingFree: true)
        .isEmpty
    )
  }

  /// Simulated gate flip: a free user is locked out of exactly the Plus
  /// set — no more, no less.
  func testSimulatedGateOnLocksExactlyThePlusSet() {
    let locked = PlusCatalog.lockedStockIDs(
      allStockIDs: allIDs, entitlement: .free, everythingFree: false)
    XCTAssertEqual(locked, PlusCatalog.plusStockIDs(allStockIDs: allIDs))
    for id in PlusCatalog.freeForeverStockIDs {
      XCTAssertTrue(
        PlusCatalog.isStockUnlocked(id, entitlement: .free, everythingFree: false),
        "\(id) is promised free forever"
      )
    }
  }

  /// Simulated gate flip: Plus unlocks everything.
  func testSimulatedGateOnPlusUnlocksEverything() {
    XCTAssertTrue(
      PlusCatalog.lockedStockIDs(allStockIDs: allIDs, entitlement: .plus, everythingFree: false)
        .isEmpty
    )
  }

  /// An unknown stock id (e.g. a future seasonal drop not yet in the free
  /// set) must default to locked once gates are on — never silently free.
  func testUnknownStockDefaultsToLockedForFreeUsers() {
    XCTAssertFalse(
      PlusCatalog.isStockUnlocked(
        "seasonal-drop-2027", entitlement: .free, everythingFree: false))
    XCTAssertTrue(
      PlusCatalog.isStockUnlocked(
        "seasonal-drop-2027", entitlement: .plus, everythingFree: false))
  }

  /// The shipped flag itself: this pass ships with every gate open.
  /// When the owner intentionally flips it, this test is the one place
  /// that must be updated — a deliberate speed bump.
  func testShippedConfigurationIsEverythingFree() {
    XCTAssertTrue(Store.everythingFreeForNow)
  }

  // MARK: - Catalog integrity

  func testProductIDsAreUniqueAndWellFormed() {
    XCTAssertEqual(PlusCatalog.productIDs.count, Set(PlusCatalog.productIDs).count)
    XCTAssertFalse(PlusCatalog.productIDs.isEmpty)
    for id in PlusCatalog.productIDs {
      XCTAssertTrue(id.hasPrefix("app.lensmood.ios."), "\(id) breaks the bundle-id convention")
    }
    XCTAssertNotEqual(PlusCatalog.yearlyID, PlusCatalog.lifetimeID)
  }

  func testFreeSetIsNonEmptyAndRealAndPartitionsTheCatalog() {
    XCTAssertFalse(PlusCatalog.freeForeverStockIDs.isEmpty, "free tier must exist")
    // Every free-forever id names a real camera.
    XCTAssertTrue(
      PlusCatalog.freeForeverStockIDs.isSubset(of: Set(allIDs)),
      "free set contains an id missing from Stock.all"
    )
    // free + plus is a clean partition of the 18.
    let plus = PlusCatalog.plusStockIDs(allStockIDs: allIDs)
    XCTAssertTrue(plus.isDisjoint(with: PlusCatalog.freeForeverStockIDs))
    XCTAssertEqual(plus.union(PlusCatalog.freeForeverStockIDs), Set(allIDs))
    // The launch design: a few full cameras free, most in Plus.
    XCTAssertGreaterThanOrEqual(PlusCatalog.freeForeverStockIDs.count, 3)
    XCTAssertFalse(plus.isEmpty, "Plus must contain cameras or there is nothing to sell")
  }

  func testStockIDsAreUnique() {
    XCTAssertEqual(allIDs.count, Set(allIDs).count)
  }

  // MARK: - Copy hygiene

  /// CI-mirrored rule: no Sources file — comments included — may contain
  /// the standalone tokens on the banned list. The tokens are assembled
  /// from fragments so this test file cannot itself trip the scan.
  func testCopyHygieneAcrossAllSources() throws {
    let banned = [
      "a" + "i",
      "artificial" + " " + "intelligence",
      "machine" + " " + "learning",
    ]
    let pattern = "\\b(?:" + banned.joined(separator: "|") + ")\\b"
    let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

    let sourcesDir = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Tests/
      .deletingLastPathComponent()  // LensMoodApp/
      .appendingPathComponent("Sources")
    let enumerator = FileManager.default.enumerator(
      at: sourcesDir, includingPropertiesForKeys: nil)
    var scanned = 0
    while let url = enumerator?.nextObject() as? URL {
      guard url.pathExtension == "swift" else { continue }
      let text = try String(contentsOf: url, encoding: .utf8)
      let range = NSRange(text.startIndex..., in: text)
      if let match = regex.firstMatch(in: text, options: [], range: range),
        let r = Range(match.range, in: text)
      {
        XCTFail("banned token \"\(text[r])\" in \(url.lastPathComponent)")
      }
      scanned += 1
    }
    XCTAssertGreaterThan(scanned, 0, "copy-hygiene scan found no Swift sources")
  }
}
