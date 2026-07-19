import CoreImage
import ImageIO
import UIKit
import Vision

enum VisionError: LocalizedError {
  case unreadableImage

  var errorDescription: String? {
    "The photograph could not be prepared for subject analysis."
  }
}

/// The masked-light masks in the raw, serializable form they were built from:
/// the exact L8 bytes `FilmEngine.attachLightMasks` materialized each mask
/// CIImage out of, at the shared analysis resolution (≤512 px long edge). A
/// reading carries this so it can be frozen beside its developed frame and
/// replayed byte-for-byte on a later develop — Vision output is not guaranteed
/// bit-stable across separate runs (or OS updates), so a second read would
/// drift. The person matte is intentionally absent: only these three derived
/// masks have committed byte arrays that round-trip losslessly, and the flash
/// near-field falls back to the (persisted) faces when no person matte exists.
struct SubjectMaskRaster: Equatable {
  let width: Int
  let height: Int
  let subjectMatte: [UInt8]?
  let skinMask: [UInt8]?
  let skyMask: [UInt8]?
}

struct SubjectAnalysis {
  let faces: [FaceProfile]
  let personMask: CIImage?

  // R66 masked-light fields. All three are produced ONLY inside
  // `FilmEngine.read`'s subject pass (heuristics on a small analysis raster,
  // materialized to single-channel bytes at <=512 long edge) and upscaled
  // lazily where a pass uses them. A develop without a cached reading — or
  // with `analyzeSubjects: false` — carries nil masks, which switches the
  // masked passes structurally off.

  /// Cleaned subject silhouette (largest connected component, holes filled)
  /// that the rim-halation pass traces. The raw Vision matte keeps its holes
  /// and spurs for the flash-falloff pass, whose behavior is already pinned.
  let subjectMatte: CIImage?
  /// Person matte intersected with tight skin chroma and a luma window,
  /// opened-then-closed, feathered — the skin-protection scope.
  let skinMask: CIImage?
  /// Chromatic-blue sky evidence (hue + low texture + top prior + not-subject,
  /// top-touching components only). nil when sky coverage is below the
  /// refusal threshold, so the sky pass cannot fire on skyless scenes.
  let skyMask: CIImage?

  /// The raw L8 bytes the three masks above were materialized from, kept only
  /// so a reading can be persisted and replayed later (see PersistedReading).
  /// The passes consume the CIImages above, never this — it is provenance for
  /// serialization, not a render input.
  let maskRaster: SubjectMaskRaster?

  init(
    faces: [FaceProfile],
    personMask: CIImage?,
    subjectMatte: CIImage? = nil,
    skinMask: CIImage? = nil,
    skyMask: CIImage? = nil,
    maskRaster: SubjectMaskRaster? = nil
  ) {
    self.faces = faces
    self.personMask = personMask
    self.subjectMatte = subjectMatte
    self.skinMask = skinMask
    self.skyMask = skyMask
    self.maskRaster = maskRaster
  }
}

final class VisionService {
  static func analyze(_ image: UIImage, includePersonMask: Bool = false) throws -> SubjectAnalysis {
    guard let cgImage = image.cgImage else { throw VisionError.unreadableImage }
    let orientation = CGImagePropertyOrientation(image.imageOrientation)

    let faceRequest = VNDetectFaceRectanglesRequest()
    var requests: [VNRequest] = [faceRequest]
    let maskRequest: VNGeneratePersonSegmentationRequest?
    if includePersonMask {
      let request = VNGeneratePersonSegmentationRequest()
      // R63 tried .accurate (owner accepts the Neural Engine time), but CI
      // measured it NONDETERMINISTIC: the three render-twice-compare-bytes
      // suites failed only on Vision-mask paths. Determinism (same photo →
      // same develop, byte-for-byte) is a core engine guarantee, so .balanced
      // stays until .accurate proves reproducible on real hardware.
      request.qualityLevel = .balanced
      request.outputPixelFormat = kCVPixelFormatType_OneComponent8
      requests.append(request)
      maskRequest = request
    } else {
      maskRequest = nil
    }

    let handler = VNImageRequestHandler(
      cgImage: cgImage,
      orientation: orientation,
      options: [:]
    )
    try handler.perform(requests)

    let faces = (faceRequest.results ?? []).enumerated().map { index, face in
      let bounds = face.boundingBox
      return FaceProfile(
        id: index,
        bounds: CGRect(
          x: bounds.origin.x,
          y: 1 - bounds.origin.y - bounds.height,
          width: bounds.width,
          height: bounds.height
        ),
        confidence: face.confidence
      )
    }

    let mask: CIImage?
    if let buffer = maskRequest?.results?.first?.pixelBuffer {
      mask = CIImage(cvPixelBuffer: buffer)
    } else {
      mask = nil
    }

    return SubjectAnalysis(faces: faces, personMask: mask)
  }
}

private extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
