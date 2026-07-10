// Ocean darkroom palette — same tokens as the reference app, so the SwiftUI
// build looks like LensMood on day one.

import SwiftUI

extension Color {
  init(hex: String) {
    let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    let r, g, b: UInt64
    switch s.count {
    case 6: (r, g, b) = ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
    default: (r, g, b) = (128, 128, 128)
    }
    self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
  }
}

enum Theme {
  static let paper = Color(hex: "#eef2f5")
  static let surface = Color.white
  static let ink = Color(hex: "#17242d")
  static let inkSoft = Color(hex: "#586974")
  static let fog = Color(hex: "#6e7c86")
  static let accent = Color(hex: "#0e7487")
  static let viewfinder = Color(hex: "#141a1f")
  static let recRed = Color(hex: "#e1251b")
}
