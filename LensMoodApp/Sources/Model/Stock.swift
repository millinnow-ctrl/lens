import SwiftUI

struct Stock: Identifiable, Hashable {
  let id: String
  let name: String
  let tagline: String
  let bestFor: String
  let exif: String
  let g0: String
  let g1: String
  let symbol: String
  var badge: String? = nil

  var recipe: CameraRecipe { CameraRecipe.recipe(for: id) }
}

extension Stock {
  static let all: [Stock] = [
    Stock(id: "disposable", name: "Disposable", tagline: "Warm flash, soft grain", bestFor: "Friends after dark", exif: "F/11 · 400 · FLASH", g0: "#E5A94E", g1: "#C95B3E", symbol: "camera.fill"),
    Stock(id: "iphone-flash", name: "Direct Flash", tagline: "Hard flash, deep shadows", bestFor: "Night portraits", exif: "F/1.8 · ISO 640 · FLASH", g0: "#D7D8DD", g1: "#6D707A", symbol: "bolt.fill"),
    Stock(id: "camcorder-90s", name: "Tape 94", tagline: "Soft tape, muted color", bestFor: "Moving memories", exif: "REC · 30FPS · AUTO", g0: "#6DB69B", g1: "#315B61", symbol: "video.fill"),
    Stock(id: "leica-street", name: "Street 35", tagline: "Clean contrast, quiet grain", bestFor: "Available light", exif: "F/2 · ISO 400 · 35MM", g0: "#30302E", g1: "#A6A39A", symbol: "viewfinder"),
    Stock(id: "gq-editorial", name: "Editorial Strobe", tagline: "Polished light, crisp shadows", bestFor: "Structured portraits", exif: "F/8 · ISO 100 · STROBE", g0: "#C9AA5C", g1: "#76502B", symbol: "person.crop.rectangle"),
    Stock(id: "a24-still", name: "Independent Still", tagline: "Muted color, soft highlights", bestFor: "Quiet narrative frames", exif: "F/2.8 · ISO 800 · 1/48", g0: "#42636A", g1: "#1D292C", symbol: "film.fill"),
    Stock(id: "film-noir", name: "Noir", tagline: "Hard light, deep blacks", bestFor: "Graphic light", exif: "F/5.6 · ISO 400 · B&W", g0: "#DEDDD8", g1: "#11110F", symbol: "circle.lefthalf.filled"),
    Stock(id: "y2k-digicam", name: "Pocket 2002", tagline: "Glossy flash, bright color", bestFor: "Chaotic nights", exif: "F/2.6 · ISO 200 · FLASH", g0: "#5DB9D9", g1: "#9B52B4", symbol: "sparkles"),
    Stock(id: "polaroid", name: "Instant 600", tagline: "Creamy light, faded color", bestFor: "Tender daylight", exif: "F/8 · 600 · INSTANT", g0: "#F1E2CA", g1: "#DCA58F", symbol: "photo.fill"),
    Stock(id: "super-8", name: "8mm Home Movie", tagline: "Warm grain, home-movie glow", bestFor: "Sunlit memory", exif: "REC · 18FPS · 8MM", g0: "#DFA34C", g1: "#A64F2B", symbol: "film.stack"),
    Stock(id: "lomo", name: "Toy Color", tagline: "Punchy color, dark corners", bestFor: "Unpredictable daylight", exif: "F/2.8 · 400 · ZONE", g0: "#389866", g1: "#194A39", symbol: "camera.aperture"),
    Stock(id: "kodachrome", name: "Slide 64", tagline: "Rich color, clean shadows", bestFor: "Color in daylight", exif: "F/5.6 · 64 · 1/125", g0: "#C44D43", g1: "#682B24", symbol: "rectangle.stack.fill"),
    Stock(id: "security-cam", name: "Monitor 02", tagline: "Grainy green, night gain", bestFor: "Detached observation", exif: "CAM 02 · 12FPS · IR", g0: "#6CB98A", g1: "#294236", symbol: "eye.fill"),
    Stock(id: "point-shoot", name: "Pocket Compact", tagline: "Crisp flash, glossy color", bestFor: "Everyday immediacy", exif: "F/1.8 · 24MM · FLASH", g0: "#B6BBC2", g1: "#34373A", symbol: "camera.compact.fill"),
    Stock(id: "pastel-cinema", name: "Pastel Cinema", tagline: "Powdery color, flat light", bestFor: "Soft compositions", exif: "F/4 · ISO 100 · SYM", g0: "#E7BEC6", g1: "#A7CEC1", symbol: "cloud.sun.fill"),
    Stock(id: "tokyo-neon", name: "Neon Night", tagline: "Neon bloom, wet streets", bestFor: "Colored city light", exif: "F/1.4 · ISO 1600", g0: "#2998A8", g1: "#AA59A5", symbol: "lightswitch.on.fill"),
    Stock(id: "photobooth", name: "Photobooth", tagline: "Hard flash, true black and white", bestFor: "Close faces", exif: "STRIP · 4 FRAMES · B&W", g0: "#E8E7E2", g1: "#393936", symbol: "person.2.fill"),
    Stock(id: "tintype", name: "Wet Plate", tagline: "Cool silver plate, deep vignette", bestFor: "Still portraits", exif: "WET PLATE · 5S", g0: "#B3BBBA", g1: "#2E3639", symbol: "person.crop.artframe"),
  ]

  static func find(_ id: String) -> Stock {
    all.first(where: { $0.id == id }) ?? all[0]
  }
}
