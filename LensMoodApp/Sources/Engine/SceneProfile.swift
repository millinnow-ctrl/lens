import CoreGraphics

struct SceneProfile: Equatable {
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

  static let neutral = SceneProfile(
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

struct FaceProfile: Equatable, Identifiable {
  let id: Int
  let bounds: CGRect
  let confidence: Float
}
