import SwiftUI
import UIKit

enum AppTab: Hashable {
  case cameras
  case capture
  case library
  case printRoom
  case tape
}

/// One developed photograph, held two-tier so the 48-frame Library stays
/// memory-bounded:
/// - `thumbnail` (≤480 px long edge) is always resident — it is all the
///   Gallery grid, roll sleeves, and camera Roll sheet ever draw.
/// - the full 2048 px frame lives on disk (`imageURL`) and is decoded on
///   demand (frame detail, print, save). Only the just-developed session
///   asset keeps the full frame (and its original) in memory, so review
///   right after a develop is instant.
struct DevelopedAsset: Identifiable {
  let id: UUID
  /// grid-tier preview, always in memory (long edge ≤ `thumbnailEdge` px)
  let thumbnail: UIImage
  /// the full developed frame — just-developed session assets only;
  /// nil once the frame is reloaded from disk or demoted by a newer frame
  let image: UIImage?
  /// the stored 2048 px JPEG backing `loadFullImage()` for persisted frames
  let imageURL: URL?
  /// the original photograph — session assets only (the camera's
  /// full-resolution re-develop path); nil for persisted/demoted frames
  let source: UIImage?
  let stock: Stock
  let decisions: [String]
  let createdAt: Date
  var favorite: Bool

  /// the grid tier's pixel bound (long edge)
  static let thumbnailEdge: CGFloat = 480

  /// A just-developed session asset: holds the full frame and original in
  /// memory; the thumbnail is built here once so the grid never pays for a
  /// full-frame decode.
  init(
    id: UUID = UUID(),
    image: UIImage,
    source: UIImage,
    stock: Stock,
    decisions: [String],
    createdAt: Date = Date(),
    favorite: Bool = false
  ) {
    self.init(
      id: id,
      thumbnail: Self.makeThumbnail(from: image),
      image: image,
      imageURL: nil,
      source: source,
      stock: stock,
      decisions: decisions,
      createdAt: createdAt,
      favorite: favorite
    )
  }

  /// A frame restored from disk: thumbnail in memory, full frame on demand.
  init(
    id: UUID,
    thumbnail: UIImage,
    imageURL: URL,
    stock: Stock,
    decisions: [String],
    createdAt: Date,
    favorite: Bool
  ) {
    self.init(
      id: id,
      thumbnail: thumbnail,
      image: nil,
      imageURL: imageURL,
      source: nil,
      stock: stock,
      decisions: decisions,
      createdAt: createdAt,
      favorite: favorite
    )
  }

  private init(
    id: UUID,
    thumbnail: UIImage,
    image: UIImage?,
    imageURL: URL?,
    source: UIImage?,
    stock: Stock,
    decisions: [String],
    createdAt: Date,
    favorite: Bool
  ) {
    self.id = id
    self.thumbnail = thumbnail
    self.image = image
    self.imageURL = imageURL
    self.source = source
    self.stock = stock
    self.decisions = decisions
    self.createdAt = createdAt
    self.favorite = favorite
  }

  /// The full developed frame: the in-memory session frame when present,
  /// otherwise one bounded (≤2048 px) JPEG decode from disk. Prefer calling
  /// off the main thread; fall back to `thumbnail` when this returns nil.
  func loadFullImage() -> UIImage? {
    if let image { return image }
    guard let imageURL else { return nil }
    return UIImage(contentsOfFile: imageURL.path)
  }

  /// The same frame with its in-memory bitmaps released: once a newer frame
  /// arrives, this one's frame of record is the persisted 2048 px JPEG (its
  /// write is already queued on LibraryStore's serial queue by `add`).
  func demotedToStored() -> DevelopedAsset {
    guard image != nil || source != nil else { return self }
    return DevelopedAsset(
      id: id,
      thumbnail: thumbnail,
      image: nil,
      imageURL: imageURL ?? LibraryStore.frameURL(for: id),
      source: nil,
      stock: stock,
      decisions: decisions,
      createdAt: createdAt,
      favorite: favorite
    )
  }

  /// Bound a frame to the grid tier. Pixel-true: accounts for `scale`, and
  /// always emits a scale-1 bitmap so the bound is a real pixel bound.
  static func makeThumbnail(from image: UIImage, maxEdge: CGFloat = thumbnailEdge) -> UIImage {
    let pixelLongest = max(image.size.width * image.scale, image.size.height * image.scale)
    guard pixelLongest > maxEdge else { return image }
    let factor = maxEdge / pixelLongest
    let size = CGSize(
      width: (image.size.width * image.scale * factor).rounded(.down),
      height: (image.size.height * image.scale * factor).rounded(.down)
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
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
      // relaunch (load decodes only grid-tier thumbnails — the 2048 px frames
      // stay on disk until a detail view asks for one)
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
    // Two-tier memory law: only the newest frame keeps its full bitmap (and
    // original) in memory. Every older frame demotes to thumbnail + on-disk
    // frame — its 2048 px JPEG is already written (or queued) by the persist
    // below from when it was added.
    var next = library.map { $0.demotedToStored() }
    next.insert(asset, at: 0)
    // The cap is a memory bound, not an archive policy: trim the OLDEST
    // non-favorite frames only. A favorite is never silently deleted — the
    // Library presents itself as a permanent archive of rolls, and deleting
    // a starred frame as a side effect of developing would be data loss.
    if next.count > 48 {
      var excess = next.count - 48
      for index in stride(from: next.count - 1, through: 0, by: -1) where excess > 0 {
        if !next[index].favorite {
          next.remove(at: index)
          excess -= 1
        }
      }
    }
    library = next
    // durability: persist the new frame, then drop any on-disk frames that fell
    // off the capped roll (writes run on the store's serial queue, off-main)
    LibraryStore.persist(asset)
    LibraryStore.prune(keeping: next.map(\.id))
  }

  func remove(_ asset: DevelopedAsset) {
    remove(id: asset.id)
  }

  func remove(id: UUID) {
    library.removeAll { $0.id == id }
    LibraryStore.delete(id: id)
  }
}
