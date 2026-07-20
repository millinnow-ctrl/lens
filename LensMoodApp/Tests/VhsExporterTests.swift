import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import UIKit
import XCTest
@testable import LensMood

/// End-to-end proof for the CAMCORDER VIDEO pipeline (R86).
///
/// CI has no camera hardware, so the record path is exercised with a
/// deterministic synthetic clip written by `AVAssetWriter` — a mid-gray field
/// with a moving bar (motion), plus a silent LPCM audio track — standing in for
/// what `VideoCameraPicker` hands `CamcorderView.adopt(input:)`. The REAL
/// `VhsExporter.export` (the same call `developTape` makes) then runs over it,
/// and we measure the output frames to prove the tape look engaged, the
/// timecode burned in, tracks survived, and the temp-file naming honors the
/// orphan-sweep contract.
///
/// Encoders are not byte-deterministic, so every assertion is structural or a
/// pixel measurement — never a byte compare.
final class VhsExporterTests: XCTestCase {

  // MARK: - Core proof: look engaged + timecode burned in

  func testExportAppliesVhsLookAndBurnsTimecode() async throws {
    let fps = 24
    let size = CGSize(width: 320, height: 240)
    let input = try await makeDeterministicClip(
      seconds: 2.0, fps: fps, size: size, withAudio: false
    )
    defer { try? FileManager.default.removeItem(at: input) }

    // The synthetic clip must look like a real recorder hand-off: one video
    // track, correct dimensions — exactly what the exporter's guard checks.
    let inAsset = AVURLAsset(url: input)
    XCTAssertNotNil(
      inAsset.tracks(withMediaType: .video).first,
      "synthetic input must carry a video track"
    )

    // Run the REAL exporter (developTape's call) with a hard timeout so a
    // wedged encoder fails loudly instead of hanging CI.
    let output = try await withExportTimeout(seconds: 180) {
      try await VhsExporter.export(videoURL: input)
    }
    defer { try? FileManager.default.removeItem(at: output) }

    // (4) Naming contract: the real export path is what the orphan sweep must
    // protect while a develop is in flight (the citizenship guard).
    XCTAssertTrue(
      output.lastPathComponent.hasPrefix("lensmood-tape-"),
      "export must use the lensmood-tape- prefix the sweep protects, got \(output.lastPathComponent)"
    )
    XCTAssertEqual(output.pathExtension, "mp4", "developed tape is an .mp4")

    // Output exists and is non-trivial (a real encoded clip, not a stub).
    let attrs = try FileManager.default.attributesOfItem(atPath: output.path)
    let bytes = (attrs[.size] as? Int) ?? 0
    XCTAssertGreaterThan(bytes, 10_000, "developed tape is implausibly small (\(bytes) bytes)")

    let outAsset = AVURLAsset(url: output)
    guard let outVideo = outAsset.tracks(withMediaType: .video).first else {
      return XCTFail("developed tape has no video track")
    }

    // Duration preserved within a frame or two of tolerance.
    XCTAssertEqual(
      CMTimeGetSeconds(outAsset.duration), 2.0, accuracy: 0.3,
      "developed tape duration drifted from the 2s source"
    )

    // naturalSize / transform sane.
    XCTAssertGreaterThan(outVideo.naturalSize.width, 0)
    XCTAssertGreaterThan(outVideo.naturalSize.height, 0)
    let tf = outVideo.preferredTransform
    XCTAssertTrue(tf.a != 0 || tf.b != 0, "video transform is degenerate")

    // Decode the same instant from input and output. Both must decode.
    let t = CMTime(seconds: 0.5, preferredTimescale: 600)
    let inFrame = try frame(from: input, at: t)
    let outFrame = try frame(from: output, at: t)
    XCTAssertEqual(inFrame.width, outFrame.width, "render size changed unexpectedly")
    XCTAssertEqual(inFrame.height, outFrame.height, "render size changed unexpectedly")

    let inR = try XCTUnwrap(ImageMetrics.raster(inFrame), "input frame did not rasterize")
    let outR = try XCTUnwrap(ImageMetrics.raster(outFrame), "output frame did not rasterize")

    // (2) The VHS look actually engaged: the frame changed materially. Color
    // grade + vignette + grain + overlay shift far more than encoder noise.
    let mae = try XCTUnwrap(ImageMetrics.meanAbsoluteError(inR, outR))
    XCTAssertGreaterThan(
      mae, 8.0,
      "developed frame barely differs from source (MAE \(mae)) — the tape look did not engage"
    )

    // (3) Timecode / REC overlay burned in: cream monospaced text renders in
    // the output that is absent from the source, and it is sparse (a compact
    // overlay, not a global color cast).
    let outCream = creamText(outR)
    let inCream = creamText(inR)
    XCTAssertGreaterThanOrEqual(
      outCream.count, 30,
      "no burned-in timecode/REC text found in the developed frame"
    )
    XCTAssertLessThan(
      outCream.fraction, 0.05,
      "cream pixels cover \(outCream.fraction) of the frame — that is a cast, not text"
    )
    XCTAssertLessThan(
      inCream.count, 5,
      "the source frame already contained cream text — the burn-in test is not isolating the overlay"
    )
  }

  // MARK: - Audio passthrough (record path captures sound)

  func testExportPreservesAudioTrackWhenInputHasOne() async throws {
    let input = try await makeDeterministicClip(
      seconds: 2.0, fps: 24, size: CGSize(width: 320, height: 240), withAudio: true
    )
    defer { try? FileManager.default.removeItem(at: input) }

    let inAsset = AVURLAsset(url: input)
    try XCTSkipUnless(
      inAsset.tracks(withMediaType: .audio).first != nil,
      "synthetic audio track was not written on this runner; audio passthrough not exercised"
    )

    let output = try await withExportTimeout(seconds: 180) {
      try await VhsExporter.export(videoURL: input)
    }
    defer { try? FileManager.default.removeItem(at: output) }

    let outAsset = AVURLAsset(url: output)
    XCTAssertNotNil(
      outAsset.tracks(withMediaType: .video).first,
      "developed tape lost its video track"
    )
    XCTAssertNotNil(
      outAsset.tracks(withMediaType: .audio).first,
      "input had audio but the developed tape has none — passthrough broke"
    )
    XCTAssertEqual(
      CMTimeGetSeconds(outAsset.duration), 2.0, accuracy: 0.3,
      "audio-bearing tape duration drifted"
    )
  }

  // MARK: - Bad input surfaces an error (B10 failure path honesty)

  func testExportRejectsFileWithoutVideoTrack() async throws {
    // A text file masquerading as a movie: no video track. The exporter must
    // throw (which developTape turns into the user-facing alert), not crash.
    let bogus = FileManager.default.temporaryDirectory
      .appendingPathComponent("lensmood-input-\(UUID().uuidString).mov")
    try Data("not a movie".utf8).write(to: bogus)
    defer { try? FileManager.default.removeItem(at: bogus) }

    do {
      _ = try await VhsExporter.export(videoURL: bogus)
      XCTFail("export should reject a file with no video track")
    } catch let error as VhsError {
      // Expected — a descriptive, user-presentable message.
      XCTAssertFalse(
        error.localizedDescription.isEmpty,
        "VhsError must carry a message developTape can show the user"
      )
    }
  }

  // MARK: - Lifecycle: orphan sweep honors the in-flight export (citizenship)

  func testOrphanSweepProtectsInFlightExportAndCollectsAbandoned() {
    // An export in flight: its lensmood-tape file is on disk before outputURL
    // publishes, so the sweep must never collect it while it is being kept.
    let inFlightTape = "lensmood-tape-inflight.mp4"
    let inFlightInput = "lensmood-input-inflight.mov"
    let keep: Set<String> = [inFlightTape, inFlightInput]

    let present = [
      inFlightTape,                       // being written right now — protect
      inFlightInput,                      // the working source — protect
      "lensmood-tape-abandoned.mp4",      // an earlier session's leftover — collect
      "lensmood-input-abandoned.mov",     // an earlier session's leftover — collect
      "IMG_0001.mov",                     // a user file — never a candidate
    ]

    let collected = Set(CamcorderView.orphanedTapeNames(present, keeping: keep))

    XCTAssertFalse(
      collected.contains(inFlightTape),
      "sweep would delete the in-flight export out from under the encoder"
    )
    XCTAssertFalse(
      collected.contains(inFlightInput),
      "sweep would delete the working source mid-develop"
    )
    XCTAssertTrue(collected.contains("lensmood-tape-abandoned.mp4"), "abandoned tape not collected")
    XCTAssertTrue(collected.contains("lensmood-input-abandoned.mov"), "abandoned input not collected")
    XCTAssertFalse(collected.contains("IMG_0001.mov"), "swept a non-LensMood user file")
  }

  // MARK: - Helpers

  /// Cream monospaced overlay text — warm, bright, mid-to-high blue. Distinct
  /// from the mid-gray field, the blue motion bar, and the low-amplitude grain.
  private func creamText(_ r: ImageMetrics.Raster) -> (count: Int, fraction: Double) {
    var count = 0
    var i = 0
    while i < r.px.count {
      let red = Int(r.px[i]), green = Int(r.px[i + 1]), blue = Int(r.px[i + 2])
      // r≥0.72, g≥0.62, 0.5≤b≤0.95, warm (r noticeably above b).
      if red >= 184, green >= 158, blue >= 128, blue <= 242, red - blue >= 10 {
        count += 1
      }
      i += 4
    }
    let total = max(1, r.count)
    return (count, Double(count) / Double(total))
  }

  /// Decode one exact frame (zero tolerance ⇒ deterministic timestamp).
  private func frame(from url: URL, at time: CMTime) throws -> CGImage {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try generator.copyCGImage(at: time, actualTime: nil)
  }

  /// Race the export against a timeout so a wedged encoder fails the test
  /// instead of hanging the CI job.
  private func withExportTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw VhsError.exportFailed("export exceeded \(Int(seconds))s timeout")
      }
      let result = try await group.next()!
      group.cancelAll()
      return result
    }
  }

  /// Write a deterministic H.264 clip (mid-gray field + a bar that marches
  /// left→right so real motion exists) to a lensmood-input- temp file,
  /// optionally with a silent LPCM audio track.
  private func makeDeterministicClip(
    seconds: Double, fps: Int, size: CGSize, withAudio: Bool
  ) async throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("lensmood-input-\(UUID().uuidString).mov")
    let width = Int(size.width), height = Int(size.height)

    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
    ])
    videoInput.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
      ]
    )
    XCTAssertTrue(writer.canAdd(videoInput), "writer rejected video input")
    writer.add(videoInput)

    var audioInput: AVAssetWriterInput?
    var audioFormat: CMAudioFormatDescription?
    let sampleRate = 44_100.0
    if withAudio {
      var asbd = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
        mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
      )
      let status = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault, asbd: &asbd,
        layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
        extensions: nil, formatDescriptionOut: &audioFormat
      )
      if status == noErr, audioFormat != nil {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
          AVFormatIDKey: kAudioFormatLinearPCM,
          AVSampleRateKey: sampleRate,
          AVNumberOfChannelsKey: 1,
          AVLinearPCMBitDepthKey: 16,
          AVLinearPCMIsBigEndianKey: false,
          AVLinearPCMIsFloatKey: false,
          AVLinearPCMIsNonInterleaved: false,
        ])
        input.expectsMediaDataInRealTime = false
        if writer.canAdd(input) {
          writer.add(input)
          audioInput = input
        }
      }
    }

    guard writer.startWriting() else {
      throw VhsError.exportFailed("test writer failed to start: \(writer.error?.localizedDescription ?? "unknown")")
    }
    writer.startSession(atSourceTime: .zero)

    // Video frames.
    let totalFrames = Int(seconds * Double(fps))
    for index in 0..<totalFrames {
      while !videoInput.isReadyForMoreMediaData { usleep(500) }
      let buffer = try makePixelBuffer(width: width, height: height, index: index, total: totalFrames)
      let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
      XCTAssertTrue(adaptor.append(buffer, withPresentationTime: pts), "failed to append frame \(index)")
    }
    videoInput.markAsFinished()

    // Silent audio, if requested and set up.
    if let audioInput, let audioFormat {
      let totalSamples = Int(seconds * sampleRate)
      let chunk = 4_410  // 0.1s
      var sampleIndex = 0
      while sampleIndex < totalSamples {
        let n = min(chunk, totalSamples - sampleIndex)
        if let sample = try? makeSilence(
          samples: n, startSample: sampleIndex, sampleRate: sampleRate, format: audioFormat
        ) {
          while !audioInput.isReadyForMoreMediaData { usleep(500) }
          audioInput.append(sample)
        }
        sampleIndex += n
      }
      audioInput.markAsFinished()
    }

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      writer.finishWriting { continuation.resume() }
    }
    guard writer.status == .completed else {
      throw VhsError.exportFailed("test writer did not complete: \(writer.error?.localizedDescription ?? "unknown")")
    }
    return url
  }

  /// One deterministic ARGB frame: mid-gray field + a blue bar whose x-position
  /// advances with the frame index (so consecutive frames differ ⇒ motion).
  private func makePixelBuffer(width: Int, height: Int, index: Int, total: Int) throws -> CVPixelBuffer {
    let attrs: CFDictionary = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ] as CFDictionary
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs, &pixelBuffer
    )
    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      throw VhsError.exportFailed("CVPixelBufferCreate failed (\(status))")
    }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
      throw VhsError.exportFailed("pixel buffer had no base address")
    }
    let context = CGContext(
      data: base, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    )
    guard let context else { throw VhsError.exportFailed("could not build CGContext for frame") }

    // Mid-gray field: bright enough to leave headroom for the grade to shift.
    context.setFillColor(red: 0.43, green: 0.43, blue: 0.43, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Blue motion bar — a non-cream colour so it never trips the overlay test.
    let barWidth = max(1, Int(Double(width) * 0.15))
    let progress = total > 1 ? Double(index) / Double(total - 1) : 0
    let barX = Int(progress * Double(width - barWidth))
    context.setFillColor(red: 0.0, green: 0.0, blue: 0.78, alpha: 1)
    context.fill(CGRect(x: barX, y: 0, width: barWidth, height: height))

    return buffer
  }

  /// A block of 16-bit LPCM silence as a ready CMSampleBuffer.
  private func makeSilence(
    samples: Int, startSample: Int, sampleRate: Double, format: CMAudioFormatDescription
  ) throws -> CMSampleBuffer {
    let byteCount = samples * 2
    var blockBuffer: CMBlockBuffer?
    var status = CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
      blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
      offsetToData: 0, dataLength: byteCount,
      flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &blockBuffer
    )
    guard status == kCMBlockBufferNoErr, let block = blockBuffer else {
      throw VhsError.exportFailed("CMBlockBufferCreate failed (\(status))")
    }
    // Zero it → true silence (allocated memory is otherwise undefined).
    status = CMBlockBufferFillDataBytes(
      with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount
    )
    guard status == kCMBlockBufferNoErr else {
      throw VhsError.exportFailed("CMBlockBufferFillDataBytes failed (\(status))")
    }

    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
      presentationTimeStamp: CMTime(value: CMTimeValue(startSample), timescale: CMTimeScale(sampleRate)),
      decodeTimeStamp: .invalid
    )
    var sampleSize = 2
    var sampleBuffer: CMSampleBuffer?
    status = CMSampleBufferCreateReady(
      allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
      sampleCount: samples, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
      sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sampleBuffer
    )
    guard status == noErr, let sample = sampleBuffer else {
      throw VhsError.exportFailed("CMSampleBufferCreateReady failed (\(status))")
    }
    return sample
  }
}
