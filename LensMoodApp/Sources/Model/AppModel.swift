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
  let id: UUID
  let image: UIImage
  let source: UIImage
  let stock: Stock
  let decisions: [String]
  let createdAt: Date
  var favorite: Bool

  init(
    id: UUID = UUID(),
    image: UIImage,
    source: UIImage,
    stock: Stock,
    decisions: [String],
    createdAt: Date = Date(),
    favorite: Bool = false
  ) {
    self.id = id
    self.image = image
    self.source = source
    self.stock = stock
    self.decisions = decisions
    self.createdAt = createdAt
    self.favorite = favorite
  }
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
    if environment["LENSMOOD_DEMO"] == "1" {
      seedDemoLibrary()
    } else {
      // real sessions: restore the developed Library from disk so it survives
      // relaunch (frames are stored downsized, so this is memory-bounded)
      library = LibraryStore.load()
    }
  }

  /// fill the session library with bundled sample frames (screenshot fixtures)
  private func seedDemoLibrary() {
    // point-shoot leads: its clean flash frame reads like a photo straight
    // off the iPhone, which is what the Print stage shows first
    let picks = [
      "point-shoot", "leica-street", "disposable", "kodachrome", "tokyo-neon",
      "polaroid", "a24-still", "film-noir", "gq-editorial", "pastel-cinema",
      "super-8", "y2k-digicam",
    ]
    for (offset, id) in picks.enumerated() {
      guard let stock = Stock.all.first(where: { $0.id == id }),
            let image = BundleMedia.image("style-\(id)") else { continue }
      // seed a couple of favorites so the Library shows the heart affordance
      library.append(DevelopedAsset(
        image: image, source: image, stock: stock, decisions: [], favorite: offset < 2
      ))
    }
  }

  /// flip a developed frame's favorite flag and persist it (index-only write)
  func toggleFavorite(id: UUID) {
    guard let index = library.firstIndex(where: { $0.id == id }) else { return }
    library[index].favorite.toggle()
    LibraryStore.setFavorite(id: id, favorite: library[index].favorite)
    UISelectionFeedbackGenerator().selectionChanged()
  }

  func add(_ asset: DevelopedAsset) {
    library.insert(asset, at: 0)
    // full-resolution frames are heavy — bound the session roll so long
    // sessions can't grow memory without limit
    if library.count > 48 {
      library.removeLast(library.count - 48)
    }
    // durability: persist the new frame, then drop any on-disk frames that fell
    // off the capped roll
    LibraryStore.persist(asset)
    LibraryStore.prune(keeping: library.map(\.id))
  }

  func remove(_ asset: DevelopedAsset) {
    remove(id: asset.id)
  }

  func remove(id: UUID) {
    library.removeAll { $0.id == id }
    LibraryStore.delete(id: id)
  }
}
