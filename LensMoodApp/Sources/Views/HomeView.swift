import SwiftUI

/// Home — the ocean entry screen, restored to the owner-approved reference
/// design (`lensmood-native/app/index.tsx`): brand lockup, living hero card,
/// the 16:9 camcorder tape card, category chips, and the 18-camera shelf of
/// gradient StyleCards with mono EXIF readouts.
struct HomeView: View {
  @EnvironmentObject private var model: AppModel
  @State private var category: StyleCategory = .all
  @State private var path = NavigationPath()

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
            path.append(Stock.all[0])
          }
          .padding(.top, 6)

          sectionHead(title: "Video", subtitle: nil)
          tapeCard

          sectionHead(title: "Explore looks", subtitle: "\(Stock.all.count) cameras, one tap each")
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
            .font(.system(size: 20, weight: .bold))
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
              .font(.system(size: 20))
              .foregroundStyle(Theme.ink)
          }
          .accessibilityLabel("Account and privacy")
        }
      }
    }
  }

  private func sectionHead(title: String, subtitle: String?) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(size: 26, weight: .heavy))
        .tracking(-0.4)
        .foregroundStyle(Theme.ink)
      if let subtitle {
        Text(subtitle)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Theme.fog)
      }
    }
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

        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 7) {
            Circle().fill(Theme.recRed).frame(width: 9, height: 9)
            Text("REC")
              .font(.system(size: 12, weight: .bold))
              .tracking(1)
              .foregroundStyle(Color(hex: "#FFF0DC").opacity(0.95))
              .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
          }
          Spacer()
          Text("Camcorder")
            .font(.system(size: 26, weight: .heavy))
            .tracking(-0.4)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
          Text("Any clip, filmed like 1994 — tap to load a tape.")
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.45), radius: 5, y: 1)
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
    if let ui = UIImage(named: "camcorder-cover") {
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
              .font(.system(size: 14, weight: on ? .bold : .semibold))
              .foregroundStyle(on ? Color.white : Theme.ink)
              .padding(.horizontal, 16)
              .frame(height: 36)
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
            .font(.system(size: 9, weight: .heavy))
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
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
        Text(stock.tagline)
          .font(.system(size: 12.5))
          .foregroundStyle(Theme.inkSoft)
          .lineLimit(2, reservesSpace: true)
        Text(stock.exif)
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .tracking(0.4)
          .foregroundStyle(Theme.fog)
          .lineLimit(1)
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

/// HeroCard — the living hero: dark viewfinder card with the chrome strip,
/// the rotating warm word and the white "Start with a photo" pill.
struct HeroCard: View {
  var onStart: () -> Void

  private static let words = ["mood.", "look.", "texture.", "glow."]
  @State private var word = 0

  var body: some View {
    VStack(spacing: 0) {
      // chrome strip
      HStack {
        HStack(spacing: 7) {
          Circle().fill(Theme.recRed).frame(width: 7, height: 7)
          Text("GOLDEN HOUR")
        }
        Spacer()
        Text("ƒ1.4 · 50MM · WARM")
      }
      .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
      .tracking(1)
      .foregroundStyle(Theme.viewfinderChrome)
      .padding(.horizontal, 14)
      .frame(height: 34)
      .background(Theme.viewfinder)

      // frame: dusk-road gradient poster with a low sun
      ZStack {
        LinearGradient(
          colors: [
            Color(hex: "#2C3E50"), Color(hex: "#7A6247"),
            Color(hex: "#C99B62"), Color(hex: "#8A5A33"),
          ],
          startPoint: .top, endPoint: .init(x: 0.2, y: 1)
        )
        GeometryReader { geo in
          Circle()
            .fill(
              RadialGradient(
                colors: [
                  Color(hex: "#FFEEC8").opacity(0.95),
                  Color(hex: "#FFC878").opacity(0.25),
                  Color(hex: "#FFC878").opacity(0),
                ],
                center: .center,
                startRadius: 0,
                endRadius: geo.size.width * 0.3
              )
            )
            .frame(width: geo.size.width * 0.6, height: geo.size.width * 0.6)
            .position(x: geo.size.width * 0.78, y: geo.size.height * 0.42)
        }

        VStack(spacing: 14) {
          VStack(spacing: 0) {
            Text("Give every photo")
              .font(.system(size: 30, weight: .heavy))
              .tracking(-0.5)
              .foregroundStyle(.white)
            Text(Self.words[word])
              .font(.system(size: 34, weight: .heavy))
              .tracking(-0.5)
              .foregroundStyle(Color(hex: "#FFD9A0"))
              .id(word)
              .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
              ))
          }
          .shadow(color: .black.opacity(0.4), radius: 8, y: 2)

          Button(action: onStart) {
            Text("Start with a photo")
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(Theme.ink)
              .padding(.horizontal, 24)
              .frame(height: 46)
              .background(.white)
              .clipShape(Capsule())
              .oceanCardShadow()
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Start with a photo")
        }
        .padding(.vertical, 30)
      }
      .frame(minHeight: 250)
    }
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .oceanCardShadow(deep: true)
    .onReceive(Timer.publish(every: 3.4, on: .main, in: .common).autoconnect()) { _ in
      withAnimation(.easeInOut(duration: 0.45)) {
        word = (word + 1) % Self.words.count
      }
    }
    .accessibilityElement(children: .contain)
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
