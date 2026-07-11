import CoreImage
import CoreGraphics
import UIKit

enum SceneAnalysisError: LocalizedError {
  case unreadableImage
  case renderFailed

  var errorDescription: String? {
    switch self {
    case .unreadableImage: return "The photograph could not be decoded."
    case .renderFailed: return "The photograph could not be analyzed."
    }
  }
}

final class SceneAnalyzer {
  private let context: CIContext
  private let sampleSize = 64

  init(context: CIContext) {
    self.context = context
  }

  func analyze(_ image: CIImage) throws -> SceneProfile {
    let source = image.orientedForDisplay
    guard !source.extent.isEmpty else { throw SceneAnalysisError.unreadableImage }

    let scale = min(
      CGFloat(sampleSize) / source.extent.width,
      CGFloat(sampleSize) / source.extent.height
    )
    let resized = source
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
      .cropped(to: CGRect(
        x: 0,
        y: 0,
        width: max(1, floor(source.extent.width * scale)),
        height: max(1, floor(source.extent.height * scale))
      ))

    let width = Int(resized.extent.width)
    let height = Int(resized.extent.height)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw SceneAnalysisError.renderFailed
    }
    context.render(
      resized,
      toBitmap: &pixels,
      rowBytes: width * 4,
      bounds: resized.extent,
      format: .RGBA8,
      colorSpace: colorSpace
    )

    var histogram = [Int](repeating: 0, count: 256)
    var sumLuminance = 0.0
    var sumRed = 0.0
    var sumGreen = 0.0
    var sumBlue = 0.0
    var sumSaturation = 0.0
    var shadowCount = 0
    var highlightCount = 0
    let count = max(1, width * height)

    for index in stride(from: 0, to: pixels.count, by: 4) {
      let red = Double(pixels[index]) / 255
      let green = Double(pixels[index + 1]) / 255
      let blue = Double(pixels[index + 2]) / 255
      let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
      let bin = min(255, max(0, Int((luminance * 255).rounded())))
      histogram[bin] += 1
      sumLuminance += luminance
      sumRed += red
      sumGreen += green
      sumBlue += blue
      let maximum = max(red, max(green, blue))
      let minimum = min(red, min(green, blue))
      sumSaturation += maximum == 0 ? 0 : (maximum - minimum) / maximum
      if luminance < 0.12 { shadowCount += 1 }
      if luminance > 0.92 { highlightCount += 1 }
    }

    let p01 = percentile(0.01, histogram: histogram, count: count)
    let median = percentile(0.50, histogram: histogram, count: count)
    let p99 = percentile(0.99, histogram: histogram, count: count)
    let mean = sumLuminance / Double(count)
    let averageRed = sumRed / Double(count)
    let averageGreen = sumGreen / Double(count)
    let averageBlue = sumBlue / Double(count)
    let warmth = (averageRed - averageBlue).clamped(to: -0.35...0.35)

    return SceneProfile(
      meanLuminance: mean,
      medianLuminance: median,
      shadowFraction: Double(shadowCount) / Double(count),
      highlightFraction: Double(highlightCount) / Double(count),
      dynamicRange: max(0, p99 - p01),
      averageRed: averageRed,
      averageGreen: averageGreen,
      averageBlue: averageBlue,
      saturation: sumSaturation / Double(count),
      warmth: warmth,
      isLowKey: median < 0.30,
      isHighKey: median > 0.68,
      isBacklit: mean > 0.48 && Double(shadowCount) / Double(count) > 0.30
    )
  }

  private func percentile(_ value: Double, histogram: [Int], count: Int) -> Double {
    let target = Int((Double(count - 1) * value).rounded())
    var cumulative = 0
    for (index, amount) in histogram.enumerated() {
      cumulative += amount
      if cumulative > target { return Double(index) / 255 }
    }
    return 1
  }
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(range.upperBound, max(range.lowerBound, self))
  }
}

extension CIImage {
  var orientedForDisplay: CIImage {
    let origin = extent.origin
    return transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
  }
}
