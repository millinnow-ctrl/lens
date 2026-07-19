import XCTest
@testable import LensMood

/// Pins the unified Lens schema as the single source of truth: the catalog must
/// stay perfectly aligned with the authoritative `Stock` and `CameraRecipe`
/// tables (same ids, same order), expose coherent pipelines, and keep the
/// honest "deterministic-only, free, universal" invariants until learned
/// refinement is actually built and validated per lens.
final class LensCatalogTests: XCTestCase {

  func testCatalogCoversAllEighteenLenses() {
    XCTAssertEqual(Lens.all.count, 18)
  }

  func testIdsAndOrderMatchStockAndRecipe() {
    XCTAssertEqual(Lens.all.map(\.id), Stock.all.map(\.id), "Lens catalog order must mirror Stock.all")
    XCTAssertEqual(Set(Lens.all.map(\.id)), Set(CameraRecipe.all.map(\.id)), "Lens ids must match CameraRecipe ids")
  }

  func testEveryLensResolvesItsComposedSources() {
    for lens in Lens.all {
      XCTAssertEqual(lens.stock.id, lens.id)
      XCTAssertEqual(lens.recipe.id, lens.id)
      XCTAssertEqual(lens.definition.id, lens.id)
      XCTAssertEqual(lens.name, lens.stock.name)
    }
  }

  func testFallbackAlwaysResolves() {
    let ids = Set(Lens.all.map(\.id))
    for lens in Lens.all {
      XCTAssertTrue(ids.contains(lens.fallbackLensID), "\(lens.id) fallback \(lens.fallbackLensID) not in catalog")
    }
  }

  func testAnalyticsIdIsSnakeCasedAndUnique() {
    var seen = Set<String>()
    for lens in Lens.all {
      XCTAssertFalse(lens.analyticsID.contains("-"), "\(lens.id) analyticsID must be snake_case")
      XCTAssertTrue(lens.analyticsID.hasPrefix("lens_"))
      XCTAssertTrue(seen.insert(lens.analyticsID).inserted, "duplicate analyticsID \(lens.analyticsID)")
    }
  }

  func testDefaultIntensityInRange() {
    for lens in Lens.all {
      XCTAssertGreaterThan(lens.defaultIntensity, 0)
      XCTAssertLessThanOrEqual(lens.defaultIntensity, 1)
    }
  }

  func testPipelineShapes() {
    for lens in Lens.all {
      // Preview always starts cheap (proxy) and never runs a full-res or
      // learned pass — preview stays fast and identity-safe.
      XCTAssertEqual(lens.pipeline.preview.first, .proxy, "\(lens.id) preview must start at proxy")
      XCTAssertFalse(lens.pipeline.preview.contains(.fullRes), "\(lens.id) preview must not go full-res")
      XCTAssertFalse(lens.pipeline.preview.contains(.refinement), "\(lens.id) preview must not run refinement")
      // Export always ends by producing a full-resolution result (refinement,
      // when present, appends after it).
      XCTAssertTrue(lens.pipeline.export.contains(.fullRes), "\(lens.id) export must include full-res")

      // Subject-aware stage appears iff the lens declares masks.
      let hasMasks = lens.requiredMasks != .none
      XCTAssertEqual(lens.pipeline.preview.contains(.subjectAware), hasMasks, "\(lens.id) subjectAware/masks mismatch")
    }
  }

  func testCurrentInvariantsDeterministicFreeUniversal() {
    // Honest state today: no downloadable models, nothing gated, nothing paid.
    for lens in Lens.all {
      XCTAssertNil(lens.refinement, "\(lens.id) should have no learned model yet")
      XCTAssertEqual(lens.minDeviceTier, .universal, "\(lens.id) deterministic path must run everywhere")
      XCTAssertFalse(lens.isPremium, "gates are OFF (EVERYTHING_FREE_FOR_NOW)")
      XCTAssertNil(lens.entitlement)
      XCTAssertNil(lens.evalScore, "eval score must be nil until actually measured, never fabricated")
      XCTAssertTrue(lens.runsFullyOnDevice)
    }
  }

  func testEveryPopulatedCollectionResolves() {
    let collections = Lens.populatedCollections
    XCTAssertFalse(collections.isEmpty)
    // Every catalog lens belongs to a populated collection.
    for lens in Lens.all {
      XCTAssertTrue(collections.contains(lens.collection))
    }
    // No empty buckets reported as populated.
    for collection in collections {
      XCTAssertFalse(Lens.inCollection(collection).isEmpty)
    }
  }

  /// Honesty guard: the app has no data source that could make "TRENDING"
  /// or "featured" true (PrivacyInfo says Data Not Collected), so no camera
  /// may ship claiming either. The `badge` property stays for the day a real
  /// drop computes an honest "NEW".
  func testNoFabricatedBadgesInCatalog() {
    for stock in Stock.all {
      XCTAssertNotEqual(stock.badge, "trending", "\(stock.id) claims trending with no data source")
      XCTAssertNotEqual(stock.badge, "featured", "\(stock.id) claims featured with no data source")
    }
  }

  func testDeviceAndLatencyTypesOrder() {
    XCTAssertLessThan(DeviceTier.universal, DeviceTier.enhanced)
    XCTAssertLessThan(DeviceTier.enhanced, DeviceTier.highEnd)
    XCTAssertLessThan(LatencyClass.instant, LatencyClass.heavy)
  }
}
