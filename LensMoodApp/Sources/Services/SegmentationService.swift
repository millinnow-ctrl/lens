import CoreImage
import UIKit
import Vision

/// Precomputes the reusable per-photo analysis masks that subject-aware lens
/// passes consume — computed **once per photo** and cached for the editing
/// session, instead of the audit's "recompute Vision on every develop".
///
/// Layer 2 of the architecture: Apple Vision where it already solves the
/// problem (person segmentation, face landmarks, saliency, text) plus honestly
/// labelled heuristics where no reliable on-device API exists yet (skin, sky).
/// No custom Core ML model is required for any of this.
struct PhotoMasks {
  /// 0…1 subject alpha (people cut-out). Vision person segmentation.
  var person: CIImage?
  /// Detected faces with landmark regions, normalized top-left origin.
  var faces: [FaceRegion]
  /// Attention-based saliency heat (where the eye goes). Useful for
  /// subject-centred vignette / local contrast.
  var saliency: CIImage?
  /// Text bounding boxes (normalized, top-left origin) to protect signs/captions
  /// from distortion.
  var textRegions: [CGRect]
  /// Skin approximation. TODO(learned): true skin segmentation is a future
  /// compact model; today this is the face-region ∩ person hint, documented as
  /// an approximation so callers don't over-trust it.
  var skinHint: CIImage?
  /// Sky approximation via foreground-inverse (iOS 17+ only); `nil` otherwise —
  /// we do not fake a sky mask when no reliable API is available.
  var skyHint: CIImage?

  /// Which masks this bundle was actually asked to compute.
  var requested: MaskRequirement

  static func empty(requested: MaskRequirement = .none) -> PhotoMasks {
    PhotoMasks(person: nil, faces: [], saliency: nil, textRegions: [], skinHint: nil, skyHint: nil, requested: requested)
  }
}

/// A face with its key landmark regions, normalized to the image with a
/// top-left origin (matching how the rest of the app reasons about rects).
struct FaceRegion: Equatable {
  let bounds: CGRect
  let leftEye: CGPoint?
  let rightEye: CGPoint?
  let mouth: CGPoint?
  let confidence: Float
}

final class SegmentationService {
  static let shared = SegmentationService()

  private let cache = MaskCache()

  /// Reusable masks for a photo. Cheap for `.none` (returns immediately without
  /// touching Vision). Cached by (photo key, requested set) so switching lenses
  /// that need the same masks pays the Vision cost at most once.
  func masks(for image: UIImage, key: String, needs: MaskRequirement) -> PhotoMasks {
    guard needs != .none else { return .empty() }
    if let hit = cache.value(forKey: key, needs: needs) { return hit }
    let computed = compute(image, needs: needs)
    cache.insert(computed, forKey: key, needs: needs)
    return computed
  }

  /// Precompute in the background right after import so the first lens preview
  /// doesn't wait on Vision. Fire-and-forget.
  func prewarm(_ image: UIImage, key: String, needs: MaskRequirement) {
    guard needs != .none else { return }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      _ = self?.masks(for: image, key: key, needs: needs)
    }
  }

  func clearCache() { cache.removeAll() }

  // MARK: - Vision compute

  private func compute(_ image: UIImage, needs: MaskRequirement) -> PhotoMasks {
    guard let cgImage = image.cgImage else { return .empty(requested: needs) }
    let orientation = CGImagePropertyOrientation(image.imageOrientation)

    var requests: [VNRequest] = []

    let faceRequest: VNDetectFaceLandmarksRequest? = needs.contains(.face) || needs.contains(.skin)
      ? VNDetectFaceLandmarksRequest() : nil
    if let faceRequest { requests.append(faceRequest) }

    let personRequest: VNGeneratePersonSegmentationRequest?
    if needs.contains(.person) || needs.contains(.skin) {
      let r = VNGeneratePersonSegmentationRequest()
      r.qualityLevel = .balanced
      r.outputPixelFormat = kCVPixelFormatType_OneComponent8
      personRequest = r
      requests.append(r)
    } else { personRequest = nil }

    let attentionRequest: VNGenerateAttentionBasedSaliencyImageRequest? =
      needs.contains(.face) || needs.contains(.person) ? VNGenerateAttentionBasedSaliencyImageRequest() : nil
    if let attentionRequest { requests.append(attentionRequest) }

    let textRequest: VNRecognizeTextRequest?
    if needs.contains(.text) {
      let r = VNRecognizeTextRequest()
      r.recognitionLevel = .fast
      r.usesLanguageCorrection = false
      textRequest = r
      requests.append(r)
    } else { textRequest = nil }

    // iOS 17+ foreground-instance mask → sky ≈ inverse of foreground.
    var foregroundRequest: VNImageBasedRequest?
    if needs.contains(.sky), #available(iOS 17.0, *) {
      let r = VNGenerateForegroundInstanceMaskRequest()
      foregroundRequest = r
      requests.append(r)
    }

    guard !requests.isEmpty else { return .empty(requested: needs) }

    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
    do { try handler.perform(requests) } catch { return .empty(requested: needs) }

    var masks = PhotoMasks.empty(requested: needs)

    if let faces = faceRequest?.results {
      masks.faces = faces.map { obs in
        let b = obs.boundingBox
        let landmarks = obs.landmarks
        return FaceRegion(
          bounds: CGRect(x: b.origin.x, y: 1 - b.origin.y - b.height, width: b.width, height: b.height),
          leftEye: Self.centroid(landmarks?.leftEye, in: b),
          rightEye: Self.centroid(landmarks?.rightEye, in: b),
          mouth: Self.centroid(landmarks?.outerLips, in: b),
          confidence: obs.confidence
        )
      }
    }

    if let buffer = personRequest?.results?.first?.pixelBuffer {
      let personCI = CIImage(cvPixelBuffer: buffer)
      if needs.contains(.person) { masks.person = personCI }
      if needs.contains(.skin) { masks.skinHint = personCI } // documented approximation
    }

    if let sal = attentionRequest?.results?.first as? VNSaliencyImageObservation {
      masks.saliency = CIImage(cvPixelBuffer: sal.pixelBuffer)
    }

    if let text = textRequest?.results {
      masks.textRegions = text.map { obs in
        let b = obs.boundingBox
        return CGRect(x: b.origin.x, y: 1 - b.origin.y - b.height, width: b.width, height: b.height)
      }
    }

    if #available(iOS 17.0, *), let fg = foregroundRequest as? VNGenerateForegroundInstanceMaskRequest,
       let result = fg.results?.first {
      if let buffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) {
        // Foreground alpha; sky ≈ inverse (the engine inverts when grading).
        // The Vision buffer is FULL-RESOLUTION Float32 (~46MB at 12MP) — bound
        // it before it enters the cache, or six cached photos hold ~280MB.
        let raw = CIImage(cvPixelBuffer: buffer)
        let largest = max(raw.extent.width, raw.extent.height)
        let scale = min(1, 1024 / max(largest, 1))
        masks.skyHint = scale < 1
          ? raw.applyingFilter("CILanczosScaleTransform", parameters: [
              kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1,
            ])
          : raw
      }
    }

    return masks
  }

  /// Average of a landmark region's points, mapped into image space (top-left
  /// origin), or nil when the region is absent.
  private static func centroid(_ region: VNFaceLandmarkRegion2D?, in faceBox: CGRect) -> CGPoint? {
    guard let region, region.pointCount > 0 else { return nil }
    let pts = region.normalizedPoints
    var sx: CGFloat = 0, sy: CGFloat = 0
    for p in pts { sx += CGFloat(p.x); sy += CGFloat(p.y) }
    let n = CGFloat(pts.count)
    // Landmark points are normalized within the face box, bottom-left origin.
    let fx = faceBox.origin.x + (sx / n) * faceBox.width
    let fyBottom = faceBox.origin.y + (sy / n) * faceBox.height
    return CGPoint(x: fx, y: 1 - fyBottom)
  }
}

// MARK: - Cache

/// Small bounded cache keyed by (photo key, requested mask set). Keeps the last
/// few photos' masks so lens browsing reuses them; evicts oldest beyond the cap.
private final class MaskCache {
  private struct Key: Hashable { let photo: String; let needs: Int }
  private let lock = NSLock()
  private var store: [Key: PhotoMasks] = [:]
  private var order: [Key] = []
  private let capacity = 6

  func value(forKey photo: String, needs: MaskRequirement) -> PhotoMasks? {
    lock.lock(); defer { lock.unlock() }
    return store[Key(photo: photo, needs: needs.rawValue)]
  }

  func insert(_ masks: PhotoMasks, forKey photo: String, needs: MaskRequirement) {
    lock.lock(); defer { lock.unlock() }
    let key = Key(photo: photo, needs: needs.rawValue)
    if store[key] == nil { order.append(key) }
    store[key] = masks
    while order.count > capacity {
      let evict = order.removeFirst()
      store[evict] = nil
    }
  }

  func removeAll() {
    lock.lock(); defer { lock.unlock() }
    store.removeAll(); order.removeAll()
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
