import CoreImage
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

  // MARK: grain stage 1 (multi-scale, luminance-responsive)

  func testGainDrivenGrainDevelopIsDeterministicForASeed() throws {
    // camcorder-90s: the heaviest develop-path grain user (gain-driven), so
    // the stage-1 texture is pinned byte-identical at the develop level
    let source = testImage()
    let recipe = CameraRecipe.recipe(for: "camcorder-90s")
    let first = try FilmEngine().develop(source, with: recipe, seed: 11).image
    let second = try FilmEngine().develop(source, with: recipe, seed: 11).image
    XCTAssertEqual(pixelBytes(first), pixelBytes(second))
  }

  func testGrainTextureIsDeterministicForASeed() throws {
    let engine = FilmEngine()
    let field = grainField(level: 0.5)
    let first = grainBytes(engine, engine.applyGrain(field, amount: 0.3, size: 1.0, seed: 3))
    let second = grainBytes(engine, engine.applyGrain(field, amount: 0.3, size: 1.0, seed: 3))
    XCTAssertFalse(first.isEmpty)
    XCTAssertEqual(first, second, "same inputs → same grain bytes")
    let reseeded = grainBytes(engine, engine.applyGrain(field, amount: 0.3, size: 1.0, seed: 4))
    XCTAssertNotEqual(first, reseeded, "a different seed must lay different grain")
  }

  func testGrainPeaksInMidtonesAndFallsAtTheExtremes() throws {
    // the stage-1 luminance response: midtones carry the grain; deep shadows
    // and near-highlights fall to the response floor instead of staying flat
    let mid = grainDeviation(level: 0.5)
    let shadow = grainDeviation(level: 0.02)
    let highlight = grainDeviation(level: 0.93)
    XCTAssertGreaterThan(mid, 6, "midtone grain must be plainly visible at amount 0.3")
    XCTAssertGreaterThan(mid, shadow * 2, "deep shadows must carry far less grain than midtones")
    XCTAssertGreaterThan(mid, highlight * 2, "highlights must carry far less grain than midtones")
    XCTAssertGreaterThan(shadow, 0.3, "the response floor keeps shadows alive, not sterile")
  }

  private func grainField(level: CGFloat) -> CIImage {
    CIImage(color: CIColor(red: level, green: level, blue: level))
      .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
  }

  private func grainBytes(_ engine: FilmEngine, _ image: CIImage) -> [UInt8] {
    guard let cg = engine.context.createCGImage(
      image,
      from: image.extent,
      format: .RGBA8,
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
    ) else { return [] }
    return rgbaBytes(cg)
  }

  /// Mean absolute deviation (0…255) of the red channel from its own mean
  /// after graining a flat field — the visible grain strength at that level.
  private func grainDeviation(level: CGFloat) -> Double {
    let engine = FilmEngine()
    let px = grainBytes(engine, engine.applyGrain(
      grainField(level: level), amount: 0.3, size: 1.0, seed: 3
    ))
    guard !px.isEmpty else { return -1 }
    var mean = 0.0
    var n = 0.0
    for i in stride(from: 0, to: px.count, by: 4) {
      mean += Double(px[i])
      n += 1
    }
    mean /= n
    var deviation = 0.0
    for i in stride(from: 0, to: px.count, by: 4) {
      deviation += abs(Double(px[i]) - mean)
    }
    return deviation / n
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
      let nameTokens = Set(stock.name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
      let taglineTokens = Set(stock.tagline.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
      for term in forbidden {
        let token = term.lowercased()
        XCTAssertFalse(nameTokens.contains(token), "\(stock.name) contains \(term)")
        XCTAssertFalse(taglineTokens.contains(token), "\(stock.tagline) contains \(term)")
      }
    }
  }

  func testVisibleProductCopyAvoidsAILabeling() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let sourcesDirectory = testsDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("Sources")
    let enumerator = try XCTUnwrap(
      FileManager.default.enumerator(
        at: sourcesDirectory,
        includingPropertiesForKeys: nil
      )
    )
    let forbiddenPattern = #"(?i)\b(ai|artificial intelligence|machine learning)\b"#

    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
      let source = try String(contentsOf: fileURL, encoding: .utf8)
      XCTAssertNil(
        source.range(of: forbiddenPattern, options: .regularExpression),
        "Visible product source contains AI labeling in \(fileURL.lastPathComponent)"
      )
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

  /// CI-measured Class A baselines (run 148, head 714f070) plus ~1/255
  /// runner headroom. This is a REGRESSION gate, not a parity claim: only
  /// Slide 64 meets the approved <=2.0 target so far; the other nine values
  /// record honestly how far each camera still is, and may only go down.
  static let maeRegressionCeiling: [String: Double] = [
    "kodachrome": 2.0,
    // pastel-cinema: R87A woke the GLOBAL powdery Wes-Anderson palette on daylight
    // — powdery desaturation + soft highlight rolloff + high-key lift + a whisper
    // of cream (owner-approved refinement BEYOND the frozen reference LUT,
    // 2026-07-20; see FilmEngine.applyPastelDaylightPalette). The daylight golden
    // intentionally moves away from the neutral reference render; night is
    // byte-identical (scene-keyed off). Raised from the 18.3 pre-refinement
    // baseline by reasoning (~0.55 golden weight × the desat/rolloff/lift, direction
    // uncertain vs the reference), run 252 measured 13.03 — the powder palette landed
    // CLOSER to the reference than the pre-refinement render (18.3): the
    // reference engine's pastel always had this softness and the port had
    // lost it. Tightened to measured+2.
    "pastel-cinema": 15.0,
    "polaroid": 18.9,
    "gq-editorial": 19.7,
    // a24-still: R87A gave the Independent Still its BASE identity — a lifted-black
    // filmic curve + subtle teal shadows, muted saturation, distinct from Leica's
    // clean contrast (owner-approved refinement BEYOND the frozen reference LUT,
    // 2026-07-20; see FilmEngine.applyA24FilmicBase). A base look applied day AND
    // night, so it moves the golden AND the night render. Raised from the 23.1
    // pre-refinement baseline by reasoning (full-strength toe/teal/desat on the
    // golden), run 252 measured 11.80 — the filmic base landed CLOSER
    // to the reference than the pre-refinement render (23.1): the reference
    // a24 always carried lifted blacks the clean port was missing. Tightened
    // to measured+2.
    "a24-still": 13.8,
    "leica-street": 25.2,
    // tokyo-neon: R61 source bloom REFUSES daylight (neon does not exist under the
    // sun). R87A adds a GLOBAL daylight de-cast of the residual lavender the Wave-1
    // sky pass leaves — red-excess pulled down, green lifted toward tokyo's real
    // cool teal-blue signature (owner-approved refinement BEYOND the frozen
    // reference LUT, 2026-07-20; see FilmEngine.applyTokyoDaylightNeutralize). It
    // diverges from the lavender-baked golden on daylight; night byte-identical
    // (scene-keyed off). Raised from the 28.2 pre-refinement baseline by reasoning
    // (~0.55 golden weight × the de-cast), run 252 measured 28.61 (was 28.2
    // pre-refinement — the de-cast is a small honest divergence). Tightened to
    // measured+2.
    "tokyo-neon": 30.6,
    "super-8": 34.3,
    // film-noir: cool silver tone + R61 directional key shadow (owner-directed
    // physics). CI-measured 21.97 on the golden, visually approved — the sky
    // falls away from the sun with real depth. Tightened to measured+2.
    "film-noir": 24.0,
    // tintype: intentionally re-graded to a COOL orthochromatic wet-plate per
    // owner direction — diverges from the warm reference golden but the measured
    // MAE (~17.8) is small; tightened to lock the new cool look as the baseline.
    "tintype": 20.0,
  ]

  func testAllClassACamerasAgainstGoldenFixtures() throws {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let sourceURL = testsDirectory
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("reference/photos/sample-golden.jpg")
    let source = try XCTUnwrap(UIImage(contentsOfFile: sourceURL.path))
    let cameraIDs = [
      "kodachrome", "a24-still", "film-noir", "pastel-cinema", "tokyo-neon",
      "leica-street", "polaroid", "tintype", "super-8", "gq-editorial",
    ]

    for cameraID in cameraIDs {
      let referenceURL = testsDirectory
        .appendingPathComponent("Fixtures/golden-\(cameraID).png")
      let reference = try XCTUnwrap(UIImage(contentsOfFile: referenceURL.path))
      let rendered = try FilmEngine().develop(
        source,
        with: CameraRecipe.recipe(for: cameraID),
        maxPixelSize: 560,
        seed: 1,
        analyzeSubjects: false
      ).image

      XCTAssertEqual(rendered.cgImage?.width, reference.cgImage?.width, cameraID)
      XCTAssertEqual(rendered.cgImage?.height, reference.cgImage?.height, cameraID)

      let error = meanAbsoluteRGBError(rendered, reference)
      print("Class A \(cameraID) MAE: \(error)/255")
      try writeParityEvidence(cameraID: cameraID, source: source, reference: reference, rendered: rendered)
      if cameraID == "kodachrome" {
        XCTAssertLessThanOrEqual(
          error,
          2,
          "Slide 64 must meet the approved parity target before completion."
        )
      }
      let ceiling = try XCTUnwrap(
        Self.maeRegressionCeiling[cameraID],
        "no recorded baseline for \(cameraID)"
      )
      XCTAssertLessThanOrEqual(
        error,
        ceiling,
        "\(cameraID) drifted above its recorded CI baseline. Parity may only improve toward the 2.0 target — never regress."
      )

      let renderedAttachment = XCTAttachment(image: rendered)
      renderedAttachment.name = "Swift-\(cameraID)"
      renderedAttachment.lifetime = .keepAlways
      add(renderedAttachment)

      let referenceAttachment = XCTAttachment(image: reference)
      referenceAttachment.name = "Reference-\(cameraID)"
      referenceAttachment.lifetime = .keepAlways
      add(referenceAttachment)
    }
  }

  private func writeParityEvidence(
    cameraID: String,
    source: UIImage,
    reference: UIImage,
    rendered: UIImage
  ) throws {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let outputDirectory = testsDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("ui-artifacts/parity/\(cameraID)")
    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )

    let difference = try absoluteDifference(reference, rendered)
    let sideBySide = sideBySide(reference, rendered)
    let images: [(String, UIImage)] = [
      ("original.png", source),
      ("reference.png", reference),
      ("swift.png", rendered),
      ("difference.png", difference),
      ("side-by-side.png", sideBySide),
    ]
    for (name, image) in images {
      let data = try XCTUnwrap(image.pngData(), "Could not encode \(name)")
      try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
    }
  }

  private func absoluteDifference(_ first: UIImage, _ second: UIImage) throws -> UIImage {
    let firstCG = try XCTUnwrap(first.cgImage)
    let secondCG = try XCTUnwrap(second.cgImage)
    XCTAssertEqual(firstCG.width, secondCG.width)
    XCTAssertEqual(firstCG.height, secondCG.height)
    let left = rgbaBytes(firstCG)
    let right = rgbaBytes(secondCG)
    var difference = [UInt8](repeating: 0, count: left.count)
    for index in stride(from: 0, to: min(left.count, right.count), by: 4) {
      difference[index] = UInt8(abs(Int(left[index]) - Int(right[index])))
      difference[index + 1] = UInt8(abs(Int(left[index + 1]) - Int(right[index + 1])))
      difference[index + 2] = UInt8(abs(Int(left[index + 2]) - Int(right[index + 2])))
      difference[index + 3] = 255
    }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
      data: &difference,
      width: firstCG.width,
      height: firstCG.height,
      bitsPerComponent: 8,
      bytesPerRow: firstCG.width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    return UIImage(cgImage: try XCTUnwrap(context?.makeImage()))
  }

  private func sideBySide(_ reference: UIImage, _ rendered: UIImage) -> UIImage {
    guard let referenceCG = reference.cgImage, let renderedCG = rendered.cgImage else {
      return reference
    }
    let size = CGSize(
      width: referenceCG.width + renderedCG.width,
      height: max(referenceCG.height, renderedCG.height)
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    // UIImage.draw is UIKit-coordinate aware; raw CGContext.draw rendered
    // both panes upside down in the review evidence
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      UIImage(cgImage: referenceCG).draw(
        in: CGRect(x: 0, y: 0, width: referenceCG.width, height: referenceCG.height)
      )
      UIImage(cgImage: renderedCG).draw(
        in: CGRect(
          x: referenceCG.width,
          y: 0,
          width: renderedCG.width,
          height: renderedCG.height
        )
      )
    }
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


