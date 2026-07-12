import SwiftUI
import UIKit

/// Loose photographic resources (camcorder cover, print surface plates) are
/// bundled outside the asset catalog, and XcodeGen may place them at the
/// bundle root or under images/ depending on how the group resolves — probe
/// both before falling back to the caller's procedural stand-in.
enum BundleMedia {
  static func image(_ name: String) -> UIImage? {
    if let direct = UIImage(named: name) { return direct }
    for ext in ["jpg", "png"] {
      if let url = Bundle.main.url(forResource: name, withExtension: ext)
        ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "images") {
        return UIImage(contentsOfFile: url.path)
      }
    }
    return nil
  }
}

extension Color {
  init(hex: String) {
    let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var hexValue: UInt64 = 0
    Scanner(string: value).scanHexInt64(&hexValue)
    let red: UInt64
    let green: UInt64
    let blue: UInt64
    switch value.count {
    case 6:
      (red, green, blue) = ((hexValue >> 16) & 0xFF, (hexValue >> 8) & 0xFF, hexValue & 0xFF)
    default:
      (red, green, blue) = (128, 128, 128)
    }
    self.init(
      red: Double(red) / 255,
      green: Double(green) / 255,
      blue: Double(blue) / 255
    )
  }
}

/// Ocean darkroom palette — the owner-approved identity, ported 1:1 from the
/// reference app (`lensmood-native/src/theme/colors.ts`). Cool gray-white
/// paper, crisp white cards, one calm ocean-teal accent. The photograph stays
/// the loudest color in the room.
enum Theme {
  static let paper = Color(hex: "#EEF2F5")
  static let surface = Color(hex: "#FFFFFF")
  static let ink = Color(hex: "#17242D")
  static let inkSoft = Color(hex: "#586974")
  static let fog = Color(hex: "#6E7C86")
  static let hairline = Color(hex: "#E1E7EC")
  static let accent = Color(hex: "#0E7487")
  static let accentMid = Color(hex: "#1C8397")
  static let accentLight = Color(hex: "#39A6BB")
  static let clay = Color(hex: "#0C5568")
  static let clayDeep = Color(hex: "#083C4A")
  static let viewfinder = Color(hex: "#141A1F")
  static let viewfinderChrome = Color(hex: "#8A96A0")
  static let recRed = Color(hex: "#E1251B")

  /// glossy ocean fill — the primary action (reference `gradients.brandFill`)
  static let brandFill = LinearGradient(
    colors: [Color(hex: "#128AA0"), Color(hex: "#0C5E70")],
    startPoint: .top, endPoint: .bottom
  )
  /// deep teal → ocean → bright teal (reference `gradients.brandText`)
  static let brandText = LinearGradient(
    colors: [Color(hex: "#0C6376"), Color(hex: "#0F7D92"), Color(hex: "#2EA0B3")],
    startPoint: .leading, endPoint: .trailing
  )

  static let pagePadding: CGFloat = 14
  static let controlHeight: CGFloat = 52
  static let cardRadius: CGFloat = 18
}

extension View {
  /// the reference app's soft card elevation (shadowOpacity 0.28 on the
  /// deepest cards, lighter on white surfaces)
  func oceanCardShadow(deep: Bool = false) -> some View {
    shadow(
      color: Color(hex: "#02070A").opacity(deep ? 0.28 : 0.10),
      radius: deep ? 14 : 10, x: 0, y: deep ? 8 : 4
    )
  }
}

struct InstrumentButtonStyle: ButtonStyle {
  enum Kind {
    case primary
    case secondary
    case quiet
  }

  let kind: Kind

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(foreground)
      .frame(maxWidth: .infinity)
      .frame(minHeight: Theme.controlHeight)
      .background(background(pressed: configuration.isPressed))
      .clipShape(Capsule())
      .overlay {
        if kind == .secondary {
          Capsule().stroke(Theme.hairline, lineWidth: 1)
        }
      }
      .contentShape(Capsule())
      .opacity(configuration.isPressed ? 0.92 : 1)
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }

  @ViewBuilder
  private func background(pressed: Bool) -> some View {
    switch kind {
    case .primary: Theme.brandFill.opacity(pressed ? 0.9 : 1)
    case .secondary: Theme.surface
    case .quiet: Color.clear
    }
  }

  private var foreground: Color {
    switch kind {
    case .primary: return .white
    case .secondary, .quiet: return Theme.ink
    }
  }
}

struct InstrumentPanel<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.hairline, lineWidth: 1)
      )
  }
}

struct TechnicalLabel: View {
  let text: String

  var body: some View {
    Text(text.uppercased())
      .font(.system(size: 10, weight: .semibold, design: .monospaced))
      .tracking(1.4)
      .foregroundStyle(Theme.fog)
      .accessibilityLabel(text)
  }
}
