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

  /// Same working/output space as FilmEngine's production context — the kernels'
  /// luma thresholds are defined in sRGB-encoded values, so the test context
  /// must match (a default linear-space context would mute every pass).
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

  /// Mean luma (0–255) inside a FRACTIONAL region of the image (x/y/w/h in
  /// 0…1 of the extent, CI y-up) — robust to any renderer pixel scale.
  private func meanLuma(_ image: CIImage, region: CGRect) -> Double {
    let e = image.extent
    let rect = CGRect(
      x: e.minX + region.minX * e.width,
      y: e.minY + region.minY * e.height,
      width: region.width * e.width,
      height: region.height * e.height
    ).integral
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
    lights: [LightSource] = [],
    auxLights: [LightSource] = []
  ) -> SceneProfile {
    SceneProfile(
      analyzed: true, key: key, p01: 0.02, p50: p50, p99: p99,
      illum: [1, 1, 1], sat: 0.35, lights: lights, auxLights: auxLights, faceLum: nil,
      meanLuminance: key, medianLuminance: p50, shadowFraction: 0.2,
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
    // fractional regions (CI y-up): UIKit patch y 40..64 of 96 → y 0.35..0.56
    let white = CGRect(x: 0.10, y: 0.36, width: 0.22, height: 0.20)
    let red = CGRect(x: 0.68, y: 0.36, width: 0.22, height: 0.20)
    let whiteGain = meanLuma(out, region: white) - meanLuma(img, region: white)
    let redGain = meanLuma(out, region: red) - meanLuma(img, region: red)
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
    // near the source (light y is top-down → CI y-up): center (0.25, 0.75)
    let near = CGRect(x: 0.17, y: 0.67, width: 0.16, height: 0.16)
    let far = CGRect(x: 0.76, y: 0.06, width: 0.14, height: 0.14)
    let nearDelta = meanLuma(out, region: near) - meanLuma(control, region: near)
    let farDelta = abs(meanLuma(out, region: far) - meanLuma(control, region: far))
    XCTAssertGreaterThan(nearDelta, 4, "glow must appear around the source")
    XCTAssertGreaterThan(nearDelta, farDelta * 2, "glow must be local to the source, not a wash")

    // the glow carries the source's hue (red+blue over green)
    let e = out.extent
    let nearRect = CGRect(
      x: e.minX + near.minX * e.width, y: e.minY + near.minY * e.height,
      width: near.width * e.width, height: near.height * e.height
    ).integral
    guard let cg = context.createCGImage(out, from: nearRect),
          let raster = ImageMetrics.raster(cg),
          let mean = ImageMetrics.meanColor(raster, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    else { return XCTFail("raster failed") }
    XCTAssertGreaterThan(mean.r, mean.g + 2, "magenta source must glow magenta, not white")
    XCTAssertGreaterThan(mean.b, mean.g + 2)
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
    XCTAssertTrue(FilmEngine.emissiveLights(in: daylight).isEmpty)
    let out = FilmEngine.shared.applySourceBloom(img, scene: daylight, baseBloom: 0.18, amount: 1.0)
    let control = FilmEngine.shared.applyBloom(img, amount: 0.18)
    XCTAssertEqual(render(out), render(control), "refusal must be byte-identical to plain bloom")
  }

  func testWhiteLightCountsAsEmissiveInTheDark() {
    let white = LightSource(x: 0.5, y: 0.5, r: 0.05, intensity: 0.8, tint: [1, 1, 1])
    XCTAssertFalse(FilmEngine.emissiveLights(in: scene(key: 0.1, lights: [white])).isEmpty,
                   "a hot source in a dark scene is emissive even when white")
  }

  func testNeonDoesNotExistUnderTheSun() {
    // even a strongly colored source is refused in a bright scene — the glow
    // pass is a night/dusk behavior, never a daylight paint (golden regression:
    // the sun's warm annulus slipped a tint-only gate at MAE 39.3)
    let magenta = LightSource(x: 0.5, y: 0.3, r: 0.06, intensity: 1.0, tint: [1.0, 0.2, 0.9])
    XCTAssertTrue(FilmEngine.emissiveLights(in: scene(key: 0.42, lights: [magenta])).isEmpty)
    // dusk band: strong color passes, weak color does not
    let pale = LightSource(x: 0.5, y: 0.3, r: 0.06, intensity: 1.0, tint: [1.0, 0.9, 0.82])
    XCTAssertTrue(FilmEngine.emissiveLights(in: scene(key: 0.32, lights: [pale])).isEmpty)
    XCTAssertFalse(FilmEngine.emissiveLights(in: scene(key: 0.32, lights: [magenta])).isEmpty)
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
    let left = meanLuma(out, region: CGRect(x: 0.04, y: 0.33, width: 0.20, height: 0.34))
    let right = meanLuma(out, region: CGRect(x: 0.76, y: 0.33, width: 0.20, height: 0.34))
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

  // MARK: R63 — chroma lights, night-lift cap, aux key fallback

  func testChromaPassDetectsBlueNeonThatLumaMisses() throws {
    // pure blue emitter: peak channel 1.0 but luma ≈ 0.11 — invisible to the
    // reference meter's specular knee, found by the R63 chroma pass.
    // (Found on a real photo: a blazing blue neon sign registered ZERO lights.)
    let img = canvas({ g, size in
      g.setFillColor(UIColor(white: 0.06, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
      g.setFillColor(UIColor(red: 0.1, green: 0.15, blue: 1.0, alpha: 1).cgColor)
      g.fill(CGRect(x: 30, y: 40, width: 36, height: 100))
    }, side: 256)
    let profile = try SceneAnalyzer(context: CIContext()).analyze(img)
    XCTAssertTrue(profile.lights.isEmpty, "luma pass must NOT see the blue emitter (documents the gap)")
    XCTAssertFalse(profile.auxLights.isEmpty, "chroma pass must find it")
    let light = try XCTUnwrap(profile.auxLights.first)
    XCTAssertGreaterThan(light.tint[2], light.tint[0], "tint must be blue-dominant")
    XCTAssertGreaterThan(light.tint[2], light.tint[1])
    XCTAssertEqual(light.x, 48.0 / 256.0, accuracy: 0.1, "position near the sign")
  }

  func testChromaPassIgnoresAmbientColor() throws {
    // a saturated blue frame (dusk sky) is color, not a light source
    let img = canvas({ g, size in
      g.setFillColor(UIColor(red: 0.15, green: 0.3, blue: 0.9, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
    }, side: 128)
    let profile = try SceneAnalyzer(context: CIContext()).analyze(img)
    XCTAssertTrue(profile.auxLights.isEmpty, "ambient guard must refuse full-frame color")
  }

  func testNightLiftCappedForFlashStocks() {
    let engine = FilmEngine()
    let darkScene = SceneProfile(
      analyzed: true, key: 0.08, p01: 0.0, p50: 0.06, p99: 0.5,
      illum: [1, 1, 1], sat: 0.3, lights: [], auxLights: [], faceLum: nil,
      meanLuminance: 0.08, medianLuminance: 0.08, shadowFraction: 0.7,
      highlightFraction: 0.02, dynamicRange: 0.5, averageRed: 0.1,
      averageGreen: 0.1, averageBlue: 0.12, saturation: 0.3, warmth: 0,
      isLowKey: true, isHighKey: false, isBacklit: false
    )
    let flash = engine.adaptiveExposure(for: darkScene, recipe: .recipe(for: "iphone-flash"))
    let video = engine.adaptiveExposure(for: darkScene, recipe: .recipe(for: "camcorder-90s"))
    // camcorder (no flashPhysics) lifts freely; the flash stock must not fog
    // the night sky toward the midtone target
    XCTAssertLessThan(flash, video * 0.75,
                      "flash stocks must not lift a night sky the flash never reached")
    XCTAssertGreaterThan(flash, 0, "the subject exposure still gets some help")
  }

  // R78 — flash highlight headroom (photobooth face-blowout fix)
  func testFlashHighlightHeadroomWiringAndFaceCap() {
    // wiring: only photobooth carries the headroom; the color flash family
    // measured sound (7–10% face clip) and stays at 0 (unchanged).
    XCTAssertGreaterThan(CameraRecipe.recipe(for: "photobooth").flashHighlightHeadroom, 0)
    for id in ["iphone-flash", "y2k-digicam", "point-shoot", "disposable"] {
      XCTAssertEqual(CameraRecipe.recipe(for: id).flashHighlightHeadroom, 0, id)
    }
    // functional: a photobooth flashed face already near clip gets LESS adaptive
    // lift than the same scene with a mid-toned face — the headroom backing off.
    let engine = FilmEngine()
    func boothScene(faceLum: Double) -> SceneProfile {
      SceneProfile(
        analyzed: true, key: 0.17, p01: 0.0, p50: 0.14, p99: 0.7,
        illum: [1, 1, 1], sat: 0.3, lights: [], auxLights: [], faceLum: faceLum,
        meanLuminance: 0.17, medianLuminance: 0.14, shadowFraction: 0.5,
        highlightFraction: 0.05, dynamicRange: 0.6, averageRed: 0.15,
        averageGreen: 0.15, averageBlue: 0.16, saturation: 0.3, warmth: 0,
        isLowKey: true, isHighKey: false, isBacklit: false
      )
    }
    let booth = CameraRecipe.recipe(for: "photobooth")
    let hotFace = engine.adaptiveExposure(for: boothScene(faceLum: 0.86), recipe: booth)
    let midFace = engine.adaptiveExposure(for: boothScene(faceLum: 0.45), recipe: booth)
    XCTAssertLessThan(hotFace, midFace,
                      "headroom must back the lift off when the flashed face is near clip")
    XCTAssertGreaterThan(hotFace, 0, "the subject still gets some help")
  }

  func testKeyShadowFallsBackToChromaLights() {
    let img = canvas { g, size in
      g.setFillColor(UIColor(white: 0.5, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
    }
    let neon = LightSource(x: 0.08, y: 0.5, r: 0.04, intensity: 1, tint: [0.3, 0.4, 1])
    let out = FilmEngine.shared.applyKeyShadow(
      img, scene: scene(key: 0.1, lights: [], auxLights: [neon]),
      subject: SubjectAnalysis(faces: [], personMask: nil), amount: 0.7
    )
    let left = meanLuma(out, region: CGRect(x: 0.04, y: 0.33, width: 0.20, height: 0.34))
    let right = meanLuma(out, region: CGRect(x: 0.76, y: 0.33, width: 0.20, height: 0.34))
    XCTAssertGreaterThan(left, right + 6, "a chroma light must key the noir direction too")
  }

  // MARK: R64 — security-cam day/night mode

  func testSecurityCamGreenIROnlyAtNight() throws {
    // mid-gray scenes at two brightnesses: the IR green cast must appear at
    // night and vanish in daylight (real CCTV runs IR only in the dark)
    let recipe = CameraRecipe.recipe(for: "security-cam")
    func meanChannels(_ brightness: CGFloat) throws -> (r: Double, g: Double, b: Double) {
      let source = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { ctx in
        UIColor(white: brightness, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
      }
      let out = try FilmEngine().develop(source, with: recipe, seed: 3, analyzeSubjects: false).image
      let ci = CIImage(image: out)!
      guard let cg = context.createCGImage(ci, from: ci.extent),
            let raster = ImageMetrics.raster(cg),
            let mean = ImageMetrics.meanColor(raster, in: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4))
      else { throw XCTSkip("raster failed") }
      return mean
    }
    let day = try meanChannels(0.62)
    let night = try meanChannels(0.07)
    XCTAssertGreaterThan(night.g, max(night.r, night.b) + 4, "night must cast IR green")
    XCTAssertLessThan(abs(day.g - day.r), 6, "daylight must stay near-neutral, not green")
  }

  // MARK: R62 night physics

  func testNightReciprocityStarvesDarkScenesOnly() {
    let img = canvas { g, size in
      g.setFillColor(UIColor(white: 0.4, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
    }
    let night = FilmEngine.shared.applyNightReciprocity(img, scene: scene(key: 0.06), amount: 1.0)
    XCTAssertLessThan(meanLuma(night, region: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
                      meanLuma(img, region: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)) - 20,
                      "slow film must collapse in the dark")
    let day = FilmEngine.shared.applyNightReciprocity(img, scene: scene(key: 0.5), amount: 1.0)
    XCTAssertEqual(render(day), render(img), "daylight must be byte-identical (parity safety)")
  }

  /// R62.1 — the ratified verdict is "only the neon survives": a lit sign must
  /// stay readable while the street crushes. A bright, saturated neon patch on
  /// a dark field, in a scene the meter reads as emissive-lit; the carve-out
  /// (protectEmissive) must hold the sign back from the −2 EV collapse without
  /// rescuing the dead street.
  func testSuper8NightReciprocityLetsEmissiveHighlightsSurvive() {
    let img = canvas { g, size in
      g.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
      // a bright, saturated cyan neon sign
      g.setFillColor(UIColor(red: 0.55, green: 1.0, blue: 1.0, alpha: 1).cgColor)
      g.fill(CGRect(x: 32, y: 16, width: 32, height: 24))
    }
    let neonLight = LightSource(x: 0.5, y: 0.28, r: 0.06, intensity: 0.9, tint: [0.2, 0.9, 1.0])
    let night = scene(key: 0.06, p99: 0.88, lights: [neonLight])
    XCTAssertFalse(FilmEngine.emissiveLights(in: night).isEmpty, "scene must read as emissive")

    let before = FilmEngine.shared.applyNightReciprocity(img, scene: night, amount: 1.0, protectEmissive: false)
    let after = FilmEngine.shared.applyNightReciprocity(img, scene: night, amount: 1.0, protectEmissive: true)

    // neon region (CI y-up: UIKit y16..40 of 96 → CI 0.583..0.833)
    let neon = CGRect(x: 0.36, y: 0.60, width: 0.25, height: 0.20)
    // a dark corner of the street, away from the sign
    let street = CGRect(x: 0.05, y: 0.05, width: 0.20, height: 0.20)

    let beforeNeon = meanLuma(before, region: neon)
    let afterNeon = meanLuma(after, region: neon)
    let afterStreet = meanLuma(after, region: street)

    XCTAssertGreaterThan(afterNeon, beforeNeon + 20,
                         "the carve-out must let the lit sign survive the pull")
    XCTAssertGreaterThan(afterNeon, afterStreet + 40,
                         "the neon must read far above the dead street")
    XCTAssertLessThan(afterStreet, 25,
                      "the street must still crush — shadows die, only the neon survives")
  }

  func testCCDClipRacesHighlightsToWhite() {
    let img = canvas { g, size in
      g.setFillColor(UIColor(white: 0.9, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
    }
    let out = FilmEngine.shared.applyCCDClip(img, amount: 1.0)
    XCTAssertGreaterThan(meanLuma(out, region: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
                         meanLuma(img, region: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)) + 6,
                         "a 0.9 highlight must race toward clip on a CCD")
  }

  func testHighlightSmearIsVerticalAndDarkGateWorks() {
    // hot white dot on dark gray: smear must bleed vertically, not horizontally.
    // 256px canvas: the smear radius is 3.5% of the edge (~7.8px here), so the
    // probe strips must sit immediately adjacent to the dot's edges.
    let img = canvas({ g, size in
      g.setFillColor(UIColor(white: 0.1, alpha: 1).cgColor)
      g.fill(CGRect(origin: .zero, size: size))
      g.setFillColor(UIColor.white.cgColor)
      g.fill(CGRect(x: 116, y: 116, width: 24, height: 24))
    }, side: 256)
    let out = FilmEngine.shared.applyHighlightSmear(
      img, scene: scene(key: 0.08), amount: 1.0, onlyInDark: false
    )
    // 12px strip just below the dot (CI y-up) vs 12px strip just to its right
    let belowRegion = CGRect(x: 0.453, y: 0.398, width: 0.094, height: 0.047)
    let sideRegion = CGRect(x: 0.555, y: 0.453, width: 0.047, height: 0.094)
    let belowGain = meanLuma(out, region: belowRegion) - meanLuma(img, region: belowRegion)
    let sideGain = meanLuma(out, region: sideRegion) - meanLuma(img, region: sideRegion)
    XCTAssertGreaterThan(belowGain, sideGain + 2,
                         "smear must run down the column, not sideways")

    // dark-only variant is a byte-identical no-op in daylight
    let day = FilmEngine.shared.applyHighlightSmear(
      img, scene: scene(key: 0.5), amount: 1.0, onlyInDark: true
    )
    XCTAssertEqual(render(day), render(img))
  }

  func testR62RecipeGates() {
    XCTAssertEqual(CameraRecipe.recipe(for: "super-8").nightReciprocity, 1.0)
    XCTAssertEqual(CameraRecipe.recipe(for: "y2k-digicam").ccdClip, 1.0)
    XCTAssertEqual(CameraRecipe.recipe(for: "y2k-digicam").highlightSmear, 0.6)
    XCTAssertFalse(CameraRecipe.recipe(for: "y2k-digicam").highlightSmearDarkOnly)
    XCTAssertEqual(CameraRecipe.recipe(for: "camcorder-90s").highlightSmear, 0.85)
    XCTAssertTrue(CameraRecipe.recipe(for: "camcorder-90s").highlightSmearDarkOnly)
    XCTAssertEqual(CameraRecipe.recipe(for: "photobooth").flashPhysics, 1.0, "booth curtain")
    for id in ["leica-street", "kodachrome", "polaroid", "film-noir", "tokyo-neon", "tintype"] {
      let recipe = CameraRecipe.recipe(for: id)
      XCTAssertEqual(recipe.nightReciprocity, 0, id)
      XCTAssertEqual(recipe.ccdClip, 0, id)
      XCTAssertEqual(recipe.highlightSmear, 0, id)
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
