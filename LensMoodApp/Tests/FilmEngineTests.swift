import XCTest
import UIKit
@testable import LensMood

final class FilmEngineTests: XCTestCase {
  func testCatalogHasOneRecipePerCamera() {
    XCTAssertEqual(CameraRecipe.all.count, 18)
    XCTAssertEqual(Set(CameraRecipe.all.map(\.id)).count, 18)
    XCTAssertEqual(CameraRecipe.all.filter { $0.engineClass == .staticLUT }.count, 10)
    XCTAssertEqual(CameraRecipe.all.filter { $0.engineClass == .adaptive }.count, 8)
  }

  func testAdaptiveRenderingIsDeterministicForASeed() throws {
    let source = testImage()
    let recipe = CameraRecipe.recipe(for: "disposable")
    let first = try FilmEngine().develop(source, with: recipe, seed: 42).image
    let second = try FilmEngine().develop(source, with: recipe, seed: 42).image
    XCTAssertEqual(pixelBytes(first), pixelBytes(second))
  }

  func testFilmNoirRecipeEnforcesMonochrome() {
    let recipe = CameraRecipe.recipe(for: "film-noir")
    XCTAssertTrue(recipe.monochrome)
    XCTAssertEqual(recipe.saturation, 0)
  }

  func testLowLightAdaptiveCameraRaisesExposure() throws {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
    let image = renderer.image { context in
      UIColor(white: 0.08, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    }
    let result = try FilmEngine().develop(
      image,
      with: CameraRecipe.recipe(for: "point-shoot"),
      seed: 7
    )
    XCTAssertTrue(result.scene.isLowKey)
    XCTAssertTrue(result.decisions.contains { $0.hasPrefix("Low light raised") })
  }

  func testPublicCameraNamesAvoidUnclearedBrandsAndAILanguage() {
    let forbidden = ["Leica", "GQ", "A24", "Polaroid", "Kodachrome", "iPhone", "Super 8", "AI"]
    for stock in Stock.all {
      for term in forbidden {
        XCTAssertFalse(stock.name.localizedCaseInsensitiveContains(term), "\(stock.name) contains \(term)")
        XCTAssertFalse(stock.tagline.localizedCaseInsensitiveContains(term), "\(stock.tagline) contains \(term)")
      }
    }
  }

  func testEveryAdaptiveRecipeProducesDistinctPixels() throws {
    let source = testImage()
    var outputs = Set<Data>()
    for recipe in CameraRecipe.all where recipe.engineClass == .adaptive {
      let image = try FilmEngine().develop(source, with: recipe, seed: 91).image
      outputs.insert(pixelBytes(image))
    }
    XCTAssertEqual(outputs.count, 8)
  }

  func testRecipeParameterFingerprintsAreUnique() {
    let fingerprints = CameraRecipe.all.map {
      [
        $0.exposureBias, $0.adaptiveExposure, $0.warmth, $0.saturation,
        $0.contrast, $0.shadowLift, $0.highlightCompression, $0.vignette,
        $0.bloom, $0.grain, $0.grainSize,
      ]
    }
    XCTAssertEqual(Set(fingerprints.map(String.init(describing:))).count, 18)
  }

  private func testImage() -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
    return renderer.image { context in
      UIColor(red: 0.15, green: 0.28, blue: 0.52, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
      UIColor(red: 0.92, green: 0.58, blue: 0.34, alpha: 1).setFill()
      context.fill(CGRect(x: 16, y: 12, width: 32, height: 40))
    }
  }

  private func pixelBytes(_ image: UIImage) -> Data {
    guard let cgImage = image.cgImage,
          let data = cgImage.dataProvider?.data else {
      return Data()
    }
    return data as Data
  }
}
