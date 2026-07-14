import CoreImage
import XCTest
@testable import LensMood

/// Logic-level contract for the reusable-mask layer. We intentionally do not
/// assert Vision ML results here (they need real images/hardware and would be
/// flaky in the simulator); those are validated on device. This pins the cheap,
/// deterministic guarantees: the `.none` fast path never touches Vision, the
/// `requested` set is honoured, and the mask taxonomy is correct.
final class SegmentationServiceTests: XCTestCase {

  private func solidImage(_ side: Int = 8) -> UIImage {
    let size = CGSize(width: side, height: side)
    return UIGraphicsImageRenderer(size: size).image { ctx in
      UIColor.gray.setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
    }
  }

  func testNoneRequestReturnsEmptyWithoutVision() {
    let masks = SegmentationService.shared.masks(for: solidImage(), key: "k-none", needs: .none)
    XCTAssertNil(masks.person)
    XCTAssertNil(masks.saliency)
    XCTAssertNil(masks.skinHint)
    XCTAssertNil(masks.skyHint)
    XCTAssertTrue(masks.faces.isEmpty)
    XCTAssertTrue(masks.textRegions.isEmpty)
    XCTAssertEqual(masks.requested, .none)
  }

  func testEmptyFactoryInvariants() {
    let e = PhotoMasks.empty(requested: .portrait)
    XCTAssertNil(e.person)
    XCTAssertTrue(e.faces.isEmpty)
    XCTAssertEqual(e.requested, .portrait)
  }

  func testPortraitTaxonomy() {
    XCTAssertTrue(MaskRequirement.portrait.contains(.person))
    XCTAssertTrue(MaskRequirement.portrait.contains(.face))
    XCTAssertTrue(MaskRequirement.portrait.contains(.skin))
    XCTAssertFalse(MaskRequirement.portrait.contains(.sky))
    XCTAssertFalse(MaskRequirement.portrait.contains(.text))
  }

  func testComputeIsResilientAndTagsRequestedSet() {
    // On a tiny solid image Vision finds nothing; compute must still return a
    // well-formed bundle tagged with exactly what was asked for (never crash,
    // never mislabel). This exercises the real code path defensively.
    let masks = SegmentationService.shared.masks(for: solidImage(), key: "k-text", needs: .text)
    XCTAssertEqual(masks.requested, .text)
    // No text in a gray square.
    XCTAssertTrue(masks.textRegions.isEmpty)
  }

  func testFaceRegionValueType() {
    let f = FaceRegion(bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.3),
                       leftEye: CGPoint(x: 0.2, y: 0.3), rightEye: nil, mouth: nil, confidence: 0.9)
    XCTAssertEqual(f.bounds.width, 0.3, accuracy: 0.0001)
    XCTAssertEqual(f.leftEye?.x ?? 0, 0.2, accuracy: 0.0001)
  }
}
