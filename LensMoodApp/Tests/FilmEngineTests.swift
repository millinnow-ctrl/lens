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

  func testSlide64AgainstFirstGoldenFixture() throws {
    let bundle = Bundle(for: Self.self)
    let sourceURL = try XCTUnwrap(bundle.url(forResource: "sample-golden", withExtension: "jpg"))
    let referenceURL = try XCTUnwrap(bundle.url(forResource: "golden-kodachrome", withExtension: "png"))
    let source = try XCTUnwrap(UIImage(contentsOfFile: sourceURL.path))
    let reference = try XCTUnwrap(UIImage(contentsOfFile: referenceURL.path))
    let rendered = try FilmEngine().develop(
      source,
      with: CameraRecipe.recipe(for: "kodachrome"),
      maxPixelSize: 560,
      seed: 1
    ).image

    XCTAssertEqual(rendered.cgImage?.width, reference.cgImage?.width)
    XCTAssertEqual(rendered.cgImage?.height, reference.cgImage?.height)

    let error = meanAbsoluteRGBError(rendered, reference)
    print("Slide 64 pilot MAE: \(error)/255")
    XCTAssertLessThan(
      error,
      55,
      "The pilot Swift port has drifted beyond the broad bring-up threshold."
    )

    let renderedAttachment = XCTAttachment(image: rendered)
    renderedAttachment.name = "Swift-Slide-64"
    renderedAttachment.lifetime = .keepAlways
    add(renderedAttachment)

    let referenceAttachment = XCTAttachment(image: reference)
    referenceAttachment.name = "Reference-Kodachrome"
    referenceAttachment.lifetime = .keepAlways
    add(referenceAttachment)
  }

  private func meanAbsoluteRGBError(_ first: UIImage, _ second: UIImage) -> Double {
    guard let firstCG = first.cgImage,
          let secondCG = second.cgImage,
          firstCG.width == secondCG.width,
          firstCG.height == secondCG.height else {
      return .infinity
    }
    let left = rgbaBytes(firstCG)
    let right = rgbaBytes(secondCG)
    var total = 0
    var samples = 0
    for index in stride(from: 0, to: min(left.count, right.count), by: 4) {
      total += abs(Int(left[index]) - Int(right[index]))
      total += abs(Int(left[index + 1]) - Int(right[index + 1]))
      total += abs(Int(left[index + 2]) - Int(right[index + 2]))
      samples += 3
    }
    return samples == 0 ? .infinity : Double(total) / Double(samples)
  }

  private func rgbaBytes(_ image: CGImage) -> [UInt8] {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
      data: &bytes,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
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
