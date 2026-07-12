import XCTest
@testable import LensMood

/// Guards the in-app camera's opt-in modulation: with no capture settings, or
/// with the settings sitting at the loaded camera's home, the developer must
/// produce byte-identical output to the pure recipe — so every golden-fixture
/// parity result is untouched. Deviated settings must visibly change the frame.
final class FilmEngineCaptureParityTests: XCTestCase {
  private func source() throws -> UIImage {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("reference/photos/sample-golden.jpg")
    return try XCTUnwrap(UIImage(contentsOfFile: url.path))
  }

  private func bytes(_ image: UIImage) -> [UInt8] {
    guard let cg = image.cgImage else { return [] }
    var data = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
    let ctx = CGContext(
      data: &data, width: cg.width, height: cg.height,
      bitsPerComponent: 8, bytesPerRow: cg.width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    return data
  }

  private func mae(_ a: UIImage, _ b: UIImage) -> Double {
    let x = bytes(a), y = bytes(b)
    guard !x.isEmpty, x.count == y.count else { return .infinity }
    var total = 0, n = 0
    for i in stride(from: 0, to: x.count, by: 4) {
      total += abs(Int(x[i]) - Int(y[i]))
      total += abs(Int(x[i + 1]) - Int(y[i + 1]))
      total += abs(Int(x[i + 2]) - Int(y[i + 2]))
      n += 3
    }
    return n == 0 ? .infinity : Double(total) / Double(n)
  }

  func testNilCaptureIsByteIdenticalToPureRecipe() throws {
    let img = try source()
    let recipe = CameraRecipe.recipe(for: "kodachrome")
    let a = try FilmEngine.shared.develop(img, with: recipe, maxPixelSize: 560, seed: 1).image
    let b = try FilmEngine.shared.develop(img, with: recipe, maxPixelSize: 560, seed: 1, capture: nil).image
    XCTAssertEqual(mae(a, b), 0, "capture: nil must not change the developed output")
  }

  func testHomeSettingsAreByteIdenticalToPureRecipe() throws {
    let img = try source()
    let stock = Stock.find("kodachrome")
    let home = CaptureSettings.home(for: stock)
    XCTAssertTrue(home.isNeutral, "a camera at its EXIF home must be neutral")
    let pure = try FilmEngine.shared.develop(img, with: stock.recipe, maxPixelSize: 560, seed: 1).image
    let atHome = try FilmEngine.shared.develop(img, with: stock.recipe, maxPixelSize: 560, seed: 1, capture: home).image
    XCTAssertEqual(mae(pure, atHome), 0, "home settings must equal the pure recipe")
  }

  func testDeviatedSettingsVisiblyChangeTheFrame() throws {
    let img = try source()
    let stock = Stock.find("kodachrome")
    var wide = CaptureSettings.home(for: stock)
    wide.mode = .manual
    wide.aperture = 1.4          // wide open → DoF + brighter
    wide.iso = 6400              // heavy sensor grain
    wide.exposureBiasEV = 1.0
    XCTAssertFalse(wide.isNeutral)
    let pure = try FilmEngine.shared.develop(img, with: stock.recipe, maxPixelSize: 560, seed: 1).image
    let shot = try FilmEngine.shared.develop(img, with: stock.recipe, maxPixelSize: 560, seed: 1, capture: wide).image
    XCTAssertGreaterThan(mae(pure, shot), 2.0, "the dials must visibly change the developed look")
  }

  func testCaptureIsDeterministicForASeed() throws {
    let img = try source()
    let stock = Stock.find("disposable")
    var s = CaptureSettings.home(for: stock)
    s.iso = 3200
    let a = try FilmEngine.shared.develop(img, with: stock.recipe, maxPixelSize: 400, seed: 5, capture: s).image
    let b = try FilmEngine.shared.develop(img, with: stock.recipe, maxPixelSize: 400, seed: 5, capture: s).image
    XCTAssertEqual(mae(a, b), 0, "the same seed + settings must render identically")
  }

  func testAutoRelightChangesFrameAndStaysDeterministic() throws {
    let img = try source()
    let stock = Stock.find("kodachrome")
    var s = CaptureSettings.home(for: stock)
    s.autoRelight = true
    s.captureMode = .night
    XCTAssertTrue(s.isNeutral, "dials are at home; relight is a separate opt-in")
    let pure = try FilmEngine.shared.develop(img, with: stock.recipe, maxPixelSize: 560, seed: 1).image
    let relit = try FilmEngine.shared.develop(img, with: stock.recipe, maxPixelSize: 560, seed: 1, capture: s).image
    XCTAssertGreaterThan(mae(pure, relit), 1.0, "auto relight should change the frame")
    let relit2 = try FilmEngine.shared.develop(img, with: stock.recipe, maxPixelSize: 560, seed: 1, capture: s).image
    // essentially deterministic — Core Image's night-mode denoise (CINoiseReduction)
    // isn't bit-exact across runs, but stays well under a quantization step
    XCTAssertLessThan(mae(relit, relit2), 0.01, "relight must be effectively deterministic")
  }

  func testExifHomeParsesEveryStock() {
    for stock in Stock.all {
      let home = CaptureSettings.home(for: stock)
      XCTAssertGreaterThan(home.homeAperture, 0, stock.id)
      XCTAssertGreaterThan(home.homeISO, 0, stock.id)
      XCTAssertGreaterThan(home.homeShutter, 0, stock.id)
      XCTAssertTrue(home.isNeutral, "\(stock.id) should boot neutral")
    }
  }
}
