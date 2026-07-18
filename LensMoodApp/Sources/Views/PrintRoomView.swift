import PhotosUI
import SwiftUI
import UIKit

private enum PrintSurface: String, CaseIterable, Identifiable {
  case wood = "Walnut"
  case linen = "Linen"
  case marble = "Marble"
  case concrete = "Concrete"

  var id: String { rawValue }

  /// bundled photographic surface plate (the reference app's scene assets)
  var imageName: String {
    switch self {
    case .wood: return "wood"
    case .linen: return "linen"
    case .marble: return "marble"
    case .concrete: return "concrete"
    }
  }

  /// fallback + tint base when the plate is missing
  var color: Color {
    switch self {
    case .wood: return Color(hex: "#5B4636")
    case .linen: return Color(hex: "#D6CDBE")
    case .marble: return Color(hex: "#CFCBC4")
    case .concrete: return Color(hex: "#A7A39B")
    }
  }

  var reflectedTint: Color {
    switch self {
    case .wood: return Color(hex: "#8E6548")
    case .linen: return Color(hex: "#E4D8C8")
    case .marble: return Color(hex: "#DDD8CF")
    case .concrete: return Color(hex: "#B8BAB7")
    }
  }

  /// contact shadow character: hard surfaces cast a tighter, darker shadow;
  /// fabric diffuses it. Light stays top-leading everywhere on the stage.
  var shadow: (opacity: Double, blur: Double) {
    switch self {
    case .wood: return (0.30, 0.016)
    case .linen: return (0.20, 0.030)
    case .marble: return (0.34, 0.012)
    case .concrete: return (0.30, 0.018)
    }
  }
}

struct PrintRoomView: View {
  @EnvironmentObject private var model: AppModel
  @State private var pickedPrintItem: PhotosPickerItem?
  @State private var pickedAsset: DevelopedAsset?
  @State private var surface: PrintSurface = .wood
  @State private var saved = false
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var printReveal: CGFloat = 1
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// a photo added here wins; otherwise the latest developed frame prints
  private var selected: DevelopedAsset? {
    pickedAsset ?? model.library.first
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("A photograph becomes an object.")
            .scaledFont(size: 31, weight: .heavy, relativeTo: .largeTitle)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

          addPhotoBubble

          if selected == nil {
            emptyState
          } else {
            surfacePicker
            printStage

            Button(isSaving ? "Saving print" : "Save photographed print") {
              savePrint()
            }
            .buttonStyle(InstrumentButtonStyle(kind: .primary))
            .disabled(isSaving)
          }
        }
        .padding(Theme.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Theme.paper)
      .navigationTitle("Print")
      .navigationBarTitleDisplayMode(.inline)
      .alert("Print saved", isPresented: $saved) {
        Button("OK", role: .cancel) {}
      }
      .alert("Could not save this print", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "Please try again.")
      }
    }
  }

  private var emptyState: some View {
    InstrumentPanel {
      VStack(spacing: 14) {
        Image(systemName: "photo.artframe")
          .scaledFont(size: 34, weight: .ultraLight, relativeTo: .largeTitle)
        Text("Develop a photograph first")
          .font(.title3.weight(.heavy))   // 20pt at the default size
        Button("Choose a camera") {
          model.selectedTab = .cameras
        }
        .buttonStyle(InstrumentButtonStyle(kind: .primary))
      }
      .padding(24)
      .frame(maxWidth: .infinity)
    }
  }

  /// the photo choice lives at the top: one bubble that opens the library
  private var addPhotoBubble: some View {
    PhotosPicker(selection: $pickedPrintItem, matching: .images) {
      HStack(spacing: 8) {
        Image(systemName: "photo.badge.plus")
          .scaledFont(size: 15, weight: .semibold, relativeTo: .subheadline)
        Text("Add a photo")
          .font(.subheadline.weight(.bold))   // 15pt at the default size
          .lineLimit(1)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 24)
      .frame(minHeight: 46)
      .background(Theme.brandFill)
      .clipShape(Capsule())
      .oceanCardShadow()
    }
    .frame(maxWidth: .infinity)
    .onChange(of: pickedPrintItem) { item in loadPrintPhoto(item) }
    .accessibilityHint("Choose a photo from your library to print")
  }

  private func loadPrintPhoto(_ item: PhotosPickerItem?) {
    guard let item else { return }
    Task { @MainActor in
      defer { pickedPrintItem = nil }
      guard let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data) else {
        errorMessage = "That photo could not be read."
        return
      }
      pickedAsset = DevelopedAsset(image: image, source: image, stock: Stock.all[0], decisions: [])
      UISelectionFeedbackGenerator().selectionChanged()
    }
  }

  private var surfacePicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      TechnicalLabel(text: "Surface")
      Picker("Print surface", selection: $surface) {
        ForEach(PrintSurface.allCases) { item in
          Text(item.rawValue).tag(item)
        }
      }
      .pickerStyle(.segmented)
    }
  }

  @ViewBuilder
  private var printStage: some View {
    if let selected {
      InstantPrintComposition(asset: selected, surface: surface, reveal: printReveal)
        .aspectRatio(1, contentMode: .fit)
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
        .accessibilityLabel("Instant print of \(selected.stock.name) on \(surface.rawValue)")
        .onAppear { developIn() }
        .onChange(of: selected.id) { _ in developIn() }
    }
  }

  /// the print-develop ceremony: each new print starts milky and clears.
  /// Reduce Motion: skip the long develop and present the finished print with a
  /// brief crossfade instead of the 2.2s emulsion clear.
  private func developIn() {
    let duration: Double = reduceMotion ? 0.35 : 2.2
    printReveal = 0
    // a soft tap as the print starts developing, a gentle success as it settles
    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    withAnimation(.easeOut(duration: duration)) { printReveal = 1 }
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
  }

  private func savePrint() {
    guard let selected else { return }
    isSaving = true
    let composition = InstantPrintComposition(asset: selected, surface: surface)
      .frame(width: 1200, height: 1200)
    let renderer = ImageRenderer(content: composition)
    renderer.scale = 1
    guard let image = renderer.uiImage else {
      isSaving = false
      errorMessage = "The print could not be rendered. Please try again."
      return
    }

    Task {
      do {
        try await PhotoLibraryWriter.save(image: image)
        isSaving = false
        saved = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch {
        isSaving = false
        errorMessage = error.localizedDescription
      }
    }
  }
}

private struct InstantPrintComposition: View {
  let asset: DevelopedAsset
  let surface: PrintSurface
  /// 0 = fresh milky print, 1 = fully developed (drives the reveal ceremony)
  var reveal: CGFloat = 1

  /// deterministic per-print seed: same photograph always lands the same way
  private var seed: Int {
    asset.id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
  }

  private var rotation: Double {
    Double((seed % 7) - 3) * 0.24
  }

  /// seeded position variation — a real print never lands dead-center
  private var offsetUnit: (x: Double, y: Double) {
    (Double(((seed / 7) % 5) - 2) * 0.008, Double(((seed / 35) % 5) - 2) * 0.008)
  }

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      ZStack {
        // photographic surface plate, color fallback if the asset is missing
        if let plate = BundleMedia.image(surface.imageName) {
          Image(uiImage: plate)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
        } else {
          surface.color
        }
        // lighting consistency: one top-leading key light over the stage
        RadialGradient(
          colors: [surface.reflectedTint.opacity(0.24), .clear],
          center: .topLeading,
          startRadius: 10,
          endRadius: size.width * 0.9
        )
        LinearGradient(
          colors: [.clear, Color.black.opacity(0.16)],
          startPoint: .topLeading, endPoint: .bottomTrailing
        )

        printBody(size: size)
          .rotationEffect(.degrees(rotation))
          .offset(
            x: size.width * offsetUnit.x,
            y: size.width * offsetUnit.y
          )
      }
      .clipped()
    }
  }

  private func printBody(size: CGSize) -> some View {
    // phased chemistry: the emulsion clears first, THEN colour + contrast build
    // in, so the photo emerges the way a real instant print develops. All phases
    // resolve to the finished print at reveal == 1 (so the saved render is exact).
    let clear = min(1, max(0, reveal / 0.45))              // milky clears over 0..0.45
    let chem = min(1, max(0, (reveal - 0.2) / 0.8))        // colour builds over 0.2..1
    let develSaturation = 0.28 + 0.72 * chem
    let develContrast = 0.9 + 0.1 * chem
    let develBrightness = -0.05 * (1 - chem)               // starts slightly dark, warms up
    let settle = 0.985 + 0.015 * reveal                    // gentle settle to full size
    let emergence = (1 - clear) * size.height * 0.035      // slides up into place

    return VStack(spacing: 0) {
      Image(uiImage: asset.image)
        .resizable()
        .scaledToFill()
        .frame(width: size.width * 0.62, height: size.width * 0.62)
        .clipped()
        .saturation(Double(develSaturation))
        .contrast(Double(develContrast))
        .brightness(Double(develBrightness))
        .padding(.top, size.width * 0.055)
      Spacer(minLength: size.width * 0.11)
    }
    .frame(width: size.width * 0.70, height: size.width * 0.85)
    .background(Color(hex: "#F3EBDD"))
    // reflected surface color reaches the paper itself, not just the stage
    .overlay(surface.reflectedTint.opacity(0.07).allowsHitTesting(false))
    // gentle sheet curl: light falls off across the emulsion, top-leading key
    .overlay(
      LinearGradient(
        colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.05)],
        startPoint: .topLeading, endPoint: .bottomTrailing
      )
      .allowsHitTesting(false)
    )
    // no printed branding — the print reads as a photograph you took,
    // not a labeled product (owner ruling)
    .overlay(
      // develop-in ceremony: the image emerges from the milky emulsion, which
      // clears in the first phase (before colour + contrast finish building)
      Rectangle()
        .fill(Color(hex: "#EDE7D8"))
        .opacity(Double(1 - clear))
        .allowsHitTesting(false)
    )
    .overlay(Rectangle().stroke(Color.black.opacity(0.08), lineWidth: 1))
    // paper thickness: a hairline of stacked edge showing on the lit sides
    .background(
      Rectangle()
        .fill(Color(hex: "#D9D0BE"))
        .offset(x: size.width * 0.0035, y: size.width * 0.0045)
    )
    // contact shadow: direction follows the stage's top-leading key light,
    // character (tightness/darkness) follows the surface material
    .shadow(
      color: Color.black.opacity(surface.shadow.opacity),
      radius: size.width * surface.shadow.blur,
      x: size.width * 0.008,
      y: size.width * 0.018
    )
    // subtle physical settle: slides up into place and settles to full size
    .scaleEffect(settle)
    .offset(y: emergence)
  }
}
