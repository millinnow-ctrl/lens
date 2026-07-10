import ExpoModulesCore
import AVFoundation
import CoreImage
import UIKit

/**
 * Bakes the LensMood camcorder look into a real video file.
 *
 * The color grade arrives as a CIColorCube LUT computed in JS from the same
 * `vhsGrade` function that drives the live Skia preview, so the exported tape
 * matches what the user watched. Grain, vignette and the counting REC timecode
 * are composited per frame with Core Image inside an AVMutableVideoComposition;
 * audio passes through untouched.
 */
public class VhsExportModule: Module {
  public func definition() -> ModuleDefinition {
    Name("VhsExport")

    AsyncFunction("exportVideo") { (videoUri: String, lutBase64: String, lutDim: Int, promise: Promise) in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let out = try VhsExporter.export(videoUri: videoUri, lutBase64: lutBase64, lutDim: lutDim)
          promise.resolve(out.absoluteString)
        } catch {
          promise.reject("E_VHS_EXPORT", error.localizedDescription)
        }
      }
    }
  }
}

enum VhsError: LocalizedError {
  case badInput(String)
  case exportFailed(String)

  var errorDescription: String? {
    switch self {
    case .badInput(let m): return m
    case .exportFailed(let m): return m
    }
  }
}

final class VhsExporter {
  static func export(videoUri: String, lutBase64: String, lutDim: Int) throws -> URL {
    guard let srcURL = URL(string: videoUri) else {
      throw VhsError.badInput("Bad video uri.")
    }
    guard let lutData = Data(base64Encoded: lutBase64),
          lutData.count == lutDim * lutDim * lutDim * 4 * MemoryLayout<Float32>.size else {
      throw VhsError.badInput("Bad LUT data.")
    }

    let asset = AVURLAsset(url: srcURL)
    guard asset.tracks(withMediaType: .video).first != nil else {
      throw VhsError.badInput("That file has no video track.")
    }

    let cube = CIFilter(name: "CIColorCube", parameters: [
      "inputCubeDimension": lutDim,
      "inputCubeData": lutData,
    ])
    guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else {
      throw VhsError.exportFailed("Core Image unavailable.")
    }

    let composition = AVMutableVideoComposition(asset: asset) { request in
      let extent = request.sourceImage.extent
      var img = request.sourceImage.clampedToExtent()

      // 1 — the tape color grade (LUT from vhsGrade)
      if let cube = cube {
        cube.setValue(img, forKey: kCIInputImageKey)
        img = cube.outputImage ?? img
      }

      // 2 — gentle tube vignette
      if let vig = CIFilter(name: "CIVignette", parameters: [
        kCIInputImageKey: img,
        "inputIntensity": 0.9,
        "inputRadius": 1.6,
      ])?.outputImage {
        img = vig
      }

      let t = CMTimeGetSeconds(request.compositionTime)

      // 3 — tape grain: random field, re-seeded per frame by translation,
      //     softened to luminance-only speckle and overlaid faintly
      let jump = CGFloat(fmod(t * 997.0, 293.0))
      let grainField = noise
        .transformed(by: CGAffineTransform(translationX: -jump * 3.1, y: -jump * 1.7))
        .applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: 0.22, y: 0.22, z: 0.22, w: 0),
          "inputGVector": CIVector(x: 0.22, y: 0.22, z: 0.22, w: 0),
          "inputBVector": CIVector(x: 0.22, y: 0.22, z: 0.22, w: 0),
          "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
          "inputBiasVector": CIVector(x: -0.11, y: -0.11, z: -0.11, w: 0.09),
        ])
      img = grainField.composited(over: img)

      // 4 — burned-in REC + counting timecode
      let overlay = Self.tapeOverlay(seconds: Int(t), blink: fmod(t, 1.2) < 0.6, extent: extent)
      img = overlay.composited(over: img)

      request.finish(with: img.cropped(to: extent), context: nil)
    }

    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
      throw VhsError.exportFailed("Could not start the export.")
    }
    let outURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("lensmood-tape-\(UUID().uuidString).mp4")
    session.outputURL = outURL
    session.outputFileType = .mp4
    session.videoComposition = composition
    session.shouldOptimizeForNetworkUse = true

    let semaphore = DispatchSemaphore(value: 0)
    session.exportAsynchronously { semaphore.signal() }
    semaphore.wait()

    if session.status != .completed {
      throw VhsError.exportFailed(session.error?.localizedDescription ?? "Export failed.")
    }
    return outURL
  }

  /** "● REC" top-left + "0:00:SS" bottom-left, rendered as a CIImage overlay */
  private static func tapeOverlay(seconds: Int, blink: Bool, extent: CGRect) -> CIImage {
    let w = extent.width
    let h = extent.height
    let fontSize = max(18, h * 0.042)
    let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
    let cream = UIColor(red: 1.0, green: 0.94, blue: 0.86, alpha: 0.95)

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
    let ui = renderer.image { ctx in
      ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                              color: UIColor.black.withAlphaComponent(0.6).cgColor)
      let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: cream]

      // counting timecode, bottom-left (UIKit origin is top-left)
      let m = seconds / 60
      let s = seconds % 60
      let tc = String(format: "0:%02d:%02d", m, s)
      tc.draw(at: CGPoint(x: w * 0.06, y: h * 0.90), withAttributes: attrs)

      // blinking ● REC, top-left
      if blink {
        let recAttrs: [NSAttributedString.Key: Any] = [
          .font: font,
          .foregroundColor: UIColor(red: 0.88, green: 0.15, blue: 0.11, alpha: 0.95),
        ]
        "\u{25CF} REC".draw(at: CGPoint(x: w * 0.06, y: h * 0.06), withAttributes: recAttrs)
      } else {
        "  REC".draw(at: CGPoint(x: w * 0.06, y: h * 0.06), withAttributes: attrs)
      }
    }
    guard let cg = ui.cgImage else { return CIImage.empty() }
    // CIImage(cgImage:) preserves visual orientation — REC stays top-left
    return CIImage(cgImage: cg)
  }
}
