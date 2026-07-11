import CoreImage
import Foundation

enum LUTLoaderError: LocalizedError {
  case missing(String)
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .missing(let name): return "Camera color profile \(name) is missing."
    case .invalid(let name): return "Camera color profile \(name) is invalid."
    }
  }
}

final class LUTLoader {
  static let dimension = 33
  private var cache: [String: Data] = [:]
  private let lock = NSLock()

  func data(named name: String) throws -> Data {
    lock.lock()
    defer { lock.unlock() }
    if let cached = cache[name] { return cached }

    guard let url = Bundle.main.url(forResource: name, withExtension: "lut", subdirectory: "luts")
      ?? Bundle.main.url(forResource: name, withExtension: "lut") else {
      throw LUTLoaderError.missing(name)
    }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let expected = Self.dimension * Self.dimension * Self.dimension * 4 * MemoryLayout<Float32>.size
    guard data.count == expected else { throw LUTLoaderError.invalid(name) }
    cache[name] = data
    return data
  }

  func apply(named name: String, to image: CIImage) throws -> CIImage {
    let data = try data(named: name)
    guard let filter = CIFilter(name: "CIColorCube", parameters: [
      "inputCubeDimension": Self.dimension,
      "inputCubeData": data,
      kCIInputImageKey: image,
    ]), let output = filter.outputImage else {
      throw LUTLoaderError.invalid(name)
    }
    return output
  }
}
