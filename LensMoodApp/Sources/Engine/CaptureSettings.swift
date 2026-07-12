import CoreGraphics
import Foundation

/// The exposure regime, exactly like a pro DSLR mode dial. It decides which
/// dials move brightness versus which are "look-only" — so Aperture Priority
/// holds exposure and only changes depth of field, as a real body does.
enum ExposureMode: String, CaseIterable, Equatable {
  case program = "P"
  case shutterPriority = "Tv"
  case aperturePriority = "Av"
  case manual = "M"
}

enum CaptureFlashMode: Equatable { case off, on, auto }

/// The live state of the pro camera's controls. Every look term is measured
/// as a deviation from the loaded camera's rated EXIF "home", so at home every
/// term is zero and the developed frame equals the pure owner-approved recipe.
struct CaptureSettings: Equatable {
  var mode: ExposureMode = .aperturePriority
  var aperture: Double = 2.8          // f-number
  var iso: Double = 200
  var shutter: Double = 1.0 / 125     // seconds
  var exposureBiasEV: Double = 0
  var kelvin: Double = 5200
  var flashMode: CaptureFlashMode = .off
  var focalLength: Double = 35        // mm-equivalent
  var focusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)  // normalized, top-left origin

  // the loaded camera's rated home (parsed from its EXIF line)
  var homeAperture: Double = 2.8
  var homeISO: Double = 200
  var homeShutter: Double = 1.0 / 125

  /// the EV the AVCaptureDevice actually realized (0 in the simulator / look-only)
  var hardwareAppliedEV: Double = 0

  // MARK: exposure-triangle stops, relative to home

  /// aperture stops (wider than home is positive)
  var apertureStops: Double { 2 * log2(max(0.5, homeAperture) / max(0.5, aperture)) }
  /// ISO stops
  var isoStops: Double { log2(max(1, iso) / max(1, homeISO)) }
  /// shutter stops (slower than home is positive)
  var shutterStops: Double { log2(max(1e-6, shutter) / max(1e-6, homeShutter)) }
  var baselineEV: Double { apertureStops + isoStops + shutterStops }

  /// brightness change fed to the developer, gated by the exposure mode
  var captureEV: Double {
    switch mode {
    case .manual:
      // soft knee: the full triangle drives brightness but never blows out
      return 3 * tanh((baselineEV + exposureBiasEV) / 3)
    case .program, .aperturePriority, .shutterPriority:
      // the body holds exposure; only exposure compensation moves brightness
      return min(3, max(-3, exposureBiasEV))
    }
  }

  /// EV the developer applies after subtracting what the sensor already did
  var appliedEV: Double { captureEV - hardwareAppliedEV }

  // MARK: look terms

  /// how far the focal length pushes/pulls background separation
  var focalMultiplier: Double {
    switch focalLength {
    case ..<30: return 0.85
    case ..<45: return 1.0
    case ..<70: return 1.15
    default: return 1.5
    }
  }

  /// 0…1 background-blur amount from a wide aperture
  var bokehStrength: Double { min(1, max(0, apertureStops / 3)) * focalMultiplier }
  var wantsDepthOfField: Bool { bokehStrength > 0.05 }

  /// deep-focus micro-sharpening when stopped down past home
  var deepFocusAcutance: Double { apertureStops < 0 ? min(1, -apertureStops) * 0.05 : 0 }

  /// sensor noise amplitude from ISO above home
  var isoNoiseAmplitude: Double { min(6, max(0, isoStops)) * 0.018 }
  var isoSaturationMultiplier: Double { 1 - max(0, isoStops - 3) * 0.03 }

  /// motion blur from a slow shutter
  var motionStrength: Double { min(6, max(0, shutterStops)) }
  var slowShutterAcutance: Double { shutterStops < 0 ? min(1, -shutterStops) * 0.06 : 0 }

  /// warm/cool tint from the white-balance dial (−0.30…+0.30, warm positive)
  var warmthWB: Double { min(0.30, max(-0.30, (5200 - kelvin) / 8000)) + 0.03 }

  var extraWideOpenGlow: Double { aperture <= 2 ? max(0, apertureStops) * 0.04 : 0 }

  /// true when nothing has moved off home — the developer then does no extra work
  var isNeutral: Bool {
    abs(aperture - homeAperture) < 1e-3
      && abs(iso - homeISO) < 1e-3
      && abs(shutter - homeShutter) < 1e-6
      && abs(exposureBiasEV) < 1e-3
      && abs(kelvin - 5200) < 1
      && flashMode == .off
  }

  // MARK: EXIF-home parsing

  /// seed the dials to a camera's rated home so it opens on the approved look
  static func home(for stock: Stock) -> CaptureSettings {
    let (f, iso, t) = exifHome(stock)
    var s = CaptureSettings()
    s.aperture = f; s.iso = iso; s.shutter = t
    s.homeAperture = f; s.homeISO = iso; s.homeShutter = t
    return s
  }

  /// parse "F/5.6 · 64 · 1/125" style EXIF into (aperture, iso, shutter)
  static func exifHome(_ stock: Stock) -> (Double, Double, Double) {
    var f = 2.8, iso = 200.0, t = 1.0 / 125
    let tokens = stock.exif.split(whereSeparator: { $0 == "·" }).map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    for token in tokens {
      let upper = token.uppercased()
      if let r = upper.range(of: #"F/([0-9.]+)"#, options: .regularExpression) {
        f = Double(upper[r].dropFirst(2)) ?? f
      } else if let r = upper.range(of: #"ISO ?([0-9]+)"#, options: .regularExpression) {
        iso = Double(upper[r].replacingOccurrences(of: "ISO", with: "").trimmingCharacters(in: .whitespaces)) ?? iso
      } else if let r = upper.range(of: #"1/([0-9]+)"#, options: .regularExpression) {
        if let d = Double(upper[r].dropFirst(2)) { t = 1.0 / d }
      } else if let r = upper.range(of: #"^([0-9]+)S$"#, options: .regularExpression) {
        t = Double(upper[r].dropLast()) ?? t
      } else if upper.range(of: #"^[0-9]{2,4}$"#, options: .regularExpression) != nil {
        // a bare film-speed number (e.g. "64", "600", "400")
        iso = Double(upper) ?? iso
      }
    }
    // named overrides where the EXIF is not a photographic triple
    switch stock.id {
    case "tintype": t = 5
    case "kodachrome": f = 5.6; iso = 64; t = 1.0 / 125
    case "tokyo-neon": f = 1.4; iso = 1600
    default: break
    }
    return (f, iso, t)
  }
}

/// the live envelope the AVCaptureDevice reports (the hardware limits the dials)
struct CaptureLimits: Equatable {
  var minISO: Double = 25
  var maxISO: Double = 12800
  var minShutter: Double = 1.0 / 8000
  var maxShutter: Double = 30
  var minBias: Double = -3
  var maxBias: Double = 3
  var minZoom: Double = 1
  var maxZoom: Double = 1
  // the iPhone lens aperture is fixed; the dial's f-range is an app constant
  var minAperture: Double = 1.2
  var maxAperture: Double = 22
}
