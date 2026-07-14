import PhotosUI
import SwiftUI
import UIKit

private enum PreviewMode: String, CaseIterable, Identifiable {
  case original = "Original"
  case developed = "Developed"
  case compare = "Compare"

  var id: String { rawValue }
}

struct DevelopView: View {
  init(stock: Stock) {
    _currentStock = State(initialValue: stock)
  }

  /// the loaded camera — switchable in place via the StyleRail below the stage
  @State private var currentStock: Stock

  @EnvironmentObject private var model: AppModel
  @State private var pickedItem: PhotosPickerItem?
  @State private var sourceImage: UIImage?
  @State private var developedImage: UIImage?
  @State private var decisions: [String] = []
  @State private var previewMode: PreviewMode = .developed
  @State private var compareFraction: CGFloat = 0.5
  @State private var isDeveloping = false
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var sharePresented = false
  @State private var saveConfirmation = false
  @State private var renderID = UUID()
  /// the library entry for the current photograph — switching cameras replaces
  /// it instead of flooding the Gallery with one near-duplicate per camera
  @State private var sessionAssetID: UUID?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        cameraIdentity
        stage
        styleRail
        previewControl

        if isDeveloping {
          developingState
        } else if sourceImage == nil {
          photoPicker(title: "Choose a photograph")
        } else {
          actions
          if !decisions.isEmpty { decisionPanel }
        }

        characterCard

      }
      .padding(Theme.pagePadding)
    }
    .background(Theme.paper)
    .navigationTitle(currentStock.name)
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: pickedItem) { item in
      load(item)
    }
    .onAppear {
      // a photo chosen from the Home hero develops immediately on arrival
      if let pending = model.pendingDevelopImage {
        model.pendingDevelopImage = nil
        sourceImage = pending
        develop(pending)
      }
    }
    .sheet(isPresented: $sharePresented) {
      if let developedImage {
        ActivitySheet(items: [developedImage])
      }
    }
    .alert("Saved to Photos", isPresented: $saveConfirmation) {
      Button("OK", role: .cancel) {}
    }
    .alert("Could not develop this photograph", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "Try another photograph.")
    }
  }

  /// StyleRail — the horizontal camera switcher from the reference app:
  /// gradient swatch chips, ocean ring on the active camera. Selecting
  /// re-develops the loaded photograph in place.
  private var styleRail: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Stock.all) { item in
            railChip(item)
          }
        }
        .padding(.vertical, 2)
      }
      .onAppear { proxy.scrollTo(currentStock.id, anchor: .center) }
    }
    .accessibilityLabel("Camera switcher")
  }

  private func railChip(_ item: Stock) -> some View {
    let active = item.id == currentStock.id
    return Button {
      guard item.id != currentStock.id else { return }
      currentStock = item
      UISelectionFeedbackGenerator().selectionChanged()
      if let sourceImage {
        develop(sourceImage)
      }
    } label: {
      VStack(spacing: 5) {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color(hex: item.g0), Color(hex: item.g1)],
              startPoint: .topLeading, endPoint: .bottomTrailing
            )
          )
          .frame(width: 40, height: 40)
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(active ? Theme.accent : Theme.hairline, lineWidth: active ? 2.5 : 1)
          }
        Text(item.name)
          .font(.system(size: 10, weight: active ? .bold : .medium))
          .foregroundStyle(active ? Theme.ink : Theme.fog)
          .lineLimit(1)
      }
      .frame(width: 62)
    }
    .buttonStyle(.plain)
    .id(item.id)
    .accessibilityLabel("Develop with \(item.name)")
    .accessibilityAddTraits(active ? .isSelected : [])
  }

  private var cameraIdentity: some View {
    VStack(alignment: .center, spacing: 5) {
      TechnicalLabel(text: currentStock.exif)
      Text(currentStock.tagline)
        .font(.system(size: 23, weight: .heavy))
        .foregroundStyle(Theme.ink)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
  }

  /// The look's structured identity (StyleDefinition) — tells the user *why*
  /// this stock exists and what it's for, so 18 looks don't read as one filter
  /// pack. Keyed by stock id; updates live as the StyleRail switches cameras.
  private var characterCard: some View {
    let def = StyleDefinition.forStock(id: currentStock.id)
    return InstrumentPanel {
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 8) {
          Image(systemName: def.isMonochrome ? "circle.righthalf.filled" : "camera.aperture")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
          Text(def.emotionalTone)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.ink)
        }
        Text(def.cameraInspiration)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Theme.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
        Text(def.palette)
          .font(.system(size: 12))
          .foregroundStyle(Theme.fog)
          .fixedSize(horizontal: false, vertical: true)
        if !def.suitableSubjects.isEmpty {
          VStack(alignment: .leading, spacing: 3) {
            TechnicalLabel(text: "Best for")
            Text(def.suitableSubjects.joined(separator: "  ·  "))
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(Theme.inkSoft)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.top, 1)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(currentStock.name). \(def.emotionalTone). Inspired by \(def.cameraInspiration). Best for \(def.suitableSubjects.joined(separator: ", ")).")
  }

  private var stage: some View {
    ZStack {
      Rectangle()
        .fill(Theme.viewfinder)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)

      if let sourceImage {
        preview(source: sourceImage, developed: developedImage)
      } else {
        VStack(spacing: 12) {
          Image(systemName: currentStock.symbol)
            .font(.system(size: 34, weight: .light))
          Text("Load one photograph")
            .font(.system(size: 17, weight: .semibold))
        }
        .foregroundStyle(Theme.viewfinderChrome)
      }
    }
    .overlay(alignment: .top) {
      HStack {
        Text(currentStock.name.uppercased())
        Spacer()
        Text(isDeveloping ? "DEVELOPING" : currentStock.exif)
      }
      .font(.system(size: 9, weight: .semibold, design: .monospaced))
      .tracking(0.8)
      .foregroundStyle(Theme.viewfinderChrome)
      .padding(11)
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    .oceanCardShadow(deep: true)
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func preview(source: UIImage, developed: UIImage?) -> some View {
    GeometryReader { geometry in
      let size = geometry.size
      ZStack(alignment: .leading) {
        switch previewMode {
        case .original:
          fittedImage(source)
        case .developed:
          fittedImage(developed ?? source)
        case .compare:
          fittedImage(source)
          if let developed {
            fittedImage(developed)
              .frame(width: size.width * compareFraction, alignment: .leading)
              .clipped()
            Rectangle()
              .fill(Theme.paper)
              .frame(width: 1)
              .offset(x: size.width * compareFraction)
            Circle()
              .fill(Theme.paper)
              .overlay(Circle().stroke(Theme.ink, lineWidth: 1))
              .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 10, weight: .bold)))
              .frame(width: 30, height: 30)
              .offset(x: size.width * compareFraction - 15)
          }
        }
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard previewMode == .compare else { return }
            compareFraction = min(1, max(0, value.location.x / max(1, size.width)))
          }
      )
    }
  }

  private func fittedImage(_ image: UIImage) -> some View {
    Image(uiImage: image)
      .resizable()
      .scaledToFit()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var previewControl: some View {
    Picker("Preview", selection: $previewMode) {
      ForEach(PreviewMode.allCases) { mode in
        Text(mode.rawValue).tag(mode)
      }
    }
    .pickerStyle(.segmented)
    .disabled(developedImage == nil)
    .accessibilityHint("Choose the original, developed, or split comparison")
  }

  private var developingState: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        ProgressView().tint(Theme.accent)
        Text("Reading the photograph")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Theme.ink)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(Theme.surface)
    .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
  }

  private var actions: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        photoPicker(title: "New photograph")
        Button(isSaving ? "Preparing full resolution" : "Save") { save() }
          .buttonStyle(InstrumentButtonStyle(kind: .primary))
          .disabled(developedImage == nil || isSaving)
      }
      Button("Share developed photograph") {
        sharePresented = true
      }
      .buttonStyle(InstrumentButtonStyle(kind: .secondary))
      .disabled(developedImage == nil)
    }
  }

  private func photoPicker(title: String) -> some View {
    PhotosPicker(selection: $pickedItem, matching: .images) {
      Text(title)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(InstrumentButtonStyle(kind: .secondary))
  }

  private var decisionPanel: some View {
    InstrumentPanel {
      VStack(alignment: .leading, spacing: 14) {
        TechnicalLabel(text: "Development decisions")
        ForEach(Array(decisions.enumerated()), id: \.offset) { index, decision in
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(String(format: "%02d", index + 1))
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(Theme.accent)
            Text(decision)
              .font(.system(size: 14))
              .foregroundStyle(Theme.ink)
          }
        }
      }
      .padding(16)
    }
  }

  private func load(_ item: PhotosPickerItem?) {
    guard let item else { return }
    isDeveloping = true
    errorMessage = nil
    Task { @MainActor in
      do {
        guard let data = try await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
          throw FilmEngineError.unreadableImage
        }
        sourceImage = image
        sessionAssetID = nil   // a new photograph starts a new library entry
        develop(image)
      } catch {
        isDeveloping = false
        errorMessage = error.localizedDescription
      }
    }
  }

  private func develop(_ image: UIImage) {
    let request = UUID()
    renderID = request
    isDeveloping = true
    developedImage = nil
    decisions = []
    let recipe = currentStock.recipe
    let seed = Double(currentStock.id.unicodeScalars.reduce(17) { ($0 * 31 + Int($1.value)) % 100_000 })

    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result {
        try FilmEngine.shared.develop(
          image,
          with: recipe,
          maxPixelSize: 2048,
          seed: seed
        )
      }
      DispatchQueue.main.async {
        guard renderID == request else { return }
        isDeveloping = false
        switch result {
        case .success(let render):
          developedImage = render.image
          decisions = render.decisions
          previewMode = .developed
          let asset = DevelopedAsset(
            image: render.image,
            source: image,
            stock: currentStock,
            decisions: render.decisions
          )
          if let previous = sessionAssetID { model.remove(id: previous) }
          model.add(asset)
          sessionAssetID = asset.id
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }

  private func save() {
    guard let sourceImage else { return }
    isSaving = true
    let recipe = currentStock.recipe
    let seed = Double(currentStock.id.unicodeScalars.reduce(17) { ($0 * 31 + Int($1.value)) % 100_000 })
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result {
        // 4096 keeps peak memory safe on 2–3 GB devices (8192 risked jetsam)
        try FilmEngine.shared.develop(sourceImage, with: recipe, maxPixelSize: 4096, seed: seed).image
      }
      DispatchQueue.main.async {
        switch result {
        case .success(let fullResolution):
          Task { @MainActor in
            do {
              try await PhotoLibraryWriter.save(image: fullResolution)
              isSaving = false
              saveConfirmation = true
              UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
              isSaving = false
              errorMessage = error.localizedDescription
            }
          }
        case .failure(let error):
          isSaving = false
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    DevelopView(stock: Stock.all[0])
      .environmentObject(AppModel())
  }
}
