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

struct SubjectAnalysis {
  let faces: [FaceProfile]
  let personMask: CIImage?
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
      // R63 (owner-directed): the develop path is not real-time — spend the
      // Neural Engine time on the accurate model so mask edges (hair, hands)
      // hold up under the flash-falloff and subject-aware passes.
      request.qualityLevel = .accurate
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
