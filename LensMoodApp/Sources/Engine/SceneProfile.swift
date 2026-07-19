import CoreGraphics
import Foundation // CGRect's Codable conformance (FaceProfile) lives in the Foundation overlay

/// A face/subject focal reading — mirrors `Focal` in the frozen reference
/// (lensmood-native/src/engine/types.ts).
struct Focal: Equatable {
  /// face center, normalized 0..1
  let x: Double
  let y: Double
  /// face radius as a fraction of the longest edge
  let r: Double
}

/// Mirrors `LightSource` in the frozen reference
/// (lensmood-native/src/engine/types.ts).
///
/// Codable so a whole `SceneProfile` can be frozen into a reading sidecar
/// (see PersistedReading) and replayed byte-for-byte on a later develop.
struct LightSource: Equatable, Codable {
  /// normalized center, 0..1 of frame
  let x: Double
  let y: Double
  /// blob radius as a fraction of the longest edge
  let r: Double
  /// 0..1 — how hot the blob's peak burns above the specular threshold
  let intensity: Double
  /// the light's true color, sampled on the glow annulus around the clipped
  /// core (the core itself is blown white) — [r, g, b] 0..1
  let tint: [Double]
}

struct SceneProfile: Equatable, Codable {
  // MARK: - Reference meter fields
  // NEW: verbatim port of `SceneProfile` in the frozen reference
  // (lensmood-native/src/engine/types.ts), produced by the ported meter in
  // SceneAnalyzer.swift. These are the adaptive parameters the reference
  // engine consumes; FilmEngine integration happens separately.

  /// false for the neutral fallback — adaptive passes that would otherwise
  /// misread the placeholder percentiles must check this
  let analyzed: Bool
  /// log-average luminance, 0..1 — the meter's reading of the scene key
  let key: Double
  let p01: Double
  let p50: Double
  let p99: Double
  /// white-balance gains [r, g, b], luma-preserving (never change exposure)
  let illum: [Double]
  /// mean pixel saturation 0..1 — how much color the scene actually has;
  /// drives vibrance recovery on muted uploads
  let sat: Double
  /// up to 5 detected light sources, largest energy first
  let lights: [LightSource]
  /// R63 (Swift-only, additive): saturated colored emitters — blue/red neon —
  /// whose luma never crosses the specular knee, detected by peak channel
  /// energy. NOT part of the reference meter; the light-intelligence passes
  /// consume `lights + auxLights`.
  let auxLights: [LightSource]
  /// mean luminance under the face ellipse, when a face was found
  let faceLum: Double?

  // MARK: - Legacy fields
  // Pre-port Swift API, kept so existing callers (FilmEngine and views)
  // keep compiling. Computed over the same thumbnail with the pre-port
  // formulas; NOT part of the reference meter.
  let meanLuminance: Double
  let medianLuminance: Double
  let shadowFraction: Double
  let highlightFraction: Double
  let dynamicRange: Double
  let averageRed: Double
  let averageGreen: Double
  let averageBlue: Double
  let saturation: Double
  let warmth: Double
  let isLowKey: Bool
  let isHighKey: Bool
  let isBacklit: Bool

  /// Neutral fallback — the reference's NEUTRAL_SCENE for the ported fields,
  /// plus the pre-port neutral values for the legacy fields.
  static let neutral = SceneProfile(
    analyzed: false,
    key: 0.4,
    p01: 0,
    p50: 0.4,
    p99: 1,
    illum: [1, 1, 1],
    sat: 0.35,
    lights: [],
    auxLights: [],
    faceLum: nil,
    meanLuminance: 0.5,
    medianLuminance: 0.5,
    shadowFraction: 0,
    highlightFraction: 0,
    dynamicRange: 0.5,
    averageRed: 0.5,
    averageGreen: 0.5,
    averageBlue: 0.5,
    saturation: 0,
    warmth: 0,
    isLowKey: false,
    isHighKey: false,
    isBacklit: false
  )
}

struct FaceProfile: Equatable, Identifiable, Codable {
  let id: Int
  let bounds: CGRect
  let confidence: Float
}
