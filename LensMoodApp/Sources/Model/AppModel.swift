import SwiftUI
import UIKit

enum AppTab: Hashable {
  case cameras
  case capture
  case library
  case printRoom
  case tape
}

struct DevelopedAsset: Identifiable {
  let id = UUID()
  let image: UIImage
  let source: UIImage
  let stock: Stock
  let decisions: [String]
  let createdAt = Date()
}

@MainActor
final class AppModel: ObservableObject {
  @Published var selectedTab: AppTab = .cameras
  @Published var library: [DevelopedAsset] = []
  @Published var accountPresented = false
  /// a photo chosen on the Home hero ("Choose from Library"), handed to the
  /// next DevelopView so it develops that frame straight away
  @Published var pendingDevelopImage: UIImage?

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    switch environment["LENSMOOD_TAB"] {
    case "capture": selectedTab = .capture
    case "library": selectedTab = .library
    case "print": selectedTab = .printRoom
    case "tape": selectedTab = .tape
    default: selectedTab = .cameras
    }
    // CI/screenshot only: seed a contact sheet so Library and Print Room show
    // their populated state. Never runs in a real user session (the env var is
    // set solely by the capture harness), so first-run stays genuinely empty.
    if environment["LENSMOOD_DEMO"] == "1" { seedDemoLibrary() }
  }

  /// fill the session library with bundled sample frames (screenshot fixtures)
  private func seedDemoLibrary() {
    let picks = [
      "disposable", "leica-street", "kodachrome", "tokyo-neon", "polaroid",
      "a24-still", "film-noir", "gq-editorial", "point-shoot", "pastel-cinema",
      "super-8", "y2k-digicam",
    ]
    for id in picks {
      guard let stock = Stock.all.first(where: { $0.id == id }),
            let image = BundleMedia.image("style-\(id)") else { continue }
      library.append(DevelopedAsset(image: image, source: image, stock: stock, decisions: []))
    }
  }

  func add(_ asset: DevelopedAsset) {
    library.insert(asset, at: 0)
  }

  func remove(_ asset: DevelopedAsset) {
    library.removeAll { $0.id == asset.id }
  }
}
