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
  @Published var library: [DevelopedAsset] = [] {
    didSet { rollsCache = nil }
  }
  @Published var accountPresented = false
  /// a photo chosen on the Home hero ("Choose from Library"), handed to the
  /// next DevelopView so it develops that frame straight away
  @Published var pendingDevelopImage: UIImage?
  /// a camera queued from elsewhere in the app — the Library's "Shoot this
  /// film again" sets it, HomeView routes it into a fresh DevelopView with
  /// that stock loaded (same hand-off idiom as `pendingDevelopImage`)
  @Published var pendingStock: Stock?

  /// the Library as monthly film rolls, newest first (see `Roll.group`) —
  /// memoized so Gallery body evaluations don't regroup an unchanged library
  private var rollsCache: [Roll]?
  var rolls: [Roll] {
    if let rollsCache { return rollsCache }
    let grouped = Roll.group(library)
    rollsCache = grouped
    return grouped
  }

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
    if environment["LENSMOOD_AD"] == "1" {
      // Screenshot/ad harness only (set solely by CI): land on Cameras with a
      // photograph already handed to the develop flow, so the develop surface
      // can be captured without any tap scripting. LENSMOOD_AD_STOCK picks
      // the camera, so one CI run photographs the real develop screen per
      // camera — the ad's look-switch cuts are then whole real screens, not
      // composites. Never runs in a real session.
      seedDemoLibrary()
      let stockID = environment["LENSMOOD_AD_STOCK"] ?? "tokyo-neon"
      pendingStock = Stock.find(stockID)
      pendingDevelopImage = BundleMedia.image("style-tokyo-neon")
    } else if environment["LENSMOOD_DEMO"] == "1" {
      seedDemoLibrary()
    } else {
      // real sessions: restore the developed Library from disk so it survives
      // relaunch (frames are stored downsized, so this is memory-bounded)
      library = LibraryStore.load()
      Analytics.log(.appOpened)
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
      // spread the frames across three months so the Library capture shows
      // the roll sleeves (one per calendar month); minutes keep in-roll order
      // deterministic
      let createdAt = Calendar.current.date(
        byAdding: DateComponents(month: -(offset / 5), minute: -offset),
        to: Date()
      ) ?? Date()
      // seed a couple of favorites so the Library shows the heart affordance
      library.append(DevelopedAsset(
        image: image, source: image, stock: stock, decisions: [],
        createdAt: createdAt, favorite: offset < 2
      ))
    }
  }

  /// Route a `lensmood://` deep link (widget tap → `RootView.onOpenURL`):
  /// queue the camera through the same `pendingStock` hand-off the Library's
  /// "Shoot this film again" uses, and land on the Cameras tab where HomeView
  /// pushes its develop view. Unknown URLs are ignored entirely.
  func open(url: URL) {
    guard let link = DeepLink.parse(url) else { return }
    switch link {
    case .develop(let stockID):
      pendingStock = Stock.find(stockID)
      selectedTab = .cameras
    }
  }

  /// flip a developed frame's favorite flag and persist it (index-only write)
  func toggleFavorite(id: UUID) {
    guard let index = library.firstIndex(where: { $0.id == id }) else { return }
    library[index].favorite.toggle()
    LibraryStore.setFavorite(id: id, favorite: library[index].favorite)
    Analytics.log(.favoriteToggled(on: library[index].favorite))
    UISelectionFeedbackGenerator().selectionChanged()
  }

  func add(_ asset: DevelopedAsset) {
    library.insert(asset, at: 0)
    // The cap is a memory bound, not an archive policy: trim the OLDEST
    // non-favorite frames only. A favorite is never silently deleted — the
    // Library presents itself as a permanent archive of rolls, and deleting
    // a starred frame as a side effect of developing would be data loss.
    if library.count > 48 {
      var excess = library.count - 48
      for index in stride(from: library.count - 1, through: 0, by: -1) where excess > 0 {
        if !library[index].favorite {
          library.remove(at: index)
          excess -= 1
        }
      }
    }
    // durability: persist the new frame, then drop any on-disk frames that fell
    // off the capped roll (writes run on the store's serial queue, off-main)
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
