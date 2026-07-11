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

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    switch environment["LENSMOOD_TAB"] {
    case "capture": selectedTab = .capture
    case "library": selectedTab = .library
    case "print": selectedTab = .printRoom
    case "tape": selectedTab = .tape
    default: selectedTab = .cameras
    }
  }

  func add(_ asset: DevelopedAsset) {
    library.insert(asset, at: 0)
  }

  func remove(_ asset: DevelopedAsset) {
    library.removeAll { $0.id == asset.id }
  }
}
