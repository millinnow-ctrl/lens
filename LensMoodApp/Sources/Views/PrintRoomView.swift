import SwiftUI
import UIKit

private enum PrintSurface: String, CaseIterable, Identifiable {
  case wood = "Walnut"
  case linen = "Linen"
  case stone = "Stone"
  case paper = "Paper"

  var id: String { rawValue }

  var color: Color {
    switch self {
    case .wood: return Color(hex: "#5B4636")
    case .linen: return Color(hex: "#D6CDBE")
    case .stone: return Color(hex: "#A7A39B")
    case .paper: return Color(hex: "#E8E3D9")
    }
  }

  var reflectedTint: Color {
    switch self {
    case .wood: return Color(hex: "#8E6548")
    case .linen: return Color(hex: "#E4D8C8")
    case .stone: return Color(hex: "#B8BAB7")
    case .paper: return Color(hex: "#F0E9DB")
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
          VStack(alignment: .leading, spacing: 7) {
            TechnicalLabel(text: "Print room")
            Text("A photograph becomes an object.")
              .font(.system(size: 31, weight: .bold, design: .serif))
              .foregroundStyle(Theme.ink)
            Text("Straight-down composition, true instant-print proportions, and light borrowed from the surface beneath it.")
              .font(.system(size: 14))
              .foregroundStyle(Theme.inkSoft)
              .lineSpacing(4)
          }

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
          .font(.system(size: 20, weight: .bold, design: .serif))
        Text("The Print Room uses a developed frame from your session library.")
          .font(.system(size: 13))
          .foregroundStyle(Theme.inkSoft)
          .multilineTextAlignment(.center)
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
      InstantPrintComposition(asset: selected, surface: surface)
        .aspectRatio(1, contentMode: .fit)
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
        .accessibilityLabel("Instant print of \(selected.stock.name) on \(surface.rawValue)")
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

  private var rotation: Double {
    let value = asset.id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return Double((value % 7) - 3) * 0.24
  }

  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      ZStack {
        surface.color
        RadialGradient(
          colors: [surface.reflectedTint.opacity(0.34), .clear],
          center: .topLeading,
          startRadius: 10,
          endRadius: size.width * 0.9
        )

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
        .overlay(alignment: .bottomLeading) {
          Text(asset.stock.name.uppercased())
            .font(.system(size: max(8, size.width * 0.022), weight: .medium, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(Color.black.opacity(0.54))
            .padding(.leading, size.width * 0.055)
            .padding(.bottom, size.width * 0.04)
        }
        .overlay(Rectangle().stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.28), radius: size.width * 0.018, x: size.width * 0.008, y: size.width * 0.018)
        .rotationEffect(.degrees(rotation))
      }
    }
  }
}
