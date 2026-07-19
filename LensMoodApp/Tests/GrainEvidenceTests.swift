import CoreImage
import UIKit
import XCTest
@testable import LensMood

/// Owner-approval evidence for grain stage 1 (intentional camera refinement —
/// it does NOT ship until the owner approves these grids). For every stock, a
/// 512px center crop of sample-friends developed with the pre-stage-1 grain
/// (V1, left) beside the stage-1 grain (V2, right), published to
/// `ui-artifacts/grain-v2/` — plus full-frame tokyo-neon pairs on friends and
/// night.
///
/// Method for the V1 "before" panes: the kernel below is the pre-change
/// source, kept verbatim in this test. Only the 8 adaptive stocks use the
/// develop-path grain, and for them grain is the final develop stage (the
/// photobooth mono-enforce commutes with equal-channel noise), so applying
/// the V1 kernel over a grain-zeroed develop reproduces the pre-change
/// render, modulo 8-bit quantization. The 10 LUT stocks ride the untouched
/// reference-parity grain, so their two panes are the same render — an
/// honest record that stage 1 did not move them.
final class GrainEvidenceTests: XCTestCase {

  /// The pre-stage-1 develop grain, verbatim (historical reference only).
  private static let v1Kernel = CIColorKernel(source: """
    kernel vec4 lensMoodGrain(__sample pixel, float amount, float seed, float grainSize) {
      vec2 cell = floor(destCoord() / max(grainSize, 0.5));
      float random = fract(sin(dot(cell, vec2(12.9898, 78.233)) + seed) * 43758.5453);
      float noise = (random - 0.5) * amount;
      return vec4(clamp(pixel.rgb + vec3(noise), 0.0, 1.0), pixel.a);
    }
    """)

  private static let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  private static let repoRoot = testsDirectory
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  func testExportGrainStageOneApprovalGrids() throws {
    let outDir = Self.testsDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("ui-artifacts/grain-v2")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let engine = FilmEngine()
    let friends = try source("sample-friends.jpg")

    for stock in Stock.all {
      let recipe = stock.recipe
      let after = try engine.develop(
        friends, with: recipe, maxPixelSize: 1024, seed: 1, analyzeSubjects: false
      ).image
      // develop-path grain fires only when the stock has no reference-spatial
      // profile — the same branch the engine takes
      let before = recipe.referenceSpatial == nil
        ? try v1Develop(friends, recipe: recipe, engine: engine)
        : after
      let grid = sideBySide(centerCrop(before), centerCrop(after))
      let data = try XCTUnwrap(grid.pngData(), stock.id)
      try data.write(to: outDir.appendingPathComponent("grid-\(stock.id).png"))
      XCTAssertGreaterThan(grid.size.width, 0, stock.id)
    }

    // full-frame pairs: tokyo-neon on friends + night (a LUT stock — the
    // reference-parity grain path, byte-identical before/after by design)
    let neon = CameraRecipe.recipe(for: "tokyo-neon")
    let night = try source("sample-night.jpg")
    for (name, photo) in [("friends", friends), ("night", night)] {
      let frame = try engine.develop(
        photo, with: neon, maxPixelSize: 1024, seed: 1, analyzeSubjects: false
      ).image
      let data = try XCTUnwrap(frame.pngData(), name)
      try data.write(to: outDir.appendingPathComponent("full-tokyo-neon-\(name)-v1.png"))
      try data.write(to: outDir.appendingPathComponent("full-tokyo-neon-\(name)-v2.png"))
    }
  }

  // MARK: helpers

  private func source(_ name: String) throws -> UIImage {
    let url = Self.repoRoot.appendingPathComponent("reference/photos/\(name)")
    return try XCTUnwrap(UIImage(contentsOfFile: url.path), "missing fixture photo \(name)")
  }

  /// The pre-change render for a develop-path-grain stock: grain-zeroed
  /// develop, then the verbatim V1 kernel with exactly the amount, size, and
  /// seed the V1 pipeline would have used.
  private func v1Develop(
    _ photo: UIImage, recipe: CameraRecipe, engine: FilmEngine
  ) throws -> UIImage {
    let zeroed = try engine.develop(
      photo, with: withZeroGrain(recipe), maxPixelSize: 1024, seed: 1, analyzeSubjects: false
    )
    let amount = recipe.gainDrivenGrain
      ? recipe.grain * FilmEngine.gainGrainFactor(key: zeroed.scene.key)
      : recipe.grain
    guard amount > 0.001,
          let kernel = Self.v1Kernel,
          let base = CIImage(image: zeroed.image),
          let grained = kernel.apply(
            extent: base.extent,
            arguments: [base, amount, 1.0, recipe.grainSize]
          ),
          let cg = engine.context.createCGImage(
            grained,
            from: grained.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
          )
    else { return zeroed.image }
    return UIImage(cgImage: cg)
  }

  private func withZeroGrain(_ r: CameraRecipe) -> CameraRecipe {
    CameraRecipe(
      id: r.id, engineClass: r.engineClass, lutName: r.lutName,
      postLUTExposure: r.postLUTExposure, postLUTSaturation: r.postLUTSaturation,
      postLUTContrast: r.postLUTContrast, postLUTMatrix: r.postLUTMatrix,
      referenceSpatial: r.referenceSpatial, exposureBias: r.exposureBias,
      adaptiveExposure: r.adaptiveExposure, warmth: r.warmth, saturation: r.saturation,
      contrast: r.contrast, shadowLift: r.shadowLift,
      highlightCompression: r.highlightCompression, vignette: r.vignette,
      bloom: r.bloom, grain: 0, grainSize: r.grainSize,
      monochrome: r.monochrome, protectsFaces: r.protectsFaces,
      preservesWarmCast: r.preservesWarmCast, decisionVocabulary: r.decisionVocabulary,
      flashPhysics: r.flashPhysics, sourceBloom: r.sourceBloom, keyShadow: r.keyShadow,
      gainDrivenGrain: r.gainDrivenGrain, nightReciprocity: r.nightReciprocity,
      ccdClip: r.ccdClip, highlightSmear: r.highlightSmear,
      highlightSmearDarkOnly: r.highlightSmearDarkOnly,
      rimLight: r.rimLight, skinProtect: r.skinProtect, skyResponse: r.skyResponse
    )
  }

  private func centerCrop(_ image: UIImage, side: CGFloat = 512) -> UIImage {
    guard let cg = image.cgImage else { return image }
    let w = CGFloat(cg.width)
    let h = CGFloat(cg.height)
    let s = min(side, w, h)
    let rect = CGRect(
      x: ((w - s) / 2).rounded(), y: ((h - s) / 2).rounded(), width: s, height: s
    )
    guard let cropped = cg.cropping(to: rect) else { return image }
    return UIImage(cgImage: cropped)
  }

  private func sideBySide(_ left: UIImage, _ right: UIImage) -> UIImage {
    guard let leftCG = left.cgImage, let rightCG = right.cgImage else { return left }
    let size = CGSize(
      width: leftCG.width + rightCG.width,
      height: max(leftCG.height, rightCG.height)
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    // UIImage.draw is UIKit-coordinate aware; raw CGContext.draw renders
    // both panes upside down (same fix as the parity evidence writer)
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      UIImage(cgImage: leftCG).draw(
        in: CGRect(x: 0, y: 0, width: leftCG.width, height: leftCG.height)
      )
      UIImage(cgImage: rightCG).draw(
        in: CGRect(x: leftCG.width, y: 0, width: rightCG.width, height: rightCG.height)
      )
    }
  }
}
