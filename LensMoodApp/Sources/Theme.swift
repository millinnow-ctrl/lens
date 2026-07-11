import SwiftUI

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

enum Theme {
  static let paper = Color(hex: "#F4F1EA")
  static let surface = Color(hex: "#FBF9F4")
  static let ink = Color(hex: "#171613")
  static let inkSoft = Color(hex: "#56524A")
  static let fog = Color(hex: "#817B70")
  static let hairline = Color(hex: "#D8D2C7")
  static let accent = Color(hex: "#C63C2F")
  static let viewfinder = Color(hex: "#11110F")
  static let viewfinderChrome = Color(hex: "#D7D2C9")
  static let recRed = Color(hex: "#E1251B")

  static let pagePadding: CGFloat = 18
  static let controlHeight: CGFloat = 52
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
      .background(background.opacity(configuration.isPressed ? 0.76 : 1))
      .overlay {
        if kind == .secondary {
          Rectangle().stroke(Theme.ink, lineWidth: 1)
        }
      }
      .contentShape(Rectangle())
      .opacity(configuration.isPressed ? 0.82 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }

  private var background: Color {
    switch kind {
    case .primary: return Theme.ink
    case .secondary: return Theme.surface
    case .quiet: return .clear
    }
  }

  private var foreground: Color {
    switch kind {
    case .primary: return Theme.paper
    case .secondary, .quiet: return Theme.ink
    }
  }
}

struct InstrumentPanel<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .background(Theme.surface)
      .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
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
