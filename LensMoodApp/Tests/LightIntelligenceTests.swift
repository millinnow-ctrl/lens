import CoreImage
import UIKit
import XCTest
@testable import LensMood

/// Pins the R61 light-intelligence physics at the pass level with synthetic
/// scenes: speculars prefer desaturated highlights, flash falloff sinks the
/// far field, source bloom carries the source's own hue and REFUSES scenes
/// with no emissive sources, noir shading is directional, and video gain
/// follows darkness. No golden fixtures — every assertion is self-contained.
final class LightIntelligenceTests: XCTestCase {

  private let context = CIContext(options: [.useSoftwareRenderer: false])

  // MARK: helpers

  private func render(_ image: CIImage) -> [UInt8]? {
    let extent = image.extent.integral
    guard extent.width > 0, extent.height > 0,
          let cg = context.createCGImage(image, from: extent) else { return nil }
    return ImageMetrics.raster(cg)?.px
  }

  private func meanLuma(_ image: CIImage, in rect: CGRect) -> Double {
    guard let cg = context.createCGImage(image, from: rect),
          let raster = ImageMetrics.raster(cg) else { return -1 }
    var sum = 0.0
    for i in stride(from: 0, to: raster.px.count, by: 4) {
      sum += Double(raster.px[i]) * 0.299 + Double(raster.px[i + 1]) * 0.587 + Double(raster.px[i + 2]) * 0.114
    }
    return sum / Double(max(raster.count, 1))
  }

  private func scene(
    key: Double,
    p50: Double = 0.4,
    p99: Double = 0.9,
    lights: [LightSource] = []
  ) -> SceneProfile {
    SceneProfile(
      analyzed: true, key: key, p01: 0.02, p50: p50, p99: p99,
      illum: [1, 1, 1], sat: 0.35, lights: lights, faceLum: nil,
      meanLuminance: key, medianLuminance: p50, shadowFraction: 0.2,
      highlightFraction: 0.05, dynamicRange: 0.6, averageRed: 0.5,
      averageGreen: 0.5, averageBlue: 0.5, saturation: 0.3, warmth: 0,
      isLowKey: key < 0.2, isHighKey: false, isBacklit: false
    )
  }

  private func canvas(_ draw: (CGContext, CGSize) -> Void, side: CGFloat = 96) -> CIImage {
    let size = CGSize(width: side, height: side)
    let ui = UIGraphicsImageRenderer(size: size).image { ctx in
      draw(ctx.cgContext, size)
    }
    return CIImage(image: ui)!
  }

  // MARK: video gain

  func testGainGrainFactorFollowsDarkness() {
    let night = FilmEngine.gainGrainFactor(key: 0.05)
    let dusk = FilmEngine.gainGrainFactor(key: 0.25)
    let day = FilmEngine.gainGrainFactor(key: 0.55)
    XCTAssertGreaterThan(night, dusk)
    XCTAssertGreaterThan(dusk, day)
    XCTAssertEqual(day, 0.4, accuracy: 0.0001, "daylight video is near-clean")
    XCTAssertGreaterThan(night, 1.4, "night gain noise explodes")
  }

  // MARK: flash speculars

  func testSpecularsPreferDesaturatedHighlights() {
    // gray field with two bright patches: a desaturated one (reads as glass/
    // screen/metal — must catch the flash) vs a fully saturated red (colored
    // fabric — must not)
    let img = canvas { g, size in
      g.setFillColor(UIColor(white: 0.35, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
      g.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)       // reflective surface
      g.fill(CGRect(x: 8, y: 40, width: 24, height: 24))
      g.setFillColor(UIColor(red: 1.0, green: 0.12, blue: 0.12, alpha: 1).cgColor) // saturated red
      g.fill(CGRect(x: 64, y: 40, width: 24, height: 24))
    }
    let out = FilmEngine.shared.applyFlashPhysics(
      img,
      scene: scene(key: 0.3, p50: 0.35, p99: 0.85),
      subject: SubjectAnalysis(faces: [], personMask: nil), // no mask → falloff skipped, speculars isolated
      amount: 1.0
    )
    // UIKit y-down → CI y-up: patch at y:40..64 of 96 maps to CI y 32..56
    let white = CGRect(x: 8, y: 32, width: 24, height: 24)
    let red = CGRect(x: 64, y: 32, width: 24, height: 24)
    let whiteGain = meanLuma(out, in: white) - meanLuma(img, in: white)
    let redGain = meanLuma(out, in: red) - meanLuma(img, in: red)
    XCTAssertGreaterThan(whiteGain, redGain + 2,
                         "desaturated highlight must catch the flash harder than a saturated one")
  }

  // MARK: source bloom

  func testSourceBloomCarriesSourceHueAndSinksAmbient() throws {
    let img = canvas { g, size in
      g.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
    }
    let magenta = LightSource(x: 0.25, y: 0.25, r: 0.05, intensity: 0.9, tint: [1.0, 0.25, 0.9])
    let out = FilmEngine.shared.applySourceBloom(
      img, scene: scene(key: 0.08, lights: [magenta]), baseBloom: 0.18, amount: 1.0
    )
    let control = FilmEngine.shared.applyBloom(img, amount: 0.18)
    // near the source (light y is top-down → CI y-up): (0.25, 0.75) of 96
    let near = CGRect(x: 18, y: 66, width: 12, height: 12)
    let far = CGRect(x: 74, y: 8, width: 12, height: 12)
    let nearDelta = meanLuma(out, in: near) - meanLuma(control, in: near)
    let farDelta = abs(meanLuma(out, in: far) - meanLuma(control, in: far))
    XCTAssertGreaterThan(nearDelta, 4, "glow must appear around the source")
    XCTAssertGreaterThan(nearDelta, farDelta * 2, "glow must be local to the source, not a wash")

    // the glow carries the source's hue (red+blue over green)
    guard let cg = context.createCGImage(out, from: near),
          let raster = ImageMetrics.raster(cg),
          let mean = ImageMetrics.meanColor(raster, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    else { return XCTFail("raster failed") }
    XCTAssertGreaterThan(mean.r, mean.g, "magenta source must glow magenta, not white")
    XCTAssertGreaterThan(mean.b, mean.g)
  }

  func testSourceBloomRefusesNonEmissiveScenes() {
    // bright overcast day, one WHITE sky patch detected — must fall back to
    // plain bloom (no colored glow painted onto daylight)
    let img = canvas { g, size in
      g.setFillColor(UIColor(white: 0.6, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
    }
    let skyPatch = LightSource(x: 0.5, y: 0.2, r: 0.1, intensity: 0.6, tint: [1, 1, 1])
    let daylight = scene(key: 0.5, lights: [skyPatch])
    XCTAssertTrue(FilmEngine.shared.emissiveLights(in: daylight).isEmpty)
    let out = FilmEngine.shared.applySourceBloom(img, scene: daylight, baseBloom: 0.18, amount: 1.0)
    let control = FilmEngine.shared.applyBloom(img, amount: 0.18)
    XCTAssertEqual(render(out), render(control), "refusal must be byte-identical to plain bloom")
  }

  func testWhiteLightCountsAsEmissiveInTheDark() {
    let white = LightSource(x: 0.5, y: 0.5, r: 0.05, intensity: 0.8, tint: [1, 1, 1])
    XCTAssertFalse(FilmEngine.shared.emissiveLights(in: scene(key: 0.1, lights: [white])).isEmpty,
                   "a hot source in a dark scene is emissive even when white")
  }

  // MARK: noir key shadow

  func testKeyShadowIsDirectional() {
    // uniform mid-gray: any left/right asymmetry after the pass proves direction
    let img = canvas { g, size in
      g.setFillColor(UIColor(white: 0.5, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
    }
    let keyLeft = LightSource(x: 0.08, y: 0.5, r: 0.04, intensity: 1, tint: [1, 1, 0.9])
    let out = FilmEngine.shared.applyKeyShadow(
      img, scene: scene(key: 0.2, lights: [keyLeft]),
      subject: SubjectAnalysis(faces: [], personMask: nil), amount: 0.7
    )
    let left = meanLuma(out, in: CGRect(x: 4, y: 32, width: 20, height: 32))
    let right = meanLuma(out, in: CGRect(x: 72, y: 32, width: 20, height: 32))
    XCTAssertGreaterThan(left, right + 6, "the side away from the key light must fall darker")
  }

  func testKeyShadowSkipsWithoutALight() {
    let img = canvas { g, size in
      g.setFillColor(UIColor(white: 0.5, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
    }
    let out = FilmEngine.shared.applyKeyShadow(
      img, scene: scene(key: 0.2, lights: []),
      subject: SubjectAnalysis(faces: [], personMask: nil), amount: 0.7
    )
    XCTAssertEqual(render(out), render(img), "no key light → honest no-op")
  }

  // MARK: recipe wiring

  func testRecipeGatesAreSetOnTheIntendedStocks() {
    XCTAssertEqual(CameraRecipe.recipe(for: "iphone-flash").flashPhysics, 1.0)
    XCTAssertGreaterThan(CameraRecipe.recipe(for: "photobooth").flashPhysics, 0)
    XCTAssertGreaterThan(CameraRecipe.recipe(for: "disposable").flashPhysics, 0)
    XCTAssertEqual(CameraRecipe.recipe(for: "tokyo-neon").sourceBloom, 1.0)
    XCTAssertEqual(CameraRecipe.recipe(for: "film-noir").keyShadow, 0.7)
    XCTAssertTrue(CameraRecipe.recipe(for: "security-cam").gainDrivenGrain)
    XCTAssertTrue(CameraRecipe.recipe(for: "camcorder-90s").gainDrivenGrain)
    // untouched stocks stay untouched
    for id in ["leica-street", "kodachrome", "polaroid", "gq-editorial", "a24-still", "pastel-cinema"] {
      let recipe = CameraRecipe.recipe(for: id)
      XCTAssertEqual(recipe.flashPhysics, 0, id)
      XCTAssertEqual(recipe.sourceBloom, 0, id)
      XCTAssertEqual(recipe.keyShadow, 0, id)
      XCTAssertFalse(recipe.gainDrivenGrain, id)
    }
  }

  func testDeterminismOfNewPasses() throws {
    let source = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { ctx in
      UIColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1).setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
      UIColor(red: 1, green: 0.4, blue: 0.9, alpha: 1).setFill()
      ctx.fill(CGRect(x: 10, y: 10, width: 16, height: 16))
    }
    for id in ["iphone-flash", "tokyo-neon", "film-noir", "security-cam"] {
      let recipe = CameraRecipe.recipe(for: id)
      let a = try FilmEngine().develop(source, with: recipe, seed: 7, analyzeSubjects: false).image
      let b = try FilmEngine().develop(source, with: recipe, seed: 7, analyzeSubjects: false).image
      XCTAssertEqual(a.pngData(), b.pngData(), "\(id) must stay deterministic")
    }
  }
}
