import CoreImage
import Foundation

/// Engine schema stamp for a persisted reading. Bump it whenever the reading's
/// replay-essentials change shape — a `SceneProfile` field, the face record, or
/// any mask-production heuristic in `attachLightMasks` — so a sidecar written
/// by an older build can no longer masquerade as a current reading. A stored
/// reading whose stamp differs from this is ignored, and the develop path falls
/// back to a fresh read (never a crash, never a half-applied reading).
enum ReadingSchema {
  static let version = 1
}

/// A `SceneReading` frozen for disk. It carries exactly the pieces a develop
/// consumes: the scene meter (all scalars, whole `SceneProfile`), the detected
/// faces, and the three materialized masks — subject silhouette, skin, sky — as
/// their raw L8 bytes at analysis resolution, plus a provenance stamp.
///
/// Why it exists: a photograph's develop is deterministic *given one reading*,
/// but a second read is not bit-stable — Vision segmentation drifts run to run
/// and across OS updates. The Conductor already enforces one reading per photo
/// within a session; this extends that law across time, so a re-develop replays
/// the exact reading the frame was developed with instead of a drifted re-read.
///
/// The person matte is deliberately not stored. Only the three derived masks
/// have committed byte arrays that round-trip losslessly (the person matte
/// would need a lossy re-render, defeating the purpose); the flash near-field
/// falls back to the faces, which *are* stored, so a replay stays deterministic.
struct PersistedReading: Codable {
  let schema: Int
  /// Provenance only, never a fallback gate: the whole point is to replay a
  /// reading taken on an OLDER OS build, so the build is recorded, not enforced
  /// (only `schema` decides whether a sidecar is still valid).
  let osBuild: String
  let scene: SceneProfile
  let faces: [FaceProfile]

  // The masks in raw, base64-encoded (via `Data`) form at their shared grid.
  let maskWidth: Int
  let maskHeight: Int
  let subjectMatte: Data?
  let skinMask: Data?
  let skyMask: Data?

  /// Freeze a live reading. Always succeeds: a reading with no masks (subject
  /// pass off, or Vision found nothing) freezes to scene + faces only, which
  /// replays byte-identically to the same maskless reading.
  init(_ reading: SceneReading, osBuild: String) {
    schema = ReadingSchema.version
    self.osBuild = osBuild
    scene = reading.scene
    faces = reading.subject.faces
    let raster = reading.subject.maskRaster
    maskWidth = raster?.width ?? 0
    maskHeight = raster?.height ?? 0
    subjectMatte = raster?.subjectMatte.map { Data($0) }
    skinMask = raster?.skinMask.map { Data($0) }
    skyMask = raster?.skyMask.map { Data($0) }
  }

  /// Rebuild the live reading, or nil when the sidecar's engine schema is not
  /// the current one (the caller then reads fresh). Masks are rebuilt through
  /// the *same* `materializeMask` the subject pass used, so a replayed mask is
  /// bit-for-bit identical to the one the passes originally saw.
  func makeReading() -> SceneReading? {
    guard schema == ReadingSchema.version else { return nil }
    let raster: SubjectMaskRaster?
    if maskWidth > 0, maskHeight > 0 {
      raster = SubjectMaskRaster(
        width: maskWidth,
        height: maskHeight,
        subjectMatte: subjectMatte.map { [UInt8]($0) },
        skinMask: skinMask.map { [UInt8]($0) },
        skyMask: skyMask.map { [UInt8]($0) }
      )
    } else {
      raster = nil
    }
    func materialize(_ bytes: [UInt8]?) -> CIImage? {
      FilmEngine.materializeMask(bytes, width: maskWidth, height: maskHeight)
    }
    let subject = SubjectAnalysis(
      faces: faces,
      // the person matte is not persisted (see the type doc); the flash
      // near-field falls back to the faces above
      personMask: nil,
      subjectMatte: materialize(raster?.subjectMatte),
      skinMask: materialize(raster?.skinMask),
      skyMask: materialize(raster?.skyMask),
      maskRaster: raster
    )
    return SceneReading(scene: scene, subject: subject)
  }

  /// The OS build recorded on every reading written now (version + build, e.g.
  /// "Version 17.0 (Build 21A329)"). Read once at write time; never gates load.
  static var currentOSBuild: String {
    ProcessInfo.processInfo.operatingSystemVersionString
  }
}
