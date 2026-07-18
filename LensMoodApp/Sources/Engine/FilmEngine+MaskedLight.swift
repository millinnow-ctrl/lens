import CoreImage
import UIKit

/// R66 masked-light passes — the look interacts with WHAT is in the photograph
/// (the subject's silhouette, skin, the sky), not only with global statistics.
/// Prototyped on the fixture photographs and ratified in review with these
/// conditions, all enforced here:
///  · rim halation is backlight-gated (rim only where the scene is genuinely
///    bright behind the edge), traced on a CLEANED silhouette (largest
///    component, holes filled — never interior halos or floating blobs),
///    feathered at the matte's native resolution, tinted by the source light's
///    chroma-boosted color; no metered lights → structural no-op;
///  · skin protection eases the developed pixel toward a gentler variant of
///    what the stock's own color core just did, scoped to
///    person ∩ skin-chroma ∩ luma-window; outside-mask pixels byte-identical;
///  · sky response refuses below a coverage threshold, and the mask carries
///    per-pixel chromatic-blue evidence so the grade can never land on
///    rooflines, shirts, or sunlit walls.
/// All masks are produced ONCE inside `FilmEngine.read`'s subject pass and
/// stored on `SubjectAnalysis`; the passes only consume them. Deterministic
/// (no randomness) and recipe-gated: stocks with zeroed fields — and any
/// develop with `analyzeSubjects: false` — render byte-identically to before.
///
/// Label: intentional camera refinement (owner-directed masked-light physics).
extension FilmEngine {

  // MARK: - Mask production (called ONLY from `read`'s subject pass)

  /// Working resolution (long edge) of the analysis raster the mask
  /// heuristics run on. Masks are materialized as single-channel bytes at
  /// this size and upscaled lazily where a pass uses them.
  static let maskThumbLongEdge = 512

  /// The prototype's constants are stated at a 900px long edge; every radius
  /// here is rescaled by (thumb long edge / 900) so the masks and the rim
  /// geometry stay scale-covariant.
  static let prototypeLongEdge = 900.0

  /// One analysis raster: RGBA8 bytes of the oriented photograph plus the
  /// Vision person matte resampled onto the same grid. Internal so the mask
  /// builders can be driven directly by unit tests with synthetic rasters.
  struct AnalysisRaster {
    let width: Int
    let height: Int
    /// RGBA8, row-major, first row = top of the photograph
    let pixels: [UInt8]
    /// person matte 0…1 aligned with `pixels`, when Vision produced one
    let person: [Float]?
  }

  /// Attach the masked-light masks to a Vision subject analysis. Produces the
  /// cleaned silhouette, the skin mask, and the sky mask from one small
  /// analysis raster (mirroring SceneAnalyzer's CPU-thumb approach).
  func attachLightMasks(to base: SubjectAnalysis, image: CIImage) -> SubjectAnalysis {
    guard let raster = analysisRaster(for: image, personMask: base.personMask) else {
      return base
    }
    let matteBytes = FilmEngine.buildSubjectMatte(raster)
    let skinBytes = FilmEngine.buildSkinMask(raster, subjectMatte: matteBytes)
    let skyBytes = FilmEngine.buildSkyMask(raster, subjectMatte: matteBytes)
    func materialize(_ bytes: [UInt8]?) -> CIImage? {
      guard let bytes else { return nil }
      return CIImage(
        bitmapData: Data(bytes),
        bytesPerRow: raster.width,
        size: CGSize(width: raster.width, height: raster.height),
        format: .L8,
        colorSpace: nil
      )
    }
    return SubjectAnalysis(
      faces: base.faces,
      personMask: base.personMask,
      subjectMatte: materialize(matteBytes),
      skinMask: materialize(skinBytes),
      skyMask: materialize(skyBytes)
    )
  }

  /// Downscale the oriented photograph (and the person matte, onto the same
  /// grid) into CPU bytes for the mask heuristics.
  private func analysisRaster(for image: CIImage, personMask: CIImage?) -> AnalysisRaster? {
    let sw = image.extent.width
    let sh = image.extent.height
    guard sw > 1, sh > 1 else { return nil }
    let scale = min(1, CGFloat(FilmEngine.maskThumbLongEdge) / max(sw, sh))
    let w = max(2, Int((sw * scale).rounded()))
    let h = max(2, Int((sh * scale).rounded()))
    guard let pixels = renderRGBA(image, width: w, height: h) else { return nil }
    var person: [Float]?
    if let personMask, let maskPixels = renderRGBA(personMask, width: w, height: h) {
      var plane = [Float](repeating: 0, count: w * h)
      for i in 0..<(w * h) {
        plane[i] = Float(maskPixels[i * 4]) / 255
      }
      person = plane
    }
    return AnalysisRaster(width: w, height: h, pixels: pixels, person: person)
  }

  /// Render any CIImage to a width×height RGBA8 buffer (top-down row-major),
  /// resampling with the engine's own context.
  private func renderRGBA(_ image: CIImage, width: Int, height: Int) -> [UInt8]? {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let zeroed = image.orientedForDisplay
    let sx = CGFloat(width) / max(zeroed.extent.width, 1)
    let sy = CGFloat(height) / max(zeroed.extent.height, 1)
    let scaled = zeroed
      .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
      .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    guard let cg = context.createCGImage(
      scaled,
      from: scaled.extent,
      format: .RGBA8,
      colorSpace: colorSpace
    ) else { return nil }
    var px = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = px.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
      guard let cgContext = CGContext(
        data: buffer.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return false }
      cgContext.interpolationQuality = .none
      cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return drawn ? px : nil
  }

  /// Cleaned subject silhouette — the outline the rim pass traces. Largest
  /// 4-connected component of the binarized person matte, interior holes
  /// filled (the ratified fix for interior halos and floating rim blobs).
  /// nil without a usable person matte.
  static func buildSubjectMatte(_ raster: AnalysisRaster) -> [UInt8]? {
    guard let person = raster.person else { return nil }
    let w = raster.width
    let h = raster.height
    let n = w * h
    var binary = [Bool](repeating: false, count: n)
    var count = 0
    for i in 0..<n where person[i] > 0.5 {
      binary[i] = true
      count += 1
    }
    // the matte must be a real subject, not a few stray pixels
    guard count >= max(16, n / 400) else { return nil }
    let cleaned = fillHoles(largestComponent(binary, width: w, height: h), width: w, height: h)
    var out = [UInt8](repeating: 0, count: n)
    var kept = 0
    for i in 0..<n where cleaned[i] {
      out[i] = 255
      kept += 1
    }
    return kept > 0 ? out : nil
  }

  /// Skin mask v3 (ratified): person matte ∩ tight skin chroma
  /// (Cb 95…122, Cr 138…173) ∩ luma window 0.28…0.96, opened (speckles die)
  /// then closed (pores and specular pinholes heal), feathered ≈4px at the
  /// prototype's 900px scale. nil when nothing plausibly skin survives.
  static func buildSkinMask(_ raster: AnalysisRaster, subjectMatte: [UInt8]?) -> [UInt8]? {
    guard let matte = subjectMatte else { return nil }
    let w = raster.width
    let h = raster.height
    let n = w * h
    let px = raster.pixels
    var candidate = [Bool](repeating: false, count: n)
    var any = false
    for i in 0..<n where matte[i] > 0 {
      let r = Double(px[i * 4])
      let g = Double(px[i * 4 + 1])
      let b = Double(px[i * 4 + 2])
      let cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
      let cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
      let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255
      if cb >= 95, cb <= 122, cr >= 138, cr <= 173, luma >= 0.28, luma <= 0.96 {
        candidate[i] = true
        any = true
      }
    }
    guard any else { return nil }
    // opening then closing, exactly the prototype's v3 order
    var m = binaryDilate(binaryErode(candidate, width: w, height: h, radius: 1), width: w, height: h, radius: 1)
    m = binaryErode(binaryDilate(m, width: w, height: h, radius: 1), width: w, height: h, radius: 1)
    var plane = [Float](repeating: 0, count: n)
    var kept = 0
    for i in 0..<n where m[i] {
      plane[i] = 1
      kept += 1
    }
    guard kept >= 12 else { return nil }
    let sigma = 4.0 * Double(max(w, h)) / FilmEngine.prototypeLongEdge
    let feathered = gaussianBlur(plane, width: w, height: h, sigma: sigma)
    var out = [UInt8](repeating: 0, count: n)
    for i in 0..<n {
      out[i] = UInt8(min(255, max(0, (Double(feathered[i]) * 255).rounded())))
    }
    return out
  }

  /// Sky mask v2b (ratified): chromatic-blue evidence only — blue dominance,
  /// hue 195…265°, low texture, top-of-frame prior, not-subject; binary
  /// components must touch the top 12% of the frame and cover >0.2% each;
  /// the feathered result is multiplied by a per-pixel chroma gate (kills the
  /// roofline scallop). Coverage below ~6% of the frame refuses outright
  /// (returns nil) so skyless scenes are bitwise no-ops.
  static func buildSkyMask(_ raster: AnalysisRaster, subjectMatte: [UInt8]?) -> [UInt8]? {
    let w = raster.width
    let h = raster.height
    let n = w * h
    let px = raster.pixels
    let s = Double(max(w, h)) / FilmEngine.prototypeLongEdge

    var lumaPlane = [Float](repeating: 0, count: n)
    var blueDom = [Double](repeating: 0, count: n)
    for i in 0..<n {
      let r = Double(px[i * 4]) / 255
      let g = Double(px[i * 4 + 1]) / 255
      let b = Double(px[i * 4 + 2]) / 255
      lumaPlane[i] = Float(0.299 * r + 0.587 * g + 0.114 * b)
      blueDom[i] = b - max(r, g)
    }

    // texture: gradient magnitude of the softened luma, expressed in the
    // prototype's 900px per-pixel units so its thresholds transfer
    let soft = gaussianBlur(lumaPlane, width: w, height: h, sigma: 1.5 * s)
    var grad = [Float](repeating: 0, count: n)
    for y in 0..<h {
      for x in 0..<w {
        let xm = max(x - 1, 0)
        let xp = min(x + 1, w - 1)
        let ym = max(y - 1, 0)
        let yp = min(y + 1, h - 1)
        let gx = Double(soft[y * w + xp] - soft[y * w + xm]) / Double(max(xp - xm, 1))
        let gy = Double(soft[yp * w + x] - soft[ym * w + x]) / Double(max(yp - ym, 1))
        grad[y * w + x] = Float((gx * gx + gy * gy).squareRoot() * s)
      }
    }
    let tex = gaussianBlur(grad, width: w, height: h, sigma: 4 * s)

    var binary = [Bool](repeating: false, count: n)
    for y in 0..<h {
      let top = 1 - smoothStep(0.50, 0.78, Double(y) / Double(h))
      guard top > 0 else { continue }
      for x in 0..<w {
        let i = y * w + x
        let r = Double(px[i * 4]) / 255
        let g = Double(px[i * 4 + 1]) / 255
        let b = Double(px[i * 4 + 2]) / 255
        let blue = smoothStep(0.015, 0.09, blueDom[i])
        guard blue > 0 else { continue }
        let hue = hueDegrees(r: r, g: g, b: b)
        guard hue >= 195, hue <= 265 else { continue }
        let lowTex = 1 - smoothStep(0.012, 0.03, Double(tex[i]))
        var v = blue * lowTex * top
        if let matte = subjectMatte, matte[i] > 102 { v = 0 } // not-subject (>0.4)
        if v > 0.5 { binary[i] = true }
      }
    }

    let kept = topTouchingComponents(binary, width: w, height: h, topFraction: 0.12, minFraction: 0.002)
    var plane = [Float](repeating: 0, count: n)
    for i in 0..<n where kept[i] { plane[i] = 1 }
    let feathered = gaussianBlur(plane, width: w, height: h, sigma: 3 * s)
    var out = [UInt8](repeating: 0, count: n)
    var coverage = 0
    for i in 0..<n {
      let gate = smoothStep(0.02, 0.06, blueDom[i])
      let v = Double(feathered[i]) * gate
      if v > 0.5 { coverage += 1 }
      out[i] = UInt8(min(255, max(0, (v * 255).rounded())))
    }
    // refusal: a sky that barely exists is left alone (the prototype measured
    // brunch/street coverage 0.0000 → bitwise no-op, pinned by tests)
    guard Double(coverage) >= 0.06 * Double(n) else { return nil }
    return out
  }

  // MARK: - Pass 2: skin-protected curve

  /// Ease the pixels under the skin mask toward a gentler variant of what the
  /// stock's color core just did. Outside-mask pixels are returned exactly
  /// (mask 0 → identity in the kernel). Mono stocks are contrast-ease only.
  func applySkinProtection(
    _ image: CIImage,
    subject: SubjectAnalysis,
    recipe: CameraRecipe,
    amount: Double
  ) -> CIImage {
    guard amount > 0.001, let mask = subject.skinMask,
          let kernel = skinProtectKernel else { return image }
    let extent = image.extent
    let ease = 0.24 * amount
    let lift = recipe.monochrome ? 0.0 : 0.043 * amount
    let shaped = kernel.apply(
      extent: extent,
      arguments: [image, maskScaled(mask, to: extent), ease, lift]
    )
    return shaped?.cropped(to: extent) ?? image
  }

  // MARK: - Pass 3: sky-scoped color

  /// The deepen family scales with scene key — near-black night skies are left
  /// alone (ratified: skip below key ≈ 0.1). Shared with the decision notes.
  func deepenKeyScale(_ scene: SceneProfile) -> Double {
    min(1, max(0, (scene.key - 0.10) / 0.20))
  }

  /// True exactly when `applySkyResponse` will do more than return its input —
  /// the decision-note gate, kept in lockstep with the pass's own guards.
  func skyPassEngages(scene: SceneProfile, subject: SubjectAnalysis, recipe: CameraRecipe) -> Bool {
    guard recipe.skyResponse > 0.001, scene.analyzed, subject.skyMask != nil else { return false }
    switch recipe.id {
    case "tintype", "film-noir", "polaroid", "pastel-cinema":
      return true
    default:
      return deepenKeyScale(scene) > 0.001
    }
  }

  /// Grade only the sky, the way this film sees it. Characters (ratified):
  /// deepen (slide/consumer color, halved from the prototype and scaled by
  /// scene key), pastel (instant/cinema cream), orthochromatic blow-out
  /// (tintype — blue registers hot, the sky pales), filter-darken (noir —
  /// luminance-only, the deep-red-filter sky).
  func applySkyResponse(
    _ image: CIImage,
    scene: SceneProfile,
    subject: SubjectAnalysis,
    recipe: CameraRecipe,
    amount: Double
  ) -> CIImage {
    guard amount > 0.001, scene.analyzed, let mask = subject.skyMask else { return image }
    let extent = image.extent
    var weight = amount
    let graded: CIImage
    switch recipe.id {
    case "tintype":
      // orthochromatic wet plate: blue registers hot — the sky pales toward
      // blown, silver-flat
      graded = image
        .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.25])
        .applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: 1.30, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 1.30, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 1.30, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: 0.10, y: 0.10, z: 0.10, w: 0),
        ])
    case "film-noir":
      // deep-red filter: the sky falls dark. Uniform gain = luminance-only,
      // so the LUT's baked silver split-tone survives untouched.
      graded = image.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: 0.55, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: 0.55, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: 0.55, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
      ])
    case "polaroid", "pastel-cinema":
      // creamy desaturated sky, exactly the prototype's pastel grade
      graded = image
        .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.42])
        .applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: 1.03, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 1.00, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 0.95, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: 0.055, y: 0.055, z: 0.055, w: 0),
        ])
        .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.92])
    default:
      // deepen family — the prototype's kodachrome deepen with the darkening
      // HALVED (contrast 1.18→1.09 about pivot 0.38, offset −0.02→−0.01) and
      // scaled by scene key; per-stock color of blue below
      let keyScale = deepenKeyScale(scene)
      guard keyScale > 0.001 else { return image }
      weight = amount * keyScale
      let gains: (r: Double, g: Double, b: Double)
      let skySaturation: Double
      switch recipe.id {
      case "kodachrome":
        gains = (0.74, 0.90, 1.06)
        skySaturation = 1.35
      case "lomo":
        gains = (0.78, 0.90, 1.06)
        skySaturation = 1.60
      case "super-8":
        gains = (0.88, 0.94, 1.02)
        skySaturation = 1.20
      case "leica-street":
        gains = (0.85, 0.93, 1.04)
        skySaturation = 1.10
      case "point-shoot":
        gains = (0.80, 0.92, 1.05)
        skySaturation = 1.25
      default:
        gains = (0.85, 0.93, 1.04)
        skySaturation = 1.15
      }
      graded = image
        .applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: gains.r, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: gains.g, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: gains.b, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: skySaturation])
        .applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: 1.09, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 1.09, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 1.09, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          "inputBiasVector": CIVector(x: -0.0442, y: -0.0442, z: -0.0442, w: 0),
        ])
    }
    let clamped = graded.applyingFilter("CIColorClamp", parameters: [
      "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
      "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
    ])
    let weighted = maskScaled(mask, to: extent).applyingFilter("CIColorMatrix", parameters: [
      "inputRVector": CIVector(x: weight, y: 0, z: 0, w: 0),
      "inputGVector": CIVector(x: 0, y: weight, z: 0, w: 0),
      "inputBVector": CIVector(x: 0, y: 0, z: weight, w: 0),
      "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
    ])
    return clamped.applyingFilter("CIBlendWithMask", parameters: [
      kCIInputBackgroundImageKey: image,
      kCIInputMaskImageKey: weighted,
    ]).cropped(to: extent)
  }

  // MARK: - Pass 1: rim-light halation

  /// The lights the rim pass may trace from. Tokyo-neon shares the emissive
  /// refusal with its source bloom (ratified); every other rim stock traces
  /// from any metered source — the per-pixel backlight gate does the rest.
  func rimSources(scene: SceneProfile, recipe: CameraRecipe) -> [LightSource] {
    guard scene.analyzed else { return [] }
    if recipe.id == "tokyo-neon" {
      return FilmEngine.emissiveLights(in: scene)
    }
    return scene.lights + scene.auxLights
  }

  /// Backlight-aware rim halation: a narrow feathered band along the cleaned
  /// silhouette brightens ONLY where a metered light sits behind that edge,
  /// in the source's own chroma-boosted color. Geometry is computed at the
  /// matte's native resolution (feathering included — never a jagged rim) and
  /// upscaled once; every radius is a fraction of the frame, so preview and
  /// export agree. Default is the narrow flavor; super-8 uses the wide glow.
  func applyRimHalation(
    _ image: CIImage,
    scene: SceneProfile,
    subject: SubjectAnalysis,
    recipe: CameraRecipe,
    amount: Double
  ) -> CIImage {
    guard amount > 0.001, let matte = subject.subjectMatte,
          let gateKernel = rimGateKernel,
          let meanKernel = maskedMeanKernel,
          let compressKernel = rimCompressKernel else { return image }
    let sources = rimSources(scene: scene, recipe: recipe)
    // no metered lights → structural no-op (the prototype measured
    // maxdiff 0.000000 on the lightless fixture; pinned by tests)
    guard !sources.isEmpty else { return image }
    let extent = image.extent
    let thumbExtent = matte.extent
    let tw = thumbExtent.width
    let th = thumbExtent.height
    guard tw > 4, th > 4, extent.width > 4, extent.height > 4 else { return image }
    let tLong = Double(max(tw, th))
    let s = tLong / FilmEngine.prototypeLongEdge
    let wide = recipe.id == "super-8" // the ratified wide-B2 flavor

    // floors keep the band alive on small mattes (a sub-pixel morphology
    // radius would collapse dilated == eroded == matte, i.e. no band at all)
    let clamped = matte.clampedToExtent()
    let outerRadius = max(1.0, (wide ? 7.0 : 2.0) * s)
    let innerRadius = max(1.0, (wide ? 2.0 : 1.0) * s)
    let dilated = clamped
      .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: outerRadius])
      .cropped(to: thumbExtent)
    let eroded = clamped
      .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: innerRadius])
      .cropped(to: thumbExtent)
    let matteSoft = clamped
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(0.6, 2 * s)])
      .cropped(to: thumbExtent)

    // backlight: brightness of the scene just OUTSIDE the silhouette, blurred
    // wide — halation needs light behind the edge, not merely a light in frame
    let thumbImage = image
      .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
      .transformed(by: CGAffineTransform(scaleX: tw / extent.width, y: th / extent.height))
      .cropped(to: thumbExtent)
    let thumbLuma = thumbImage.applyingFilter("CIColorMonochrome", parameters: [
      kCIInputColorKey: CIColor.white,
      kCIInputIntensityKey: 1,
    ])
    let outside = matte.applyingFilter("CIColorInvert")
    let bgRadius = 12 * s
    let num = thumbLuma
      .applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: outside])
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: bgRadius])
      .cropped(to: thumbExtent)
    let den = outside
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: bgRadius])
      .cropped(to: thumbExtent)
    guard let backlight = meanKernel.apply(extent: thumbExtent, arguments: [num, den]) else {
      return image
    }

    let reach = 0.85 * tLong
    let invR2 = 1.0 / (reach * reach)
    let facingPower = wide ? 1.2 : 1.6
    let facingStep = max(1.5, 3 * s)
    var accumulated: CIImage?
    for light in sources {
      let lx = Double(light.x) * Double(tw)
      let ly = (1 - Double(light.y)) * Double(th) // meter y is top-down; CI is y-up
      // facing ≈ does the silhouette open toward this light: the soft matte
      // compared against itself sampled a step toward the source
      var dirX = lx - Double(tw) / 2
      var dirY = ly - Double(th) / 2
      let mag = (dirX * dirX + dirY * dirY).squareRoot()
      guard mag > 1 else { continue } // a dead-center light has no side
      dirX /= mag
      dirY /= mag
      let shifted = matteSoft
        .transformed(by: CGAffineTransform(translationX: -dirX * facingStep, y: -dirY * facingStep))
        .clampedToExtent()
        .cropped(to: thumbExtent)
      let weight = 0.35 + 0.65 * min(1, light.intensity)
      guard let gated = gateKernel.apply(extent: thumbExtent, arguments: [
        dilated, eroded, matteSoft, shifted, backlight,
        lx, ly, invR2, facingPower, weight,
      ]) else { continue }
      // the rim carries the source's own color, chroma-boosted ×1.6 about its
      // mean (ratified); mono stocks keep it silver
      let tint = rimTint(light.tint, mono: recipe.monochrome)
      let tinted = gated.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: tint[0], y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: tint[1], y: 0, z: 0, w: 0),
        "inputBVector": CIVector(x: tint[2], y: 0, z: 0, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
      ])
      if let existing = accumulated {
        accumulated = tinted.applyingFilter("CIAdditionCompositing", parameters: [
          kCIInputBackgroundImageKey: existing,
        ])
      } else {
        accumulated = tinted
      }
    }
    guard let rimAccumulated = accumulated,
          let compressed = compressKernel.apply(extent: thumbExtent, arguments: [rimAccumulated])
    else { return image }

    // feather at the matte's NATIVE resolution (ratified — never composite the
    // low-res band's polygonal edges), then a single upscale to the frame
    let blurRadius = max(0.4, (wide ? 6.0 : 1.2) * s)
    let gain = (wide ? 0.42 : 0.62) * amount
    let rimLayer = compressed
      .clampedToExtent()
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
      .cropped(to: thumbExtent)
      .applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
      ])
      .transformed(by: CGAffineTransform(scaleX: extent.width / tw, y: extent.height / th))
      .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
      .cropped(to: extent)
    return rimLayer.applyingFilter("CIScreenBlendMode", parameters: [
      kCIInputBackgroundImageKey: image,
    ]).cropped(to: extent)
  }

  // MARK: - Shared helpers

  /// Upscale a stored mask thumb onto the working extent (bilinear).
  private func maskScaled(_ mask: CIImage, to extent: CGRect) -> CIImage {
    let sx = extent.width / max(mask.extent.width, 1)
    let sy = extent.height / max(mask.extent.height, 1)
    return mask
      .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
      .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
      .cropped(to: extent)
  }

  private func rimTint(_ tint: [Double], mono: Bool) -> [Double] {
    guard tint.count == 3 else { return [1, 1, 1] }
    let mean = (tint[0] + tint[1] + tint[2]) / 3
    if mono { return [mean, mean, mean] }
    return tint.map { max(0, min(1, mean + ($0 - mean) * 1.6)) }
  }
}

// MARK: - CPU raster utilities (deterministic, thumb-resolution)

private func smoothStep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
  let t = min(1, max(0, (x - edge0) / max(edge1 - edge0, 1e-6)))
  return t * t * (3 - 2 * t)
}

private func hueDegrees(r: Double, g: Double, b: Double) -> Double {
  let mx = max(r, max(g, b))
  let mn = min(r, min(g, b))
  let c = mx - mn
  guard c > 1e-6 else { return 0 }
  var hue: Double
  if mx == r {
    hue = ((g - b) / c).truncatingRemainder(dividingBy: 6)
    if hue < 0 { hue += 6 }
  } else if mx == g {
    hue = (b - r) / c + 2
  } else {
    hue = (r - g) / c + 4
  }
  return hue * 60
}

/// Separable gaussian blur over a single float plane, edge-clamped.
private func gaussianBlur(_ plane: [Float], width: Int, height: Int, sigma: Double) -> [Float] {
  guard sigma > 0.2 else { return plane }
  let radius = max(1, Int((sigma * 3).rounded()))
  var weights = [Float](repeating: 0, count: radius * 2 + 1)
  var total: Float = 0
  for i in -radius...radius {
    let value = Float(exp(-Double(i * i) / (2 * sigma * sigma)))
    weights[i + radius] = value
    total += value
  }
  for i in weights.indices { weights[i] /= total }
  var horizontal = [Float](repeating: 0, count: plane.count)
  for y in 0..<height {
    for x in 0..<width {
      var acc: Float = 0
      for k in -radius...radius {
        let sx = min(max(x + k, 0), width - 1)
        acc += plane[y * width + sx] * weights[k + radius]
      }
      horizontal[y * width + x] = acc
    }
  }
  var out = [Float](repeating: 0, count: plane.count)
  for y in 0..<height {
    for x in 0..<width {
      var acc: Float = 0
      for k in -radius...radius {
        let sy = min(max(y + k, 0), height - 1)
        acc += horizontal[sy * width + x] * weights[k + radius]
      }
      out[y * width + x] = acc
    }
  }
  return out
}

private func binaryDilate(_ mask: [Bool], width: Int, height: Int, radius: Int) -> [Bool] {
  var out = [Bool](repeating: false, count: mask.count)
  for y in 0..<height {
    for x in 0..<width where mask[y * width + x] {
      for dy in -radius...radius {
        let ny = y + dy
        guard ny >= 0, ny < height else { continue }
        for dx in -radius...radius {
          let nx = x + dx
          guard nx >= 0, nx < width else { continue }
          out[ny * width + nx] = true
        }
      }
    }
  }
  return out
}

private func binaryErode(_ mask: [Bool], width: Int, height: Int, radius: Int) -> [Bool] {
  var out = [Bool](repeating: false, count: mask.count)
  for y in 0..<height {
    for x in 0..<width where mask[y * width + x] {
      var keep = true
      search: for dy in -radius...radius {
        let ny = min(max(y + dy, 0), height - 1)
        for dx in -radius...radius {
          let nx = min(max(x + dx, 0), width - 1)
          if !mask[ny * width + nx] {
            keep = false
            break search
          }
        }
      }
      out[y * width + x] = keep
    }
  }
  return out
}

/// Keep only the largest 4-connected component.
private func largestComponent(_ mask: [Bool], width: Int, height: Int) -> [Bool] {
  var seen = [Bool](repeating: false, count: mask.count)
  var best: [Int] = []
  var stack: [Int] = []
  for start in 0..<mask.count where mask[start] && !seen[start] {
    var component: [Int] = []
    stack.removeAll(keepingCapacity: true)
    stack.append(start)
    seen[start] = true
    while let i = stack.popLast() {
      component.append(i)
      let x = i % width
      let y = i / width
      if x > 0, mask[i - 1], !seen[i - 1] { seen[i - 1] = true; stack.append(i - 1) }
      if x < width - 1, mask[i + 1], !seen[i + 1] { seen[i + 1] = true; stack.append(i + 1) }
      if y > 0, mask[i - width], !seen[i - width] { seen[i - width] = true; stack.append(i - width) }
      if y < height - 1, mask[i + width], !seen[i + width] { seen[i + width] = true; stack.append(i + width) }
    }
    if component.count > best.count { best = component }
  }
  var out = [Bool](repeating: false, count: mask.count)
  for i in best { out[i] = true }
  return out
}

/// Fill interior holes: flood the complement from the border; complement
/// pixels the flood never reached are holes.
private func fillHoles(_ mask: [Bool], width: Int, height: Int) -> [Bool] {
  var reached = [Bool](repeating: false, count: mask.count)
  var stack: [Int] = []
  func seed(_ i: Int) {
    if !mask[i], !reached[i] {
      reached[i] = true
      stack.append(i)
    }
  }
  for x in 0..<width {
    seed(x)
    seed((height - 1) * width + x)
  }
  for y in 0..<height {
    seed(y * width)
    seed(y * width + width - 1)
  }
  while let i = stack.popLast() {
    let x = i % width
    let y = i / width
    if x > 0 { seed(i - 1) }
    if x < width - 1 { seed(i + 1) }
    if y > 0 { seed(i - width) }
    if y < height - 1 { seed(i + width) }
  }
  var out = [Bool](repeating: false, count: mask.count)
  for i in 0..<mask.count {
    out[i] = mask[i] || !reached[i]
  }
  return out
}

/// Keep 4-connected components that touch the top `topFraction` of the frame
/// AND cover more than `minFraction` of it.
private func topTouchingComponents(
  _ mask: [Bool],
  width: Int,
  height: Int,
  topFraction: Double,
  minFraction: Double
) -> [Bool] {
  var seen = [Bool](repeating: false, count: mask.count)
  var out = [Bool](repeating: false, count: mask.count)
  var stack: [Int] = []
  let topRows = max(1, Int(topFraction * Double(height)))
  let minCount = Int(minFraction * Double(width * height))
  for start in 0..<mask.count where mask[start] && !seen[start] {
    var component: [Int] = []
    var touchesTop = false
    stack.removeAll(keepingCapacity: true)
    stack.append(start)
    seen[start] = true
    while let i = stack.popLast() {
      component.append(i)
      let x = i % width
      let y = i / width
      if y < topRows { touchesTop = true }
      if x > 0, mask[i - 1], !seen[i - 1] { seen[i - 1] = true; stack.append(i - 1) }
      if x < width - 1, mask[i + 1], !seen[i + 1] { seen[i + 1] = true; stack.append(i + 1) }
      if y > 0, mask[i - width], !seen[i - width] { seen[i - width] = true; stack.append(i - width) }
      if y < height - 1, mask[i + width], !seen[i + width] { seen[i + width] = true; stack.append(i + width) }
    }
    if touchesTop, component.count > minCount {
      for i in component { out[i] = true }
    }
  }
  return out
}
