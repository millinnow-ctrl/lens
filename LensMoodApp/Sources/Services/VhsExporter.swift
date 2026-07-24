import AVFoundation
import CoreImage
import UIKit

enum VhsError: LocalizedError {
  case badInput(String)
  case exportFailed(String)

  var errorDescription: String? {
    switch self {
    case .badInput(let message): return message
    case .exportFailed(let message): return message
    }
  }
}

final class VhsExporter {
  static func export(
    videoURL: URL,
    lutData: Data? = nil,
    lutDimension: Int = 33
  ) async throws -> URL {
    let asset = AVURLAsset(url: videoURL)
    guard asset.tracks(withMediaType: .video).first != nil else {
      throw VhsError.badInput("That file has no video track.")
    }

    let cube: CIFilter?
    if let lutData {
      let expected = lutDimension * lutDimension * lutDimension * 4 * MemoryLayout<Float32>.size
      guard lutData.count == expected else {
        throw VhsError.badInput("The tape color profile is invalid.")
      }
      cube = CIFilter(name: "CIColorCube", parameters: [
        "inputCubeDimension": lutDimension,
        "inputCubeData": lutData,
      ])
    } else {
      cube = nil
    }

    guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else {
      throw VhsError.exportFailed("Core Image is unavailable.")
    }

    let composition = AVMutableVideoComposition(asset: asset) { request in
      let extent = request.sourceImage.extent
      var image = request.sourceImage.clampedToExtent()

      if let cube {
        cube.setValue(image, forKey: kCIInputImageKey)
        image = cube.outputImage ?? image
      } else {
        // Authored tape response used until a measured temporal profile replaces it.
        image = image
          .applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.78,
            kCIInputContrastKey: 0.94,
            kCIInputBrightnessKey: 0.02,
          ])
          .applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.91, y: 0.06, z: 0.03, w: 0),
            "inputGVector": CIVector(x: 0.05, y: 0.90, z: 0.05, w: 0),
            "inputBVector": CIVector(x: 0.08, y: 0.09, z: 0.83, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
          ])
      }

      image = image.applyingFilter("CIVignette", parameters: [
        kCIInputIntensityKey: 0.72,
        kCIInputRadiusKey: min(extent.width, extent.height) * 0.75,
      ])

      let seconds = CMTimeGetSeconds(request.compositionTime)
      let flicker = 0.045 * sin(seconds * 2.4) * (0.6 + 0.4 * sin(seconds * 0.7))
      image = image.applyingFilter("CIExposureAdjust", parameters: [
        kCIInputEVKey: flicker,
      ])

      let step = floor(seconds * 12)
      let jump = CGFloat(fmod(step * 83, 293))
      let grain = noise
        .transformed(by: CGAffineTransform(translationX: -jump * 3.1, y: -jump * 1.7))
        .applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: 0.20, y: 0.20, z: 0.20, w: 0),
          "inputGVector": CIVector(x: 0.20, y: 0.20, z: 0.20, w: 0),
          "inputBVector": CIVector(x: 0.20, y: 0.20, z: 0.20, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
          "inputBiasVector": CIVector(x: -0.10, y: -0.10, z: -0.10, w: 0.11),
        ])
      image = grain.composited(over: image)

      let overlay = tapeOverlay(
        seconds: max(0, Int(seconds)),
        blink: fmod(seconds, 1.2) < 0.6,
        extent: extent
      )
      image = overlay.composited(over: image)
      request.finish(with: image.cropped(to: extent), context: nil)
    }

    guard let session = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPresetHighestQuality
    ) else {
      throw VhsError.exportFailed("The tape deck could not start.")
    }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("lensmood-tape-\(UUID().uuidString).mp4")
    session.outputURL = outputURL
    session.outputFileType = .mp4
    session.videoComposition = composition
    session.shouldOptimizeForNetworkUse = true

    return try await withCheckedThrowingContinuation { continuation in
      session.exportAsynchronously {
        switch session.status {
        case .completed:
          continuation.resume(returning: outputURL)
        case .cancelled:
          continuation.resume(throwing: CancellationError())
        default:
          continuation.resume(throwing: VhsError.exportFailed(
            session.error?.localizedDescription ?? "Tape export failed."
          ))
        }
      }
    }
  }

  private static func tapeOverlay(seconds: Int, blink: Bool, extent: CGRect) -> CIImage {
    let width = extent.width
    let height = extent.height
    let fontSize = max(18, height * 0.042)
    let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
    let cream = UIColor(red: 1, green: 0.94, blue: 0.86, alpha: 0.94)

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
    let uiImage = renderer.image { context in
      context.cgContext.setShadow(
        offset: CGSize(width: 0, height: 1),
        blur: 3,
        color: UIColor.black.withAlphaComponent(0.58).cgColor
      )
      let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: cream,
      ]
      let minutes = seconds / 60
      let remainingSeconds = seconds % 60
      String(format: "0:%02d:%02d", minutes, remainingSeconds)
        .draw(at: CGPoint(x: width * 0.06, y: height * 0.90), withAttributes: attributes)

      let recordColor = UIColor(red: 0.88, green: 0.15, blue: 0.11, alpha: 0.95)
      let recordAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: blink ? recordColor : cream,
      ]
      (blink ? "● REC" : "  REC")
        .draw(at: CGPoint(x: width * 0.06, y: height * 0.06), withAttributes: recordAttributes)
    }
    guard let cgImage = uiImage.cgImage else { return CIImage.empty() }
    return CIImage(cgImage: cgImage)
  }
}
