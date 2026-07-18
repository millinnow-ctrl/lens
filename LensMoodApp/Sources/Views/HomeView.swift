import AVFoundation
import PhotosUI
import SwiftUI

/// Home — the ocean entry screen, restored to the owner-approved reference
/// design (`lensmood-native/app/index.tsx`): brand lockup, living hero card,
/// the 16:9 camcorder tape card, category chips, and the 18-camera shelf of
/// gradient StyleCards with mono EXIF readouts.
struct HomeView: View {
  @EnvironmentObject private var model: AppModel
  @State private var category: StyleCategory = .all
  @State private var path = NavigationPath()

  // "Start with a photo" → the standard iOS source chooser
  @State private var showSourceChooser = false
  @State private var showLibraryPicker = false
  @State private var heroPickedItem: PhotosPickerItem?
  @State private var heroPickError: String?
  @State private var carouselIndex = 0

  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
  ]

  private var shelf: [Stock] {
    category.filter(Stock.all)
  }

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          HeroCard {
            showSourceChooser = true
          }
          .padding(.top, 6)

          // the camera carousel — first thing under the hero, like the
          // original home: signature artwork cards, one camera per card
          styleCarousel

          sectionHead(title: "Video", subtitle: nil)
          tapeCard

          sectionHead(title: "Explore looks", subtitle: nil)
          categoryChips

          LazyVGrid(columns: columns, spacing: 12) {
            ForEach(shelf) { stock in
              NavigationLink(value: stock) {
                StyleCard(stock: stock)
              }
              .buttonStyle(.plain)
              .accessibilityHint("Opens \(stock.name) development")
            }
          }
          .padding(.top, 12)
          .animation(.easeOut(duration: 0.18), value: category)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 36)
      }
      .background(Theme.paper)
      .navigationDestination(for: Stock.self) { stock in
        DevelopView(stock: stock)
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          HStack(spacing: 8) {
            ApertureMark()
            HStack(spacing: 0) {
              Text("Lens")
                .foregroundStyle(Theme.ink)
              Text("Mood")
                .foregroundStyle(Theme.accent)
            }
            .font(.title3.weight(.bold))   // 20pt at the default size
            .tracking(-0.3)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("LensMood")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            model.accountPresented = true
          } label: {
            Image(systemName: "person.crop.circle")
              .font(.title3)   // 20pt at the default size
              .foregroundStyle(Theme.ink)
          }
          .accessibilityLabel("Account and privacy")
        }
      }
      // the standard iOS "add a photo" chooser
      .confirmationDialog("Start with a photo", isPresented: $showSourceChooser, titleVisibility: .visible) {
        Button("Take Photo") { model.selectedTab = .capture }
        Button("Choose from Library") { showLibraryPicker = true }
        Button("Cancel", role: .cancel) {}
      }
      .photosPicker(isPresented: $showLibraryPicker, selection: $heroPickedItem, matching: .images)
      .onChange(of: heroPickedItem) { item in loadHeroPhoto(item) }
      // "Shoot this film again" (Library detail) queues a camera; push its
      // develop view whether Home is already alive (onChange) or only built
      // when the tab switch lands (onAppear)
      .onAppear { routePendingStock() }
      .onChange(of: model.pendingStock) { _ in routePendingStock() }
      .alert("Could not open that photo", isPresented: Binding(
        get: { heroPickError != nil }, set: { if !$0 { heroPickError = nil } }
      )) { Button("OK", role: .cancel) {} } message: { Text(heroPickError ?? "Try another photo.") }
    }
  }

  /// push the develop view for a camera queued by "Shoot this film again"
  private func routePendingStock() {
    guard let stock = model.pendingStock else { return }
    model.pendingStock = nil
    path.append(stock)
  }

  /// carry a library pick into a fresh develop session
  private func loadHeroPhoto(_ item: PhotosPickerItem?) {
    guard let item else { return }
    Task { @MainActor in
      defer { heroPickedItem = nil }
      do {
        guard let data = try await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
          heroPickError = "That photo could not be read."
          return
        }
        model.pendingDevelopImage = image
        path.append(Stock.all[0])
      } catch {
        heroPickError = error.localizedDescription
      }
    }
  }

  /// StyleCarousel — the original home carousel: snap-scrolling portrait
  /// cards, each wearing its camera's signature artwork, badge, and tagline.
  /// Scroll is signalled three ways: a coverflow 3D tilt as cards approach
  /// the edges, deep drop shadows, and a trailing fade the cards slide under.
  private var styleCarousel: some View {
    VStack(spacing: 8) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 14) {
          ForEach(Array(Stock.all.enumerated()), id: \.element.id) { index, stock in
            Button {
              path.append(stock)
            } label: {
              CarouselCard(stock: stock, index: index)
                .modifier(CarouselDepth())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(stock.name). \(stock.tagline)")
          }
        }
        .padding(.horizontal, 4)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(
          GeometryReader { g in
            Color.clear.preference(
              key: CarouselOffsetKey.self,
              value: -g.frame(in: .named("carousel")).minX
            )
          }
        )
      }
      .coordinateSpace(name: "carousel")
      .onPreferenceChange(CarouselOffsetKey.self) { offset in
        // 144pt card + 14pt gap; tick the haptic as each card passes center
        let index = max(0, min(Stock.all.count - 1, Int((offset / 158).rounded())))
        if index != carouselIndex {
          carouselIndex = index
          UISelectionFeedbackGenerator().selectionChanged()
        }
      }
      // the cards slide under a soft edge with a chevron — more to the right
      .overlay(alignment: .trailing) {
        ZStack(alignment: .trailing) {
          LinearGradient(
            colors: [Theme.paper.opacity(0), Theme.paper],
            startPoint: .leading, endPoint: .trailing
          )
          .frame(width: 46)
          Image(systemName: "chevron.compact.right")
            .scaledFont(size: 27, weight: .semibold, relativeTo: .title)
            .foregroundStyle(Theme.fog.opacity(0.55))
            .padding(.trailing, 2)
        }
        .allowsHitTesting(false)
      }

      // page dots — the scroll position, one dot per camera
      HStack(spacing: 6) {
        ForEach(0..<Stock.all.count, id: \.self) { i in
          Capsule()
            .fill(i == carouselIndex ? Theme.accent : Theme.fog.opacity(0.45))
            .frame(width: i == carouselIndex ? 20 : 7, height: 7)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: carouselIndex)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.bottom, 6)
    }
    .padding(.top, 4)
  }

  // headings stand alone and centered — the owner's copy principle
  private func sectionHead(title: String, subtitle: String?) -> some View {
    Text(title)
      .scaledFont(size: 26, weight: .heavy, relativeTo: .title)
      .tracking(-0.4)
      .foregroundStyle(Theme.ink)
      .frame(maxWidth: .infinity)
      .multilineTextAlignment(.center)
      .padding(.top, 24)
      .padding(.bottom, 12)
  }

  /// the camcorder is the whole story: one big 16:9 tape frame,
  /// the whole picture is the button
  private var tapeCard: some View {
    Button {
      model.selectedTab = .tape
    } label: {
      ZStack(alignment: .topLeading) {
        tapePoster
          .aspectRatio(16.0 / 9.0, contentMode: .fit)

        // reference videoScrim: keeps the title legible over the cover's own
        // baked-in tape timestamp
        LinearGradient(
          colors: [.clear, .black.opacity(0.62)],
          startPoint: .center, endPoint: .bottom
        )

        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 7) {
            Circle().fill(Theme.recRed).frame(width: 9, height: 9)
            Text("REC")
              .font(.caption.weight(.bold))   // 12pt at the default size
              .tracking(1)
              .foregroundStyle(Color(hex: "#FFF0DC").opacity(0.95))
              .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
          }
          Spacer()
          Text("Camcorder")
            .scaledFont(size: 26, weight: .heavy, relativeTo: .title)
            .tracking(-0.4)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
        }
        .padding(16)
      }
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .oceanCardShadow(deep: true)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open the camcorder")
  }

  @ViewBuilder
  private var tapePoster: some View {
    if let ui = BundleMedia.image("camcorder-cover") {
      Image(uiImage: ui)
        .resizable()
        .scaledToFill()
    } else {
      // engine-made fallback: the tape deck's dusk gradient
      Rectangle().fill(
        LinearGradient(
          colors: [Color(hex: "#2C3E50"), Color(hex: "#5B6B5C"), Color(hex: "#8A9A7B")],
          startPoint: .topLeading, endPoint: .bottomTrailing
        )
      )
    }
  }

  private var categoryChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(StyleCategory.allCases, id: \.self) { cat in
          let on = category == cat
          Button {
            category = cat
          } label: {
            Text(cat.label)
              .scaledFont(size: 14, weight: on ? .bold : .semibold, relativeTo: .footnote)
              .lineLimit(1)
              .foregroundStyle(on ? Color.white : Theme.ink)
              .padding(.horizontal, 16)
              // minHeight, not height: the chip may grow with the type setting
              .frame(minHeight: 36)
              .background(on ? AnyShapeStyle(Theme.brandFill) : AnyShapeStyle(Theme.surface))
              .clipShape(Capsule())
              .overlay {
                if !on { Capsule().stroke(Theme.hairline, lineWidth: 1) }
              }
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(on ? .isSelected : [])
        }
      }
      .padding(.vertical, 2)
    }
  }
}

/// which looks belong to which shelf (reference `CATEGORY_STYLES`)
enum StyleCategory: CaseIterable, Hashable {
  case all, film, flash, video, editorial, bw

  var label: String {
    switch self {
    case .all: return "All"
    case .film: return "Film"
    case .flash: return "Flash"
    case .video: return "Video"
    case .editorial: return "Editorial"
    case .bw: return "B&W"
    }
  }

  private var ids: [String] {
    switch self {
    case .all: return []
    case .film: return ["disposable", "leica-street", "a24-still", "film-noir", "polaroid", "super-8", "lomo", "kodachrome", "tintype"]
    case .flash: return ["iphone-flash", "y2k-digicam", "disposable", "photobooth", "tokyo-neon", "point-shoot"]
    case .video: return ["camcorder-90s", "y2k-digicam", "security-cam", "super-8"]
    case .editorial: return ["gq-editorial", "leica-street", "a24-still", "pastel-cinema"]
    case .bw: return ["film-noir", "tintype", "photobooth", "security-cam"]
    }
  }

  func filter(_ stocks: [Stock]) -> [Stock] {
    if self == .all { return stocks }
    let wanted = ids
    return stocks.filter { wanted.contains($0.id) }
  }
}

/// reports how far the carousel strip has scrolled, so the page dots and the
/// per-card haptic tick can follow the finger
private struct CarouselOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// CarouselDepth — the coverflow scroll cue. As a card scrolls toward either
/// edge it tilts in 3D around the vertical axis and eases back slightly, so
/// the strip reads as a rotating rack of cards you can push. iOS 17+ uses the
/// interactive scroll transition; on iOS 16 the deep shadow + edge fade + the
/// peeking next card still signal scrollability.
private struct CarouselDepth: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    // Reduce Motion: drop the 3D coverflow tilt; keep a gentle scale/opacity
    // falloff so depth still reads without vestibular-triggering rotation.
    if #available(iOS 17.0, *) {
      content.scrollTransition(.interactive, axis: .horizontal) { view, phase in
        view
          .rotation3DEffect(
            .degrees(reduceMotion ? 0 : phase.value * -34),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.7
          )
          .scaleEffect(phase.isIdentity ? 1 : (reduceMotion ? 0.94 : 0.86))
          .opacity(phase.isIdentity ? 1 : 0.72)
      }
    } else {
      content
    }
  }
}

/// CarouselCard — one camera in the home carousel: 4:5 signature artwork,
/// chrome badge, name + LM index + tagline. Ported from the original web
/// StyleCarousel.
struct CarouselCard: View {
  let stock: Stock
  let index: Int

  private var badgeLabel: String? {
    switch stock.badge {
    case "trending": return "TRENDING"
    case "featured": return "THIS WEEK"
    case "new": return "NEW"
    default: return nil
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topTrailing) {
        artwork
          .frame(width: 144, height: 180)
          .clipped()
        if let badgeLabel {
          Text(badgeLabel)
            .scaledFont(size: 8.5, weight: .heavy, relativeTo: .caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(.black.opacity(0.55))
            .clipShape(Capsule())
            .padding(6)
        }
      }

      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline) {
          Text(stock.name)
            .font(.footnote.weight(.bold))   // 13pt at the default size
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
          Spacer(minLength: 4)
          Text("LM·\(String(format: "%02d", index + 1))")
            .scaledFont(size: 8.5, weight: .semibold, design: .monospaced, relativeTo: .caption2)
            .lineLimit(1)
            .foregroundStyle(Theme.fog)
        }
        Text(stock.tagline)
          .font(.caption2)   // 11pt at the default size
          .foregroundStyle(Theme.inkSoft)
          .lineLimit(2, reservesSpace: true)
      }
      .padding(10)
    }
    .frame(width: 144)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Theme.hairline, lineWidth: 1)
    )
    // a real drop shadow so the cards read as physical, stacked objects
    .shadow(color: Color(hex: "#0C2430").opacity(0.16), radius: 16, x: 0, y: 12)
    .shadow(color: Color(hex: "#0C2430").opacity(0.08), radius: 3, x: 0, y: 2)
  }

  @ViewBuilder
  private var artwork: some View {
    if let art = BundleMedia.image("style-\(stock.id)") {
      Image(uiImage: art)
        .resizable()
        .scaledToFill()
    } else {
      LinearGradient(
        colors: [Color(hex: stock.g0), Color(hex: stock.g1)],
        startPoint: .topLeading, endPoint: .bottomTrailing
      )
    }
  }
}

/// StyleCard — one camera in the chooser grid, restored to the reference
/// design: white ocean surface, the stock's accent gradient as a header bar
/// with an optional badge pill, name + tagline + a mono EXIF readout.
struct StyleCard: View {
  let stock: Stock

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topLeading) {
        LinearGradient(
          colors: [Color(hex: stock.g0), Color(hex: stock.g1)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        if let badge = stock.badge {
          Text(badge.uppercased())
            .scaledFont(size: 9, weight: .heavy, relativeTo: .caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .tracking(0.8)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.92))
            .clipShape(Capsule())
            .padding(8)
        }
      }
      .frame(height: 84)

      VStack(alignment: .leading, spacing: 4) {
        Text(stock.name)
          .font(.callout.weight(.bold))   // 16pt at the default size
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Text(stock.tagline)
          .scaledFont(size: 12.5, relativeTo: .caption)
          .foregroundStyle(Theme.inkSoft)
          .lineLimit(2, reservesSpace: true)
        Text(stock.exif)
          .scaledFont(size: 10, weight: .medium, design: .monospaced, relativeTo: .caption2)
          .tracking(0.4)
          .foregroundStyle(Theme.fog)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .padding(.top, 3)
      }
      .padding(12)
    }
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    .oceanCardShadow()
    .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
  }
}

/// HeroCard — the living hero, restored from the original web home: the
/// ambient summer-picnic loop (a Y2K digicam frame) under the rotating
/// headline "Every photo has a mood. / look. / texture. / glow." Falls back
/// to the poster, then to the dusk gradient, when the loop is absent.
struct HeroCard: View {
  var onStart: () -> Void

  private static let words = ["mood.", "look.", "texture.", "glow."]
  /// held statically so view re-evaluations don't resubscribe a fresh timer
  /// (which froze the rotation while the carousel was interacting)
  private static let wordTimer = Timer.publish(every: 3.4, on: .main, in: .common).autoconnect()
  @State private var word = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      // chrome strip — the readout names the roll on frame
      HStack {
        HStack(spacing: 7) {
          Circle().fill(Theme.recRed).frame(width: 7, height: 7)
          Text("SUMMER ROLL")
        }
        Spacer()
        Text("Y2K DIGICAM · SUNNY")
      }
      .scaledFont(size: 10.5, weight: .semibold, design: .monospaced, relativeTo: .caption2)
      // one tight chrome strip: grown readouts shrink a touch, never wrap
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .tracking(1)
      .foregroundStyle(Theme.viewfinderChrome)
      .padding(.horizontal, 14)
      .frame(minHeight: 34)
      .background(Theme.viewfinder)

      ZStack(alignment: .bottomLeading) {
        poster

        // scrim carries the words
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0),
            .init(color: .black.opacity(0.45), location: 0.55),
            .init(color: .black.opacity(0.85), location: 1),
          ],
          startPoint: .top, endPoint: .bottom
        )

        // "shot on" tag — these are real frames from the engine's cameras
        VStack {
          HStack(spacing: 6) {
            Circle().fill(Theme.recRed).frame(width: 4, height: 4)
            Text("SHOT ON LENSMOOD")
              .scaledFont(size: 9, weight: .semibold, design: .monospaced, relativeTo: .caption2)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
              .tracking(1.2)
          }
          .foregroundStyle(.white.opacity(0.9))
          .padding(.horizontal, 10)
          .frame(minHeight: 24)
          .background(.black.opacity(0.45))
          .clipShape(Capsule())
          .frame(maxWidth: .infinity, alignment: .leading)
          Spacer()
        }
        .padding(12)

        VStack(alignment: .leading, spacing: 6) {
          // two deliberate lines: "Every photo" / "has a {word}" — keeps the
          // animated word anchored to line two instead of wrapping up to line one
          VStack(alignment: .leading, spacing: -2) {
            Text("Every photo")
              .scaledFont(size: 30, weight: .heavy, relativeTo: .largeTitle)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
              Text("has a ")
                .scaledFont(size: 30, weight: .heavy, relativeTo: .largeTitle)
              Text(Self.words[word])
                .scaledFont(size: 30, weight: .heavy, design: .serif, relativeTo: .largeTitle)
                .italic()
                .foregroundStyle(Color(hex: "#FFD9A0"))
                .id(word)
                .transition(reduceMotion
                  ? .opacity
                  : .asymmetric(
                      insertion: .move(edge: .bottom).combined(with: .opacity),
                      removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
          }
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .foregroundStyle(.white)
          .shadow(color: .black.opacity(0.5), radius: 7, y: 1)

          Button(action: onStart) {
            HStack(spacing: 8) {
              Image(systemName: "photo.badge.plus")
                .scaledFont(size: 15, weight: .semibold, relativeTo: .subheadline)
              Text("Start with a photo")
                .font(.subheadline.weight(.bold))   // 15pt at the default size
                .lineLimit(1)
                .minimumScaleFactor(0.8)
              Image(systemName: "chevron.down")
                .scaledFont(size: 10, weight: .bold, relativeTo: .caption2)
                .opacity(0.45)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(.white)
            .clipShape(Capsule())
          }
          .buttonStyle(.plain)
          .padding(.top, 8)
          .accessibilityLabel("Start with a photo")
          .accessibilityHint("Opens options to take a photo or choose from your library")
        }
        .padding(16)
      }
      .aspectRatio(4.0 / 3.6, contentMode: .fit)
      .clipped()
    }
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .oceanCardShadow(deep: true)
    .onReceive(Self.wordTimer) { _ in
      withAnimation(.easeInOut(duration: 0.34)) {
        word = (word + 1) % Self.words.count
      }
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var poster: some View {
    if let url = BundleMedia.videoURL("hero-summer") {
      LoopingVideoView(url: url)
    } else if let still = BundleMedia.image("hero-summer-poster") {
      Image(uiImage: still)
        .resizable()
        .scaledToFill()
    } else {
      LinearGradient(
        colors: [
          Color(hex: "#2C3E50"), Color(hex: "#7A6247"),
          Color(hex: "#C99B62"), Color(hex: "#8A5A33"),
        ],
        startPoint: .top, endPoint: .init(x: 0.2, y: 1)
      )
    }
  }
}

/// a muted, endlessly looping, aspect-filling video layer — the ambient
/// hero loop. No controls, no audio session impact.
private struct LoopingVideoView: UIViewRepresentable {
  let url: URL

  func makeUIView(context: Context) -> LoopingPlayerUIView {
    let view = LoopingPlayerUIView()
    view.configure(url: url)
    return view
  }

  func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}
}

final class LoopingPlayerUIView: UIView {
  private var looper: AVPlayerLooper?
  private var player: AVQueuePlayer?

  override class var layerClass: AnyClass { AVPlayerLayer.self }

  private var playerLayer: AVPlayerLayer {
    // swiftlint:disable:next force_cast
    layer as! AVPlayerLayer
  }

  func configure(url: URL) {
    let item = AVPlayerItem(url: url)
    let queue = AVQueuePlayer()
    queue.isMuted = true
    queue.preventsDisplaySleepDuringVideoPlayback = false
    looper = AVPlayerLooper(player: queue, templateItem: item)
    playerLayer.player = queue
    playerLayer.videoGravity = .resizeAspectFill
    queue.play()
    player = queue
  }
}

private struct ApertureMark: View {
  var body: some View {
    ZStack {
      Circle().stroke(Theme.accent, lineWidth: 1.5)
      Circle().fill(Theme.accent).frame(width: 8, height: 8)
      Circle().fill(.white).frame(width: 3, height: 3)
    }
    .frame(width: 22, height: 22)
  }
}

#Preview {
  HomeView().environmentObject(AppModel())
}
