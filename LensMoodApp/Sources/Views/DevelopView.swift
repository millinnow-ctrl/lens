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
  /// look strength (0 = original, 1 = fully developed). Applied live in the
  /// developed preview and at save/share; 1.0 keeps the full develop unchanged.
  @State private var intensity: CGFloat = 1.0
  @State private var isDeveloping = false
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var sharePresented = false
  @State private var saveConfirmation = false
  @State private var renderID = UUID()
  /// Per-import session id so the preview cache never reuses one photo's render
  /// for another. Reset whenever a new photograph is loaded.
  @State private var photoKey = UUID()
  /// the library entry for the current photograph — switching cameras replaces
  /// it instead of flooding the Gallery with one near-duplicate per camera
  @State private var sessionAssetID: UUID?
  /// "For this photo" — the Conductor's ranking of which cameras will love
  /// the loaded photograph. nil until the read finishes; the rail then
  /// reorders to the ranked looks.
  @State private var matches: [LookMatch]?
  /// the develop ceremony — real pipeline steps only (truth law): while the
  /// Conductor reads, one line; once read, the steps it truly ran appear as
  /// done and Developing becomes the active one
  @State private var ceremonySteps: [String] = []
  @State private var ceremonyActiveIndex = 0
  /// the memory-bounded copy of the original stored in the Library (the
  /// full-res `sourceImage` stays only for the on-screen stage + export)
  @State private var librarySource: UIImage?
  /// the composited share frame, built off-main in the button action
  @State private var shareImage: UIImage?
  /// the single gate site: developing a locked camera opens the offer
  /// (inert while Store.everythingFreeForNow)
  @State private var paywallPresented = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        cameraIdentity
        stage
        styleRail
        previewControl
        if developedImage != nil { strengthControl }

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
    // No forget on disappear: a tab switch fires onDisappear while this
    // view's state (and its photo) live on, and dropping the reading would
    // force a fresh subject pass — splitting export from preview. The
    // Conductor's small LRU cap bounds memory instead; load() still forgets
    // the replaced photo's key explicitly.
    .sheet(isPresented: $sharePresented) {
      if let shareImage {
        ActivitySheet(items: [shareImage])
      }
    }
    .sheet(isPresented: $paywallPresented) {
      PaywallView()
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

  /// the rail's order: the Conductor's ranking once the photo is read,
  /// catalog order before then (and before any photo is loaded)
  private var railStocks: [Stock] {
    guard let matches else { return Stock.all }
    return matches.map { Stock.find($0.stockID) }
  }

  /// StyleRail — the horizontal camera switcher from the reference app:
  /// gradient swatch chips, ocean ring on the active camera. Selecting
  /// re-develops the loaded photograph in place. Once the Conductor has read
  /// the photograph, the rail reorders to the looks that will love it.
  private var styleRail: some View {
    VStack(alignment: .leading, spacing: 7) {
      if let top = matches?.first {
        HStack(spacing: 8) {
          TechnicalLabel(text: "For this photo")
          if let reason = top.reason {
            Text(reason)
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(Theme.fog)
              .lineLimit(1)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cameras reordered for this photo." + (top.reason.map { " \($0)." } ?? ""))
      }
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(railStocks) { item in
              railChip(item)
            }
          }
          .padding(.vertical, 2)
        }
        .onAppear { proxy.scrollTo(currentStock.id, anchor: .center) }
        // when the rail reorders for the photo, keep the active camera in view
        .onChange(of: matches) { _ in
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            proxy.scrollTo(currentStock.id, anchor: .center)
          }
        }
      }
      .accessibilityLabel("Camera switcher")
    }
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
          .overlay(alignment: .bottomTrailing) {
            // membership gate marker — invisible while every gate is open
            if !Store.shared.isUnlocked(item) {
              Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(3)
                .background(Circle().fill(Theme.ink.opacity(0.72)))
                .offset(x: 4, y: 4)
            }
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
          // strength blend: the developed frame over the original at `intensity`
          fittedImage(source)
          if let developed {
            fittedImage(developed).opacity(Double(intensity))
          }
        case .compare:
          fittedImage(source)
          if let developed {
            // the developed side honors the strength slider — the compare
            // wipe must show exactly what Save will produce
            ZStack(alignment: .leading) {
              fittedImage(source)
              fittedImage(developed).opacity(Double(intensity))
            }
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

  /// look strength — how far to carry the developed look over the original
  private var strengthControl: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        TechnicalLabel(text: "Strength")
        Spacer()
        Text("\(Int((intensity * 100).rounded()))%")
          .font(.system(size: 12, weight: .semibold, design: .monospaced))
          .foregroundStyle(Theme.inkSoft)
      }
      Slider(value: $intensity, in: 0...1) { editing in
        if !editing { UISelectionFeedbackGenerator().selectionChanged() }
      }
      .tint(Theme.accent)
      .onChange(of: intensity) { _ in
        // adjusting strength always reads against the developed view
        if previewMode != .developed { previewMode = .developed }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Look strength")
    .accessibilityValue("\(Int((intensity * 100).rounded())) percent")
  }


  private var developingState: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(ceremonySteps.enumerated()), id: \.offset) { index, step in
        HStack(spacing: 10) {
          if index < ceremonyActiveIndex {
            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Theme.accent)
              .frame(width: 16)
          } else {
            ProgressView()
              .tint(Theme.accent)
              .scaleEffect(0.75)
              .frame(width: 16)
          }
          Text(step)
            .font(.system(size: 14, weight: index == ceremonyActiveIndex ? .semibold : .medium))
            .foregroundStyle(index == ceremonyActiveIndex ? Theme.ink : Theme.inkSoft)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(Theme.surface)
    .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(ceremonySteps.indices.contains(ceremonyActiveIndex)
      ? ceremonySteps[ceremonyActiveIndex] : "Developing")
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
        // composite off-main; presenting inside the sheet's body re-ran the
        // full-frame blend on every view evaluation
        guard let developedImage, let sourceImage else { return }
        let strength = intensity
        Task.detached(priority: .userInitiated) {
          let composed = blended(developed: developedImage, over: sourceImage, intensity: strength)
          await MainActor.run {
            shareImage = composed
            Analytics.log(.photoShared)
            sharePresented = true
          }
        }
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
    // seed the ceremony NOW: the transferable load (slow for iCloud
    // originals) runs before develop() seeds it, and the panel must never
    // show the previous photo's finished steps — or nothing at all
    ceremonySteps = ["Reading the light"]
    ceremonyActiveIndex = 0
    Task { @MainActor in
      do {
        guard let data = try await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
          throw FilmEngineError.unreadableImage
        }
        sourceImage = image
        sessionAssetID = nil   // a new photograph starts a new library entry
        librarySource = nil    // new photo ⇒ rebuild the bounded library copy
        Conductor.shared.forget(key: photoKey)
        photoKey = UUID()      // new photo ⇒ fresh preview-cache + reading scope
        matches = nil          // rail returns to catalog order until the read lands
        develop(image)
      } catch {
        isDeveloping = false
        errorMessage = error.localizedDescription
      }
    }
  }

  private func develop(_ image: UIImage) {
    // THE gate site: every render of a locked camera stops here and shows the
    // offer instead. A no-op while Store.everythingFreeForNow keeps all 18 open.
    guard Store.shared.isUnlocked(currentStock) else {
      isDeveloping = false
      paywallPresented = true
      return
    }
    Analytics.log(.developStarted(lookID: currentStock.id))
    let request = UUID()
    renderID = request
    isDeveloping = true
    developedImage = nil
    decisions = []
    let recipe = currentStock.recipe
    let seed = Double(currentStock.id.unicodeScalars.reduce(17) { ($0 * 31 + Int($1.value)) % 100_000 })
    let startedAt = CFAbsoluteTimeGetCurrent()
    // Device-tier proxy size (replaces the hardcoded 2048 cap): smaller on
    // constrained or thermally-throttled phones, larger on high-end ones.
    let edge = DeviceCapability.current.previewMaxEdge
    let cacheKey = PreviewCache.key(photo: photoKey, lens: currentStock.id, edge: edge, intensityPercent: 100)

    // Instant path: this lens was already developed for this photo — restore it
    // without re-running the whole pipeline.
    if let cached = PreviewCache.shared.render(forKey: cacheKey) {
      applyDeveloped(image: cached.image, decisions: cached.decisions, source: image)
      return
    }

    // Every render asks the Conductor: the photograph is read exactly once
    // and that one reading feeds the first develop, every lens switch, and
    // the full-res save. (Renders from one reading are byte-reproducible —
    // locked by ConductorTests — whereas separate subject passes are not
    // guaranteed bit-stable run to run.)
    let key = photoKey
    let stockID = currentStock.id
    ceremonySteps = ["Reading the light"]
    ceremonyActiveIndex = 0
    Task { @MainActor in
      do {
        let reading = try await Conductor.shared.reading(for: image, key: key)
        if matches == nil, key == photoKey {
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            matches = Conductor.rank(scene: reading.scene, faces: reading.subject.faces)
          }
        }
        // the read is done — its real steps show as completed, Developing runs
        if renderID == request {
          let narration = Conductor.narration(for: reading)
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            ceremonySteps = narration
            ceremonyActiveIndex = narration.count - 1
          }
        }
        let render = try await Task.detached(priority: .userInitiated) {
          try FilmEngine.shared.develop(
            image,
            with: recipe,
            maxPixelSize: CGFloat(edge),
            seed: seed,
            reading: reading
          )
        }.value
        guard renderID == request else { return }
        PreviewCache.shared.insert(
          CachedRender(image: render.image, decisions: render.decisions),
          forKey: cacheKey
        )
        Analytics.log(.developFinished(
          lookID: stockID,
          ms: Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
        ))
        applyDeveloped(image: render.image, decisions: render.decisions, source: image)
      } catch {
        guard renderID == request else { return }
        isDeveloping = false
        errorMessage = error.localizedDescription
      }
    }
  }

  /// Screenshot-harness only (CI ad captures): after the develop lands, hold
  /// the requested preview mode so the harness can photograph Original or
  /// Compare states without tap scripting. Never set in a real session.
  private var harnessPreviewMode: PreviewMode? {
    switch ProcessInfo.processInfo.environment["LENSMOOD_AD_MODE"] {
    case "original": return .original
    case "compare": return .compare
    default: return nil
    }
  }

  /// Commit a finished develop (from a fresh render or a cache hit) into editor
  /// state and the library. Runs on the main thread.
  private func applyDeveloped(image developed: UIImage, decisions newDecisions: [String], source: UIImage) {
    isDeveloping = false
    developedImage = developed
    decisions = newDecisions
    previewMode = harnessPreviewMode ?? .developed
    // the Library keeps a bounded copy of the original, built once per photo —
    // retaining 48 full-resolution sources was the session's dominant memory cost
    if librarySource == nil {
      librarySource = boundedLibraryCopy(of: source)
    }
    // replacing the session frame (lens switch) must not lose a favorite the
    // user set from the Library in the meantime
    let keptFavorite = sessionAssetID
      .flatMap { id in model.library.first(where: { $0.id == id })?.favorite } ?? false
    let asset = DevelopedAsset(
      image: developed,
      source: librarySource ?? source,
      stock: currentStock,
      decisions: newDecisions,
      favorite: keptFavorite
    )
    if let previous = sessionAssetID { model.remove(id: previous) }
    model.add(asset)
    sessionAssetID = asset.id
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  /// Cap the stored original's longest edge — detail-view quality at a
  /// fraction of the memory (full-res stays in `sourceImage` for export only).
  private func boundedLibraryCopy(of image: UIImage, maxEdge: CGFloat = 1600) -> UIImage {
    let largest = max(image.size.width * image.scale, image.size.height * image.scale)
    guard largest > maxEdge else { return image }
    let scale = maxEdge / largest
    let size = CGSize(
      width: (image.size.width * image.scale * scale).rounded(.down),
      height: (image.size.height * image.scale * scale).rounded(.down)
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }

  private func save() {
    guard let sourceImage else { return }
    isSaving = true
    let recipe = currentStock.recipe
    let seed = Double(currentStock.id.unicodeScalars.reduce(17) { ($0 * 31 + Int($1.value)) % 100_000 })
    let strength = intensity
    let key = photoKey
    let stockID = currentStock.id
    Task { @MainActor in
      do {
        // the save shares the develop's one reading — preview and export are
        // developed from the same read of the photograph
        let reading = try await Conductor.shared.reading(for: sourceImage, key: key)
        let fullResolution = try await Task.detached(priority: .userInitiated) { () -> UIImage in
          // Device-tier export cap (was a flat 4096): keeps peak memory under
          // jetsam on 2–3 GB devices while allowing full 4096 on roomier ones.
          let exportEdge = CGFloat(DeviceCapability.current.exportMaxEdge)
          let full = try FilmEngine.shared.develop(sourceImage, with: recipe, maxPixelSize: exportEdge, seed: seed, reading: reading).image
          return blended(developed: full, over: sourceImage, intensity: strength)
        }.value
        try await PhotoLibraryWriter.save(image: fullResolution)
        isSaving = false
        saveConfirmation = true
        Analytics.log(.photoSaved(lookID: stockID))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch is CancellationError {
        // a new photo replaced this one mid-save; not an error worth an alert
        isSaving = false
      } catch {
        isSaving = false
        errorMessage = error.localizedDescription
      }
    }
  }
}

/// Composite the developed frame over the original at `intensity`. Returns the
/// developed frame untouched at full strength (preserves the exact full develop,
/// so save/share at 100% and the parity path are byte-for-byte unchanged).
private func blended(developed: UIImage, over base: UIImage, intensity: CGFloat) -> UIImage {
  guard intensity < 0.999 else { return developed }
  let size = developed.size
  let format = UIGraphicsImageRendererFormat.default()
  format.scale = developed.scale
  format.opaque = true
  return UIGraphicsImageRenderer(size: size, format: format).image { _ in
    base.draw(in: CGRect(origin: .zero, size: size))
    developed.draw(in: CGRect(origin: .zero, size: size), blendMode: .normal, alpha: intensity)
  }
}

#Preview {
  NavigationStack {
    DevelopView(stock: Stock.all[0])
      .environmentObject(AppModel())
  }
}
