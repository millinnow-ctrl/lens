import CoreText
import SwiftUI

@main
struct LensMoodApp: App {
  @StateObject private var model = AppModel()

  init() {
    Self.registerBundledFonts()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(model)
        .preferredColorScheme(.light)
    }
  }

  /// Register the bundled Space Mono faces (the camera's technical typeface)
  /// at launch so `Font.custom` can resolve them without an Info.plist entry.
  private static func registerBundledFonts() {
    for name in ["SpaceMono-Regular", "SpaceMono-Bold"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: "ttf")
        ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "fonts")
      else { continue }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }
}

extension Font {
  /// Space Mono — the camera instrument's label typeface.
  static func spaceMono(_ size: CGFloat, bold: Bool = false) -> Font {
    .custom(bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size)
  }
}
