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
  @State private var selectedID: UUID?
  @State private var surface: PrintSurface = .wood
  @State private var saved = false
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var printReveal: CGFloat = 1

  private var selected: DevelopedAsset? {
    if let selectedID {
      return model.library.first { $0.id == selectedID }
    }
    return model.library.first
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("A photograph becomes an object.")
            .font(.system(size: 31, weight: .heavy))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

          if model.library.isEmpty {
            emptyState
          } else {
            framePicker
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
          .font(.system(size: 34, weight: .ultraLight))
        Text("Develop a photograph first")
          .font(.system(size: 20, weight: .heavy))
        Button("Choose a camera") {
          model.selectedTab = .cameras
        }
        .buttonStyle(InstrumentButtonStyle(kind: .primary))
      }
      .padding(24)
      .frame(maxWidth: .infinity)
    }
  }

  private var framePicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      TechnicalLabel(text: "Frame")
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(model.library) { asset in
            Button {
              selectedID = asset.id
              UISelectionFeedbackGenerator().selectionChanged()
            } label: {
              Image(uiImage: asset.image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 78)
                .clipped()
                .overlay {
                  Rectangle().stroke(
                    selected?.id == asset.id ? Theme.accent : Theme.hairline,
                    lineWidth: selected?.id == asset.id ? 2 : 1
                  )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(asset.stock.name)
          }
        }
      }
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

  /// the print-develop ceremony: each new print starts milky and clears
  private func developIn() {
    printReveal = 0
    withAnimation(.easeOut(duration: 2.2)) { printReveal = 1 }
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
    VStack(spacing: 0) {
      Image(uiImage: asset.image)
        .resizable()
        .scaledToFill()
        .frame(width: size.width * 0.62, height: size.width * 0.62)
        .clipped()
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
      // develop-in ceremony: the image emerges from the milky emulsion
      Rectangle()
        .fill(Color(hex: "#EDE7D8"))
        .opacity(Double(1 - reveal))
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
  }
}
