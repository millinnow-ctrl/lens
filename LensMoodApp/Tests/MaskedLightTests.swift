import CoreImage
import UIKit
import XCTest
@testable import LensMood

/// Pins the R66 masked-light physics at the pass and mask-builder level with
/// synthetic scenes and rasters: the rim band brightens only on the lit side
/// and refuses without metered lights; skin protection moves masked pixels
/// toward gentle while outside pixels stay byte-identical; the sky grade
/// touches only the sky mask and refuses under coverage; and — the parity
/// guard — every recipe with the new fields renders byte-identically when the
/// masks are structurally absent (`analyzeSubjects: false`).
final class MaskedLightTests: XCTestCase {

  /// Same working/output space as FilmEngine's production context — the
  /// kernels' thresholds are defined in sRGB-encoded values.
  private let context: CIContext = {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    return CIContext(options: [
      .workingColorSpace: sRGB,
      .outputColorSpace: sRGB,
      .useSoftwareRenderer: false,
    ])
  }()

  // MARK: helpers

  private func render(_ image: CIImage) -> [UInt8]? {
    let extent = image.extent.integral
    guard extent.width > 0, extent.height > 0,
          let cg = context.createCGImage(image, from: extent) else { return nil }
    return ImageMetrics.raster(cg)?.px
  }

  /// RGBA bytes of a FRACTIONAL region (x/y/w/h in 0…1 of the extent, CI y-up).
  private func regionBytes(_ image: CIImage, region: CGRect) -> [UInt8]? {
    let e = image.extent
    let rect = CGRect(
      x: e.minX + region.minX * e.width,
      y: e.minY + region.minY * e.height,
      width: region.width * e.width,
      height: region.height * e.height
    ).integral
    guard let cg = context.createCGImage(image, from: rect) else { return nil }
    return ImageMetrics.raster(cg)?.px
  }

  /// Mean luma (0–255) inside a fractional region.
  private func meanLuma(_ image: CIImage, region: CGRect) -> Double {
    guard let px = regionBytes(image, region: region) else { return -1 }
    var sum = 0.0
    for i in stride(from: 0, to: px.count, by: 4) {
      sum += Double(px[i]) * 0.299 + Double(px[i + 1]) * 0.587 + Double(px[i + 2]) * 0.114
    }
    return sum / Double(max(px.count / 4, 1))
  }

  private func meanColor(_ image: CIImage, region: CGRect) -> (r: Double, g: Double, b: Double) {
    guard let px = regionBytes(image, region: region) else { return (-1, -1, -1) }
    var sr = 0.0, sg = 0.0, sb = 0.0
    for i in stride(from: 0, to: px.count, by: 4) {
      sr += Double(px[i]); sg += Double(px[i + 1]); sb += Double(px[i + 2])
    }
    let n = Double(max(px.count / 4, 1))
    return (sr / n, sg / n, sb / n)
  }

  private func scene(
    key: Double,
    lights: [LightSource] = [],
    auxLights: [LightSource] = []
  ) -> SceneProfile {
    SceneProfile(
      analyzed: true, key: key, p01: 0.02, p50: key, p99: 0.9,
      illum: [1, 1, 1], sat: 0.35, lights: lights, auxLights: auxLights, faceLum: nil,
      meanLuminance: key, medianLuminance: key, shadowFraction: 0.2,
      highlightFraction: 0.05, dynamicRange: 0.6, averageRed: 0.5,
      averageGreen: 0.5, averageBlue: 0.5, saturation: 0.3, warmth: 0,
      isLowKey: key < 0.2, isHighKey: false, isBacklit: false
    )
  }

  private func canvas(_ draw: (CGContext, CGSize) -> Void, side: CGFloat = 96) -> CIImage {
    let size = CGSize(width: side, height: side)
    // scale 1: the simulator's 3× screen scale would silently triple the pixel
    // extent and break every geometric expectation in these tests
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let ui = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      draw(ctx.cgContext, size)
    }
    return CIImage(image: ui)!
  }

  /// Single-channel mask CIImage from top-down row-major bytes — the same
  /// materialization `FilmEngine.read` uses for the stored masks.
  private func maskImage(_ bytes: [UInt8], width: Int, height: Int) -> CIImage {
    CIImage(
      bitmapData: Data(bytes),
      bytesPerRow: width,
      size: CGSize(width: width, height: height),
      format: .L8,
      colorSpace: nil
    )
  }

  private func analysisRaster(
    width: Int,
    height: Int,
    person: [Float]? = nil,
    color: (Int, Int) -> (UInt8, UInt8, UInt8)
  ) -> FilmEngine.AnalysisRaster {
    var px = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let (r, g, b) = color(x, y)
        let i = (y * width + x) * 4
        px[i] = r
        px[i + 1] = g
        px[i + 2] = b
        px[i + 3] = 255
      }
    }
    return FilmEngine.AnalysisRaster(width: width, height: height, pixels: px, person: person)
  }

  private func withoutMaskedLight(_ r: CameraRecipe) -> CameraRecipe {
    CameraRecipe(
      id: r.id, engineClass: r.engineClass, lutName: r.lutName,
      postLUTExposure: r.postLUTExposure, postLUTSaturation: r.postLUTSaturation,
      postLUTContrast: r.postLUTContrast, postLUTMatrix: r.postLUTMatrix,
      referenceSpatial: r.referenceSpatial, exposureBias: r.exposureBias,
      adaptiveExposure: r.adaptiveExposure, warmth: r.warmth, saturation: r.saturation,
      contrast: r.contrast, shadowLift: r.shadowLift,
      highlightCompression: r.highlightCompression, vignette: r.vignette,
      bloom: r.bloom, grain: r.grain, grainSize: r.grainSize,
      monochrome: r.monochrome, protectsFaces: r.protectsFaces,
      preservesWarmCast: r.preservesWarmCast, decisionVocabulary: r.decisionVocabulary,
      flashPhysics: r.flashPhysics, sourceBloom: r.sourceBloom, keyShadow: r.keyShadow,
      gainDrivenGrain: r.gainDrivenGrain, nightReciprocity: r.nightReciprocity,
      ccdClip: r.ccdClip, highlightSmear: r.highlightSmear,
      highlightSmearDarkOnly: r.highlightSmearDarkOnly,
      rimLight: 0, skinProtect: 0, skyResponse: 0,
      flashHighlightHeadroom: r.flashHighlightHeadroom,
      daylightHighlightGuard: r.daylightHighlightGuard
    )
  }

  // MARK: recipe wiring — the ratified per-stock table, exactly

  func testRecipeFieldsMatchTheRatifiedTable() {
    let expected: [String: (rim: Double, skin: Double, sky: Double)] = [
      "disposable": (0, 0.25, 0),
      "iphone-flash": (0, 0.40, 0),
      "camcorder-90s": (0, 0, 0),
      "leica-street": (0.20, 0.30, 0.15),
      "gq-editorial": (0.35, 0.70, 0),
      "a24-still": (0, 0, 0),
      "film-noir": (0.60, 0, 0.50),
      "y2k-digicam": (0, 0, 0),
      "polaroid": (0.15, 0.35, 0.25),
      "super-8": (0.40, 0.20, 0.20),
      "lomo": (0.20, 0, 0.50),
      "kodachrome": (0.15, 0.50, 0.70),
      "security-cam": (0, 0, 0),
      "point-shoot": (0, 0.30, 0.20),
      "pastel-cinema": (0.20, 0.50, 0.50),
      "tokyo-neon": (0.80, 0.25, 0),
      "photobooth": (0, 0.25, 0),
      "tintype": (0.30, 0, 0.60),
    ]
    XCTAssertEqual(expected.count, CameraRecipe.all.count)
    for recipe in CameraRecipe.all {
      guard let want = expected[recipe.id] else {
        XCTFail("no ratified values for \(recipe.id)")
        continue
      }
      XCTAssertEqual(recipe.rimLight, want.rim, "\(recipe.id) rimLight")
      XCTAssertEqual(recipe.skinProtect, want.skin, "\(recipe.id) skinProtect")
      XCTAssertEqual(recipe.skyResponse, want.sky, "\(recipe.id) skyResponse")
    }
  }

  // MARK: pass 1 — rim halation

  func testRimBrightensOnlyTheLitSideAndRefusesWithoutLights() {
    // left half bright (the light's world), right half dark; a dark disc
    // subject dead-center. The rim must appear on the subject's LEFT edge
    // (facing the light, bright behind it) and not on the right.
    let img = canvas({ g, size in
      g.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
      g.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
      g.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
      g.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
      g.setFillColor(UIColor(white: 0.15, alpha: 1).cgColor)
      g.fillEllipse(in: CGRect(x: 88, y: 88, width: 80, height: 80))
    }, side: 256)
    // matte at half resolution: disc center (64, 64), radius 20 — mirrors the
    // stored-thumb-upscaled-at-use architecture
    let tw = 128, th = 128
    var matteBytes = [UInt8](repeating: 0, count: tw * th)
    for y in 0..<th {
      for x in 0..<tw {
        let dx = Double(x) - 64, dy = Double(y) - 64
        if dx * dx + dy * dy <= 20 * 20 { matteBytes[y * tw + x] = 255 }
      }
    }
    let subject = SubjectAnalysis(
      faces: [], personMask: nil,
      subjectMatte: maskImage(matteBytes, width: tw, height: th)
    )
    let keyLeft = LightSource(x: 0.08, y: 0.5, r: 0.04, intensity: 1, tint: [1, 0.8, 0.6])
    let lit = scene(key: 0.12, lights: [keyLeft])
    let recipe = CameraRecipe.recipe(for: "gq-editorial")
    let out = FilmEngine.shared.applyRimHalation(
      img, scene: lit, subject: subject, recipe: recipe, amount: 1.0
    )
    // disc edge at image x = 88 (left) / 168 (right); band regions hug them
    let leftBand = CGRect(x: 0.312, y: 0.42, width: 0.05, height: 0.16)
    let rightBand = CGRect(x: 0.638, y: 0.42, width: 0.05, height: 0.16)
    let leftGain = meanLuma(out, region: leftBand) - meanLuma(img, region: leftBand)
    let rightGain = meanLuma(out, region: rightBand) - meanLuma(img, region: rightBand)
    XCTAssertGreaterThan(leftGain, 3, "the lit-side band must glow")
    XCTAssertGreaterThan(leftGain, rightGain + 2, "the rim must stay on the lit side")

    // no metered lights → structural no-op, byte-identical
    let unlit = FilmEngine.shared.applyRimHalation(
      img, scene: scene(key: 0.12), subject: subject, recipe: recipe, amount: 1.0
    )
    XCTAssertEqual(render(unlit), render(img), "no lights → bitwise no-op")

    // no subject matte → structural no-op
    let noMatte = FilmEngine.shared.applyRimHalation(
      img, scene: lit,
      subject: SubjectAnalysis(faces: [], personMask: nil),
      recipe: recipe, amount: 1.0
    )
    XCTAssertEqual(render(noMatte), render(img), "no matte → bitwise no-op")
  }

  // MARK: pass 2 — skin-protected curve

  func testSkinProtectionEasesInsideTheMaskOnly() {
    // dark-midtone field: the gentle counter-grade must lift it toward the
    // skin pivot INSIDE the mask and leave the outside bytes untouched
    let img = canvas({ g, size in
      g.setFillColor(UIColor(white: 0.25, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
    }, side: 128)
    let tw = 64, th = 64
    var maskBytes = [UInt8](repeating: 0, count: tw * th)
    for y in 0..<28 { // top rows of the thumb = top of the photograph
      for x in 0..<tw { maskBytes[y * tw + x] = 255 }
    }
    let subject = SubjectAnalysis(
      faces: [], personMask: nil,
      skinMask: maskImage(maskBytes, width: tw, height: th)
    )
    let out = FilmEngine.shared.applySkinProtection(
      img, subject: subject, recipe: .recipe(for: "kodachrome"), amount: 1.0
    )
    // mask rows 0..27 of 64 → the top of the photo → CI y-up region 0.56…1.0
    let inside = CGRect(x: 0.1, y: 0.65, width: 0.8, height: 0.30)
    let outside = CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.35)
    let insideGain = meanLuma(out, region: inside) - meanLuma(img, region: inside)
    XCTAssertGreaterThan(insideGain, 6, "dark skin midtones must ease toward the gentle curve")
    XCTAssertEqual(
      regionBytes(out, region: outside), regionBytes(img, region: outside),
      "outside the skin mask must stay byte-identical"
    )
  }

  // MARK: pass 3 — sky-scoped color

  func testSkyResponseTouchesOnlyTheSkyAndRefusesWithoutAMask() {
    let img = canvas({ g, size in
      g.setFillColor(UIColor(red: 0.35, green: 0.5, blue: 0.75, alpha: 1).cgColor)
      g.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)) // sky on top
      g.setFillColor(UIColor(white: 0.4, alpha: 1).cgColor)
      g.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2))
    }, side: 128)
    let tw = 64, th = 64
    var maskBytes = [UInt8](repeating: 0, count: tw * th)
    for y in 0..<32 {
      for x in 0..<tw { maskBytes[y * tw + x] = 255 }
    }
    let masked = SubjectAnalysis(
      faces: [], personMask: nil,
      skyMask: maskImage(maskBytes, width: tw, height: th)
    )
    let day = scene(key: 0.45)
    let recipe = CameraRecipe.recipe(for: "kodachrome")
    let out = FilmEngine.shared.applySkyResponse(
      img, scene: day, subject: masked, recipe: recipe, amount: 1.0
    )
    let sky = CGRect(x: 0.1, y: 0.62, width: 0.8, height: 0.30)
    let ground = CGRect(x: 0.1, y: 0.05, width: 0.8, height: 0.38)
    let before = meanColor(img, region: sky)
    let after = meanColor(out, region: sky)
    XCTAssertLessThan(after.r, before.r - 5, "kodachrome must pull the sky toward cyan-blue")
    XCTAssertEqual(
      regionBytes(out, region: ground), regionBytes(img, region: ground),
      "below the sky mask must stay byte-identical"
    )

    // no sky mask (coverage refused at read time) → bitwise no-op
    let refused = FilmEngine.shared.applySkyResponse(
      img, scene: day,
      subject: SubjectAnalysis(faces: [], personMask: nil),
      recipe: recipe, amount: 1.0
    )
    XCTAssertEqual(render(refused), render(img), "no mask → bitwise no-op")

    // deepen skips near-black scenes (ratified: skip below key ≈ 0.1)
    let night = FilmEngine.shared.applySkyResponse(
      img, scene: scene(key: 0.05), subject: masked, recipe: recipe, amount: 1.0
    )
    XCTAssertEqual(render(night), render(img), "deepen must not darken a night sky further")
  }

  func testNoirSkyFilterDarkenIsLuminanceOnly() {
    // neutral gray input: the noir sky must fall darker while STAYING neutral
    // (uniform gain — the LUT's split-tone would ride on top unharmed)
    let img = canvas({ g, size in
      g.setFillColor(UIColor(white: 0.6, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
    }, side: 128)
    let tw = 64, th = 64
    var maskBytes = [UInt8](repeating: 0, count: tw * th)
    for y in 0..<32 {
      for x in 0..<tw { maskBytes[y * tw + x] = 255 }
    }
    let masked = SubjectAnalysis(
      faces: [], personMask: nil,
      skyMask: maskImage(maskBytes, width: tw, height: th)
    )
    let out = FilmEngine.shared.applySkyResponse(
      img, scene: scene(key: 0.4), subject: masked,
      recipe: .recipe(for: "film-noir"), amount: 1.0
    )
    let sky = CGRect(x: 0.1, y: 0.62, width: 0.8, height: 0.30)
    XCTAssertLessThan(
      meanLuma(out, region: sky), meanLuma(img, region: sky) - 10,
      "the red-filter sky must fall dark"
    )
    let color = meanColor(out, region: sky)
    XCTAssertLessThan(abs(color.r - color.g), 2, "luminance-only: no hue introduced")
    XCTAssertLessThan(abs(color.g - color.b), 2)
  }

  // MARK: mask builders (pure CPU, driven with synthetic rasters)

  func testSkyMaskBuilderAcceptsRealSkyAndRefusesImpostors() throws {
    let w = 120, h = 90
    // a) chromatic blue sky filling the top 40% → accepted
    let skyScene = analysisRaster(width: w, height: h) { _, y in
      y < 36 ? (77, 115, 191) : (102, 102, 102)
    }
    let mask = try XCTUnwrap(
      FilmEngine.buildSkyMask(skyScene, subjectMatte: nil),
      "a real blue sky must produce a mask"
    )
    var topSum = 0.0, bottomSum = 0.0
    for x in 0..<w {
      topSum += Double(mask[10 * w + x])
      bottomSum += Double(mask[70 * w + x])
    }
    XCTAssertGreaterThan(topSum / Double(w), 128, "sky rows must be masked")
    XCTAssertLessThan(bottomSum / Double(w), 8, "ground rows must stay clear")

    // b) gray indoor scene → nil (the brunch guard)
    let indoor = analysisRaster(width: w, height: h) { _, _ in (120, 118, 116) }
    XCTAssertNil(FilmEngine.buildSkyMask(indoor, subjectMatte: nil))

    // c) a sliver of blue touching the top (~1.2% coverage) → coverage refusal
    let sliver = analysisRaster(width: w, height: h) { x, y in
      (y < 6 && x < 21) ? (77, 115, 191) : (102, 102, 102)
    }
    XCTAssertNil(FilmEngine.buildSkyMask(sliver, subjectMatte: nil), "under-coverage must refuse")

    // d) a blue band NOT touching the top 12% → top-touch cleanup drops it
    let floating = analysisRaster(width: w, height: h) { _, y in
      (y >= 20 && y < 40) ? (77, 115, 191) : (102, 102, 102)
    }
    XCTAssertNil(FilmEngine.buildSkyMask(floating, subjectMatte: nil), "a floating blue band is not sky")
  }

  func testSkinMaskBuilderIntersectsPersonAndSkinChroma() throws {
    let w = 100, h = 100
    var person = [Float](repeating: 0, count: w * h)
    for y in 0..<h {
      for x in 0..<50 { person[y * w + x] = 1 } // person = left half
    }
    // skin chroma inside the person, the SAME chroma outside it, and a
    // non-skin (blue) patch inside it
    let raster = analysisRaster(width: w, height: h, person: person) { x, y in
      if x >= 10, x < 40, y >= 30, y < 70 { return (205, 155, 130) } // skin ∩ person
      if x >= 60, x < 90, y >= 30, y < 70 { return (205, 155, 130) } // skin outside person
      if x >= 10, x < 40, y >= 75, y < 95 { return (50, 80, 200) }   // blue ∩ person
      return (60, 60, 60)
    }
    let matte = try XCTUnwrap(FilmEngine.buildSubjectMatte(raster))
    let mask = try XCTUnwrap(FilmEngine.buildSkinMask(raster, subjectMatte: matte))
    func mean(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int) -> Double {
      var sum = 0.0
      var n = 0.0
      for y in y0..<y1 {
        for x in x0..<x1 {
          sum += Double(mask[y * w + x])
          n += 1
        }
      }
      return sum / max(n, 1)
    }
    XCTAssertGreaterThan(mean(15, 35, 40, 60), 100, "skin inside the person must be protected")
    XCTAssertLessThan(mean(65, 85, 40, 60), 8, "skin chroma OUTSIDE the person must not be")
    XCTAssertLessThan(mean(15, 35, 80, 92), 8, "non-skin chroma inside the person must not be")
    // no person matte → no skin mask (both structurally off)
    XCTAssertNil(FilmEngine.buildSkinMask(raster, subjectMatte: nil))
  }

  /// The scene-conditioned luma floor (bug fix): a fixed 0.28 floor dropped
  /// dark skin in dim scenes. Dark skin at RGB (70, 42, 30) sits in-box on
  /// chroma (Cb ≈ 117, Cr ≈ 143) but at luma ≈ 0.19 — under v3's floor.
  func testSkinMaskLumaFloorRelaxesInDimScenes() throws {
    let w = 100, h = 100
    let fullMatte = [UInt8](repeating: 255, count: w * h)
    // dark skin block on a dark background: raster mean luma ≈ 0.16, so the
    // floor relaxes to ≈ 0.17 and the luma-0.19 skin must enter the mask
    let dim = analysisRaster(width: w, height: h) { x, y in
      (x >= 30 && x < 70 && y >= 30 && y < 70) ? (70, 42, 30) : (40, 40, 40)
    }
    let mask = try XCTUnwrap(
      FilmEngine.buildSkinMask(dim, subjectMatte: fullMatte),
      "dim scene: dark skin must produce a mask (was nil under the fixed floor)"
    )
    var sum = 0.0
    var count = 0.0
    for y in 40..<60 {
      for x in 40..<60 {
        sum += Double(mask[y * w + x])
        count += 1
      }
    }
    XCTAssertGreaterThan(
      sum / count, 100,
      "the dark-skin block must be substantially masked in a dim scene"
    )
  }

  func testSkinMaskLumaFloorHoldsInBrightScenes() {
    let w = 100, h = 100
    let fullMatte = [UInt8](repeating: 255, count: w * h)
    // the SAME luma-0.19 skin block, but on a bright background (raster mean
    // luma ≈ 0.69): the floor stays at the ratified 0.28 and those pixels
    // must NOT enter the mask — byte-identical to v3, which also refused
    let bright = analysisRaster(width: w, height: h) { x, y in
      (x >= 30 && x < 70 && y >= 30 && y < 70) ? (70, 42, 30) : (200, 200, 200)
    }
    XCTAssertNil(
      FilmEngine.buildSkinMask(bright, subjectMatte: fullMatte),
      "bright scene: the floor holds at 0.28, so luma-0.19 pixels stay outside the mask"
    )
  }

  func testSkinMaskConditionedFloorIsDeterministic() throws {
    let w = 100, h = 100
    let fullMatte = [UInt8](repeating: 255, count: w * h)
    let dim = analysisRaster(width: w, height: h) { x, y in
      (x >= 30 && x < 70 && y >= 30 && y < 70) ? (70, 42, 30) : (40, 40, 40)
    }
    let first = try XCTUnwrap(FilmEngine.buildSkinMask(dim, subjectMatte: fullMatte))
    let second = try XCTUnwrap(FilmEngine.buildSkinMask(dim, subjectMatte: fullMatte))
    XCTAssertEqual(first, second, "same raster in → same mask bytes out")
  }

  func testSubjectMatteCleanupFillsHolesAndDropsSpecks() throws {
    let w = 100, h = 100
    var person = [Float](repeating: 0, count: w * h)
    for y in 20..<70 {
      for x in 20..<70 { person[y * w + x] = 1 }
    }
    for y in 40..<50 { // a hole in the torso (matte failure)
      for x in 40..<50 { person[y * w + x] = 0 }
    }
    for y in 88..<91 { // a floating speck (matte spur)
      for x in 88..<91 { person[y * w + x] = 1 }
    }
    let raster = analysisRaster(width: w, height: h, person: person) { _, _ in (100, 100, 100) }
    let matte = try XCTUnwrap(FilmEngine.buildSubjectMatte(raster))
    XCTAssertEqual(matte[45 * w + 45], 255, "interior holes must be filled (no interior halos)")
    XCTAssertEqual(matte[89 * w + 89], 0, "floating specks must be dropped (no floating rim blobs)")
    XCTAssertEqual(matte[25 * w + 25], 255, "the body itself survives")
    // no person → no matte
    let empty = analysisRaster(width: w, height: h) { _, _ in (100, 100, 100) }
    XCTAssertNil(FilmEngine.buildSubjectMatte(empty))
  }

  // MARK: the parity guard — masks absent ⇒ the new fields change NOTHING

  func testEveryRecipeIsByteIdenticalWithoutMasks() throws {
    // `analyzeSubjects: false` is exactly how the MAE golden suite renders:
    // masks nil → all three passes structurally off → a recipe with the new
    // fields must render byte-identically to the same recipe with them zeroed.
    let source = UIGraphicsImageRenderer(
      size: CGSize(width: 96, height: 96),
      format: {
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return f
      }()
    ).image { ctx in
      UIColor(red: 0.35, green: 0.5, blue: 0.75, alpha: 1).setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 96, height: 48))
      UIColor(red: 0.5, green: 0.35, blue: 0.25, alpha: 1).setFill()
      ctx.fill(CGRect(x: 0, y: 48, width: 96, height: 48))
      UIColor.white.setFill()
      ctx.fill(CGRect(x: 8, y: 8, width: 10, height: 10))
    }
    let engine = FilmEngine()
    for recipe in CameraRecipe.all {
      let with = try engine.develop(source, with: recipe, seed: 5, analyzeSubjects: false).image
      let without = try engine.develop(
        source, with: withoutMaskedLight(recipe), seed: 5, analyzeSubjects: false
      ).image
      XCTAssertEqual(
        with.pngData(), without.pngData(),
        "\(recipe.id): masked-light fields must be structurally OFF without masks"
      )
    }
  }

  // MARK: determinism — the new passes included, from one reading

  func testDevelopFromReadingWithMasksIsDeterministic() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let photo = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 96), format: format)
      .image { ctx in
        UIColor(red: 0.3, green: 0.42, blue: 0.68, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 40))
        UIColor(white: 0.25, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 40, width: 128, height: 56))
        UIColor(white: 0.9, alpha: 1).setFill()
        ctx.cgContext.fillEllipse(in: CGRect(x: 8, y: 40, width: 18, height: 18))
      }
    // a manual reading with ALL masks present, so rim + skin + sky code paths
    // all run inside the develop
    let tw = 64, th = 48
    var matte = [UInt8](repeating: 0, count: tw * th)
    var skin = [UInt8](repeating: 0, count: tw * th)
    var sky = [UInt8](repeating: 0, count: tw * th)
    for y in 0..<th {
      for x in 0..<tw {
        let dx = Double(x) - 32, dy = Double(y) - 30
        if dx * dx + dy * dy <= 100 { matte[y * tw + x] = 255 }
        if dx * dx + dy * dy <= 36 { skin[y * tw + x] = 255 }
        if y < 16 { sky[y * tw + x] = 255 }
      }
    }
    let light = LightSource(x: 0.1, y: 0.4, r: 0.05, intensity: 1, tint: [1, 0.6, 0.9])
    let reading = SceneReading(
      scene: scene(key: 0.2, lights: [light]),
      subject: SubjectAnalysis(
        faces: [], personMask: nil,
        subjectMatte: maskImage(matte, width: tw, height: th),
        skinMask: maskImage(skin, width: tw, height: th),
        skyMask: maskImage(sky, width: tw, height: th)
      )
    )
    let engine = FilmEngine()
    for stockID in ["kodachrome", "tokyo-neon", "gq-editorial", "film-noir"] {
      let recipe = CameraRecipe.recipe(for: stockID)
      let first = try engine.develop(photo, with: recipe, seed: 7, reading: reading).image
      let second = try engine.develop(photo, with: recipe, seed: 7, reading: reading).image
      XCTAssertEqual(
        first.pngData(), second.pngData(),
        "\(stockID): the same reading must always render the same bytes, new passes included"
      )
    }
  }
}
