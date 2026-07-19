import CoreImage
import UIKit
@testable import LensMood

/// Test infrastructure (no product change): CI runs on the iOS Simulator,
/// where Vision's person segmentation returns a degenerate near-zero matte, so
/// `buildSubjectMatte` correctly refuses and no CI render ever exercises the
/// masked-light passes end-to-end. This helper swaps a committed fixture matte
/// into the one place `read` would have used Vision's — everything downstream
/// (silhouette cleanup, skin mask, sky mask, the passes themselves) is the
/// real production code path.
enum MatteInjectionError: Error {
  case unreadableMatte(URL)
  case unreadableSource
}

enum MatteInjection {
  /// A SceneReading whose subject pass is driven by a committed fixture
  /// matte instead of the simulator's degenerate person segmentation.
  static func reading(
    source: UIImage, mattePNG url: URL, engine: FilmEngine
  ) throws -> SceneReading {
    let base = try engine.read(source, analyzeSubjects: false)
    guard let matte = CIImage(contentsOf: url) else {
      throw MatteInjectionError.unreadableMatte(url)
    }
    guard let oriented = CIImage(
      image: source,
      options: [.applyOrientationProperty: true]
    ) else {
      throw MatteInjectionError.unreadableSource
    }
    let injected = SubjectAnalysis(faces: [], personMask: matte)
    let subject = engine.attachLightMasks(to: injected, image: oriented.orientedForDisplay)
    return SceneReading(scene: base.scene, subject: subject)
  }
}
