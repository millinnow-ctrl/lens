// Generated from the reference engine catalog (lensmood-native/src/engine/styles.ts).
// The 18 stocks - names, taglines, EXIF plates, card gradient stops.

import SwiftUI

struct Stock: Identifiable, Hashable {
  let id: String
  let name: String
  let tagline: String
  let exif: String
  let g0: String
  let g1: String
}

extension Stock {
  static let all: [Stock] = [
    Stock(id: "disposable", name: "Disposable Camera", tagline: "Warm flash, soft grain", exif: "F/11 · 400 FILM · FLASH", g0: "#ffb84d", g1: "#ff7a59"),
    Stock(id: "iphone-flash", name: "iPhone Flash", tagline: "Hard flash, deep shadows", exif: "F/1.8 · ISO 640 · FLASH", g0: "#e8e8f2", g1: "#9aa0b4"),
    Stock(id: "camcorder-90s", name: "90s Camcorder", tagline: "Soft tape, muted color", exif: "REC · 30FPS · AUTO", g0: "#7de0b8", g1: "#3d8f9f"),
    Stock(id: "leica-street", name: "Leica Street", tagline: "Clean contrast, quiet grain", exif: "F/2 · ISO 400 · 35MM", g0: "#3c3c46", g1: "#c8c8d2"),
    Stock(id: "gq-editorial", name: "GQ Editorial", tagline: "Polished light, crisp shadows", exif: "F/8 · ISO 100 · STROBE", g0: "#e8c877", g1: "#9a6b2f"),
    Stock(id: "a24-still", name: "A24 Movie Still", tagline: "Muted color, soft highlights", exif: "F/2.8 · ISO 800 · 1/48", g0: "#3f6f78", g1: "#1d2a33"),
    Stock(id: "film-noir", name: "Film Noir", tagline: "Hard light, deep blacks", exif: "F/5.6 · ISO 400 · B&W", g0: "#f2f2f2", g1: "#101014"),
    Stock(id: "y2k-digicam", name: "Y2K Digicam", tagline: "Glossy flash, bright color", exif: "F/2.6 · ISO 200 · FLASH", g0: "#7ad7ff", g1: "#c65cff"),
    Stock(id: "polaroid", name: "Polaroid", tagline: "Creamy light, faded color", exif: "F/8 · 600 FILM · INSTANT", g0: "#fff2dc", g1: "#f0b8a0"),
    Stock(id: "super-8", name: "Super 8", tagline: "Warm grain, home-movie glow", exif: "REC · 18FPS · 8MM", g0: "#ffc46b", g1: "#d96f32"),
    Stock(id: "lomo", name: "Lomo", tagline: "Punchy color, dark corners", exif: "F/2.8 · 400 FILM · ZONE", g0: "#37c978", g1: "#0e5a46"),
    Stock(id: "kodachrome", name: "Kodachrome", tagline: "Rich color, clean shadows", exif: "F/5.6 · K64 SLIDE · 1/125", g0: "#e8534a", g1: "#8f2d1e"),
    Stock(id: "security-cam", name: "Security Cam", tagline: "Grainy green, timestamped", exif: "CAM 02 · 12FPS · IR", g0: "#7de8a9", g1: "#2e4d3a"),
    Stock(id: "point-shoot", name: "Point & Shoot", tagline: "Crisp flash, glossy color", exif: "F/1.8 · 1.0″ CMOS · 24MM", g0: "#d8dee8", g1: "#2a2e36"),
    Stock(id: "pastel-cinema", name: "Pastel Cinema", tagline: "Powdery color, flat light", exif: "F/4 · ISO 100 · SYM", g0: "#ffd7e0", g1: "#b8e6d9"),
    Stock(id: "tokyo-neon", name: "Tokyo Neon", tagline: "Neon bloom, wet streets", exif: "F/1.4 · ISO 1600 · NIGHT", g0: "#22d3ee", g1: "#e879f9"),
    Stock(id: "photobooth", name: "Photobooth", tagline: "Hard flash, true black & white", exif: "STRIP · 4 FRAMES · B&W", g0: "#ffffff", g1: "#3a3a42"),
    Stock(id: "tintype", name: "Tintype 1900", tagline: "Sepia plate, deep vignette", exif: "WET PLATE · 5S EXP", g0: "#c9a05c", g1: "#4a321b"),
  ]
}
