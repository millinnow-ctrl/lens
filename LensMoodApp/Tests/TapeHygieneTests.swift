import XCTest
@testable import LensMood

/// The Tape tab's temp-file sweep feeds deletions, so its scope is pinned:
/// only LensMood's own tape temp files (the two lensmood- prefixes) are ever
/// candidates, and the working pair named in `keep` is never touched.
final class TapeHygieneTests: XCTestCase {
  func testSweepsOnlyLensmoodTapeFilesNotKept() {
    let names = [
      "lensmood-input-aaa.mov",
      "lensmood-tape-bbb.mp4",
      "lensmood-input-keep.mov",
      "lensmood-tape-keep.mp4",
      "com.apple.somethingelse.tmp",
      "user-export.mp4",
    ]
    let keep: Set<String> = ["lensmood-input-keep.mov", "lensmood-tape-keep.mp4"]
    XCTAssertEqual(
      CamcorderView.orphanedTapeNames(names, keeping: keep).sorted(),
      ["lensmood-input-aaa.mov", "lensmood-tape-bbb.mp4"]
    )
  }

  func testForeignTempFilesAreNeverCandidates() {
    let names = ["someone-elses.mov", "lensmood.mp4", "tape-lensmood-input-x.mov"]
    XCTAssertTrue(CamcorderView.orphanedTapeNames(names, keeping: []).isEmpty)
  }

  func testEmptyKeepSweepsAllLensmoodTapeTemps() {
    let names = ["lensmood-input-a.mov", "lensmood-tape-b.mp4"]
    XCTAssertEqual(CamcorderView.orphanedTapeNames(names, keeping: []), names)
  }
}
