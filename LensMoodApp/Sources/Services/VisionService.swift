// Extracted from lensmood-native/modules/lensmood-vision (Expo wrapper removed).
// Apple Vision face detection + person segmentation, fully on-device.
// Compiled by SwiftUI CI; wired into FilmEngine in Phase B.

import Vision
import UIKit

enum VisionError: LocalizedError {
  case badInput(String)
  var errorDescription: String? {
    switch self {
    case .badInput(let m): return m
    }
  }
}

final class VisionService {
  private static func cgImage(from uri: String) throws -> CGImage {
    guard let url = URL(string: uri),
          let data = try? Data(contentsOf: url),
          let ui = UIImage(data: data),
          let cg = ui.cgImage else {
      throw VisionError.badInput("Could not read the image.")
    }
    return cg
  }

  /** VNDetectFaceRectangles → [{x, y, w, h}] normalized, top-left origin */
  static func detectFaces(uri: String) throws -> [[String: Double]] {
    let cg = try cgImage(from: uri)
    let request = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try handler.perform([request])
    let observations = request.results ?? []
    return observations.map { face in
      let bb = face.boundingBox // normalized, BOTTOM-left origin
      return [
        "x": Double(bb.origin.x),
        "y": Double(1.0 - bb.origin.y - bb.size.height), // → top-left origin
        "w": Double(bb.size.width),
        "h": Double(bb.size.height),
        "confidence": Double(face.confidence),
      ]
    }
  }

  /** VNGeneratePersonSegmentation → small grayscale PNG (base64) + dims */
  static func personMask(uri: String) throws -> [String: Any]? {
    let cg = try cgImage(from: uri)
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .balanced
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try handler.perform([request])
    guard let result = request.results?.first else { return nil }
    let buffer = result.pixelBuffer

    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

    guard let ctx = CGContext(
      data: base,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ), let maskCG = ctx.makeImage() else { return nil }

    let png = UIImage(cgImage: maskCG).pngData()
    guard let png else { return nil }
    return [
      "maskBase64": png.base64EncodedString(),
      "width": width,
      "height": height,
    ]
  }
}
