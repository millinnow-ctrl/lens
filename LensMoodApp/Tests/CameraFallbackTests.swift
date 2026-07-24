import XCTest
@testable import LensMood

/// Without camera hardware (Simulator / CI) the shutter substitutes the loaded
/// film's test plate. These tests pin down that the zoom and flip controls
/// still change that photograph — no dead buttons on the simulator.
final class CameraFallbackTests: XCTestCase {
  private func plate() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { ctx in
      UIColor.red.setFill()
      ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
      UIColor.blue.setFill()
      ctx.fill(CGRect(x: 200, y: 0, width: 200, height: 300))
    }
  }

  func testZoomCropsTheCenterOfTheTestPlate() {
    let image = plate()
    let zoomed = CameraController.fallbackFrame(from: image, zoom: 2, mirrored: false)
    XCTAssertEqual(Double(zoomed.size.width), Double(image.size.width) / 2, accuracy: 1)
    XCTAssertEqual(Double(zoomed.size.height), Double(image.size.height) / 2, accuracy: 1)
  }

  func testOneXIsUntouchedAndFlipMirrors() {
    let image = plate()
    let untouched = CameraController.fallbackFrame(from: image, zoom: 1, mirrored: false)
    XCTAssertEqual(untouched.size, image.size)
    XCTAssertEqual(untouched.imageOrientation, image.imageOrientation)

    let mirrored = CameraController.fallbackFrame(from: image, zoom: 1, mirrored: true)
    XCTAssertEqual(mirrored.imageOrientation, .upMirrored)
  }

  func testFiveXStaysInsideTheFrame() {
    let image = plate()
    let zoomed = CameraController.fallbackFrame(from: image, zoom: 5, mirrored: true)
    XCTAssertGreaterThan(zoomed.size.width, 0)
    XCTAssertLessThan(Double(zoomed.size.width), Double(image.size.width) / 4)
    XCTAssertEqual(zoomed.imageOrientation, .upMirrored)
  }
}
