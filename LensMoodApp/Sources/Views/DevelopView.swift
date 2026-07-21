import PhotosUI
import SwiftUI
import UIKit

private enum PreviewMode: String, CaseIterable, Identifiable {
  case original = "Original"
  case developed = "Developed"
  case compare = "Compare"

  var id: String { rawValue }
}

/// The develop screen's one presentation seat. SwiftUI reliably honors a
/// single sheet per attachment point — share and the membership offer used to
/// sit as two `.sheet` modifiers on the same ScrollView chain, so they are
/// consolidated into one `sheet(item:)` that can never race.
private enum DevelopSheet: Identifiable {
  case share(UIImage)
  case paywall

  var id: String {
    switch self {
    case .share: return "share"
    case .paywall: return "paywall"
    }
  }
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
  /// monotonic save counter driving the SavedTick (see SavedTick.swift)
  @State private var saveTick = 0
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
  /// share (carrying its composited frame) or the membership offer — one
  /// presentation seat, so the two can never collide on this view
  @State private var activeSheet: DevelopSheet?
  /// the film-door gate state (see ExposureRoll.swift): observed so spend
  /// counters re-render the rail chips and door the moment film is spent
  @ObservedObject private var store = Store.shared
  /// exposures spent on THIS photograph this session: camera id → the Roll
  /// entry the spend created. A spent frame is the user's photograph — it is
  /// never session-replaced, and re-rendering the same camera never
  /// double-spends. Reset when a new photograph loads.
  @State private var sessionExposureAssets: [String: UUID] = [:]
  /// set between the spend and its develop landing, so applyDeveloped knows
  /// this render was bought with film and must land on the Roll (and so an
  /// abandoned or failed render can give the frame back)
  @State private var pendingExposureSpend: String?
  /// the id the film-bought frame will carry on the Roll — reserved at the
  /// spend so a crash-safe pending marker (ExposureLedger) can be matched
  /// against the delivered frame at launch and refunded only if it never landed
  @State private var pendingExposureAssetID: UUID?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ScrollView {
      ScrollViewReader { proxy in
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
          } else if let door = filmDoor {
            filmDoorPanel(door)
              .id("film-door")
            photoPicker(title: "New photograph")
          } else {
            actions
            if !decisions.isEmpty { decisionPanel }
          }

          characterCard

        }
        .padding(Theme.pagePadding)
        // clearance for the floating tab dock, like every other scrolling tab
        // (Home 36 / Tape 80): without it the last panel — the film door's
        // message on a locked camera — rests against the dock capsule
        .padding(.bottom, 36)
        // a door must be seen to be answered: it sits below the stage and
        // the rail, so when a locked camera halts the develop the gate would
        // otherwise wait below the fold (CI run 234 caught it cut off behind
        // the dock, its one action off-screen)
        .onChange(of: filmDoor) { door in
          guard door != nil else { return }
          withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            proxy.scrollTo("film-door", anchor: .bottom)
          }
        }
      }
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
        // the hero path already read this photograph for its ranking — adopt
        // that reading's key so the develop replays the identical read from
        // the Conductor cache (one-reading law: a second read is not
        // guaranteed bit-stable)
        if let key = model.pendingDevelopKey {
          photoKey = key
          model.pendingDevelopKey = nil
        }
        sourceImage = pending
        develop(pending)
      }
    }
    // No forget on disappear: a tab switch fires onDisappear while this
    // view's state (and its photo) live on, and dropping the reading would
    // force a fresh subject pass — splitting export from preview. The
    // Conductor's small LRU cap bounds memory instead; load() still forgets
    // the replaced photo's key explicitly.
    .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
      switch sheet {
      case .share(let image):
        ActivitySheet(items: [image])
      case .paywall:
        // the sheet gets navigation chrome so the offer names itself
        // ("LensMood Plus") and carries a visible Done — swipe-down alone
        // is not an affordance
        NavigationStack {
          PaywallView(context: paywallContext, showsDone: true)
        }
      }
    }
    .savedTick(trigger: saveTick)
    .alert("Could not develop this photograph", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      // a transient render failure left the source on the stage with every
      // develop affordance disabled — offer the retry directly
      if let sourceImage, !isDeveloping {
        Button("Try again") { develop(sourceImage) }
      }
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

  /// the caption's reason belongs to the LOADED camera, never a different
  /// one — the ranking's top reason must not caption a camera it isn't about
  private var railReason: String? {
    matches?.first(where: { $0.stockID == currentStock.id })?.reason
  }

  /// StyleRail — the horizontal camera switcher from the reference app:
  /// gradient swatch chips, ocean ring on the active camera. Selecting
  /// re-develops the loaded photograph in place. Once the Conductor has read
  /// the photograph, the rail reorders to the looks that will love it.
  private var styleRail: some View {
    VStack(alignment: .leading, spacing: 7) {
      if matches != nil {
        HStack(spacing: 8) {
          TechnicalLabel(text: "For this photo")
          if let reason = railReason {
            Text(reason)
              .font(.caption2.weight(.medium))   // 11pt at the default size
              .foregroundStyle(Theme.fog)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cameras reordered for this photo." + (railReason.map { " \($0)." } ?? ""))
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
      if item.id == currentStock.id {
        // re-tapping the active camera does nothing normally, but when a
        // develop failed (nothing on the stage) it becomes the retry
        guard developedImage == nil, !isDeveloping, let sourceImage else { return }
        develop(sourceImage)
        return
      }
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
            // the camera's frame counter — invisible while every gate is
            // open. A loaded locked camera wears its remaining exposures; a
            // spent one wears the lock. Fixed sizes on purpose: badge glyphs
            // pinned to the fixed 40pt swatch — scaling would swallow the
            // artwork.
            switch store.developAccess(for: item) {
            case .open:
              EmptyView()
            case .loaded(let remaining):
              Text("\(remaining)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4.5)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Theme.ink.opacity(0.72)))
                .offset(x: 4, y: 4)
            case .spent:
              Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(3)
                .background(Circle().fill(Theme.ink.opacity(0.72)))
                .offset(x: 4, y: 4)
            }
          }
        Text(item.name)
          .scaledFont(size: 10, weight: active ? .bold : .medium, relativeTo: .caption2)
          .foregroundStyle(active ? Theme.ink : Theme.fog)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .frame(width: 62)
    }
    .buttonStyle(.plain)
    .id(item.id)
    .accessibilityLabel(chipAccessibilityLabel(item))
    .accessibilityAddTraits(active ? .isSelected : [])
  }

  /// VoiceOver hears the film state the counter shows sighted users
  private func chipAccessibilityLabel(_ item: Stock) -> String {
    switch store.developAccess(for: item) {
    case .open:
      return "Develop with \(item.name)"
    case .loaded(let remaining):
      return "Develop with \(item.name), \(remaining) exposure\(remaining == 1 ? "" : "s") loaded"
    case .spent:
      return "\(item.name), out of film — in Plus"
    }
  }

  private var cameraIdentity: some View {
    VStack(alignment: .center, spacing: 5) {
      TechnicalLabel(text: currentStock.exif)
      Text(currentStock.tagline)
        .scaledFont(size: 23, weight: .heavy, relativeTo: .title2)
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
            .scaledFont(size: 13, weight: .semibold, relativeTo: .footnote)
            .foregroundStyle(Theme.accent)
          Text(def.emotionalTone)
            .font(.subheadline.weight(.bold))   // 15pt at the default size
            .foregroundStyle(Theme.ink)
        }
        Text(def.cameraInspiration)
          .font(.footnote.weight(.medium))   // 13pt at the default size
          .foregroundStyle(Theme.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
        Text(def.palette)
          .font(.caption)   // 12pt at the default size
          .foregroundStyle(Theme.fog)
          .fixedSize(horizontal: false, vertical: true)
        if !def.suitableSubjects.isEmpty {
          VStack(alignment: .leading, spacing: 3) {
            TechnicalLabel(text: "Best for")
            Text(def.suitableSubjects.joined(separator: "  ·  "))
              .font(.caption.weight(.medium))   // 12pt at the default size
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
            .scaledFont(size: 34, weight: .light, relativeTo: .largeTitle)
          Text("Load one photograph")
            .font(.body.weight(.semibold))   // 17pt at the default size
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
      .scaledFont(size: 9, weight: .semibold, design: .monospaced, relativeTo: .caption2)
      // one tight chrome strip over the stage: shrink, never wrap
      .lineLimit(1)
      .minimumScaleFactor(0.8)
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
            // wipe must show exactly what Save will produce.
            // The overlay is ALWAYS laid out at the full stage size and only
            // MASKED to the wipe width — a shrinking frame would make the
            // images re-fit to the narrower container, so the two halves
            // would render at different scales and nothing would line up
            // across the divider. Full-size layout + leading mask keeps both
            // layers in the identical fitted rect at any aspect ratio, any
            // scale, any divider position.
            ZStack {
              fittedImage(source)
              fittedImage(developed).opacity(Double(intensity))
            }
            .frame(width: size.width, height: size.height)
            .mask(alignment: .leading) {
              Rectangle().frame(width: size.width * compareFraction)
            }
            Rectangle()
              .fill(Theme.paper)
              .frame(width: 1)
              .offset(x: size.width * compareFraction)
            Circle()
              .fill(Theme.paper)
              .overlay(Circle().stroke(Theme.ink, lineWidth: 1))
              // fixed on purpose: the glyph inside the fixed 30pt drag handle
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
          .scaledFont(size: 12, weight: .semibold, design: .monospaced, relativeTo: .caption)
          .foregroundStyle(Theme.inkSoft)
      }
      // the readout row repeats what the slider speaks — combining the whole
      // control into one element muted the slider's adjustable gesture, so
      // the slider itself carries the name and stays adjustable
      .accessibilityHidden(true)
      Slider(value: $intensity, in: 0...1) { editing in
        if !editing { UISelectionFeedbackGenerator().selectionChanged() }
      }
      .tint(Theme.accent)
      .accessibilityLabel("Look strength")
      .onChange(of: intensity) { _ in
        // adjusting strength always reads against the developed view
        if previewMode != .developed { previewMode = .developed }
      }
    }
  }


  private var developingState: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(ceremonySteps.enumerated()), id: \.offset) { index, step in
        HStack(spacing: 10) {
          if index < ceremonyActiveIndex {
            Image(systemName: "checkmark")
              .scaledFont(size: 11, weight: .bold, relativeTo: .caption2)
              .foregroundStyle(Theme.accent)
              .frame(width: 16)
          } else {
            ProgressView()
              .tint(Theme.accent)
              .scaleEffect(0.75)
              .frame(width: 16)
          }
          Text(step)
            .scaledFont(size: 14, weight: index == ceremonyActiveIndex ? .semibold : .medium, relativeTo: .footnote)
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

  // MARK: The film door (see ExposureRoll.swift — the gate sits at the
  // develop, never at the keep: whatever renders on the stage is the user's)

  /// What stands between the loaded camera and this photograph. nil when the
  /// camera develops freely: open cameras always (everything, while
  /// Store.everythingFreeForNow), and a locked camera whose exposure was
  /// already spent on this photograph (its re-renders ride the same spend).
  private var filmDoor: ExposureRoll.Access? {
    guard sourceImage != nil else { return nil }
    guard sessionExposureAssets[currentStock.id] == nil else { return nil }
    let access = store.developAccess(for: currentStock)
    return access == .open ? nil : access
  }

  /// The locked camera's box-end tab: the honest count and one deliberate
  /// action. Loaded, developing costs a stated exposure the user keeps —
  /// never spent by a rail flick. Spent, the camera is simply out of film
  /// and the way forward is buying the camera.
  private func filmDoorPanel(_ door: ExposureRoll.Access) -> some View {
    InstrumentPanel {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          TechnicalLabel(text: door == .spent ? "Out of film" : "Loaded")
          Spacer()
          Text(counterReadout(door))
            .scaledFont(size: 11, weight: .bold, design: .monospaced, relativeTo: .caption2)
            .tracking(0.8)
            .foregroundStyle(door == .spent ? Theme.fog : Theme.accent)
        }
        Text(doorMessage(door))
          .scaledFont(size: 14, relativeTo: .footnote)
          .foregroundStyle(Theme.inkSoft)
          .fixedSize(horizontal: false, vertical: true)
        if case .loaded = door {
          Button("Develop — spends one exposure") { spendAndDevelop() }
            .buttonStyle(InstrumentButtonStyle(kind: .primary))
        } else {
          Button("See LensMood Plus") { activeSheet = .paywall }
            .buttonStyle(InstrumentButtonStyle(kind: .secondary))
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(currentStock.name). \(doorMessage(door))")
  }

  private func counterReadout(_ door: ExposureRoll.Access) -> String {
    switch door {
    case .open: return ""
    case .loaded(let remaining): return "\(remaining) OF \(ExposureRoll.loadedExposures) EXP"
    case .spent: return "0 OF \(ExposureRoll.loadedExposures) EXP"
    }
  }

  private func doorMessage(_ door: ExposureRoll.Access) -> String {
    switch door {
    case .open:
      return ""
    case .loaded:
      return "\(ExposureRoll.loadedExposures) exposures loaded. Developing spends one — the frame is yours, full resolution, on your Roll."
    case .spent:
      return "All \(ExposureRoll.loadedExposures) exposures spent. What you developed is yours."
    }
  }

  /// the deliberate spend: film advances, the develop runs, the photograph
  /// lands on the Roll as the user's own (applyDeveloped)
  private func spendAndDevelop() {
    guard let sourceImage else { return }
    // a double-fired tap must not spend two frames for one develop (the
    // door leaves the tree on the next render pass, not on the first tap)
    guard !isDeveloping else { return }
    guard store.spendExposure(on: currentStock) else { return }
    let assetID = UUID()
    pendingExposureSpend = currentStock.id
    pendingExposureAssetID = assetID
    // park a crash-safe marker: if the process dies before this develop lands,
    // launch reconciliation gives the exposure back (the frame never reached
    // the Roll under this id)
    ExposureLedger.shared.recordPendingSpend(assetID: assetID, on: currentStock.id)
    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    develop(sourceImage, spendingExposure: true)
  }

  /// the offer's context: a locked camera's door leads with the frames the
  /// user already kept on it — their own photographs, never stock art
  private var paywallContext: PaywallContext {
    guard store.developAccess(for: currentStock) != .open else { return .browse }
    let kept = model.library
      .filter { $0.stock.id == currentStock.id }
      .prefix(3)
      .map(\.thumbnail)
    return .reload(stock: currentStock, kept: Array(kept))
  }

  /// the counter line under a film-bought develop — a fact, not a nudge
  private var spentExposureLine: String? {
    guard sessionExposureAssets[currentStock.id] != nil else { return nil }
    switch store.developAccess(for: currentStock) {
    case .open:
      return nil   // Plus arrived mid-session — the counter retires
    case .loaded(let remaining):
      return remaining == 1
        ? "1 exposure left."
        : "\(remaining) exposures left."
    case .spent:
      return "Last exposure spent."
    }
  }

  private var saveButtonTitle: String {
    isSaving ? "Preparing full resolution" : "Save"
  }

  private var actions: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        photoPicker(title: "New photograph")
        Button(saveButtonTitle) { save() }
          .buttonStyle(InstrumentButtonStyle(kind: .primary))
          .disabled(developedImage == nil || isSaving)
      }
      Button("Share developed photograph") {
        presentShareSheet()
      }
      .buttonStyle(InstrumentButtonStyle(kind: .secondary))
      .disabled(developedImage == nil)
      Button("Share as camera card") {
        // the card is a format the user chooses — the bare share above stays
        // unmarked
        presentCardShareSheet()
      }
      .buttonStyle(InstrumentButtonStyle(kind: .secondary))
      .disabled(developedImage == nil)
      if let spentExposureLine {
        Text(spentExposureLine)
          .font(.footnote)   // 13pt at the default size
          .foregroundStyle(Theme.inkSoft)
          .frame(maxWidth: .infinity, alignment: .center)
          .multilineTextAlignment(.center)
      }
    }
  }

  /// the camera-card share path — the same composite as the bare share,
  /// framed by LightTestCard
  private func presentCardShareSheet() {
    guard let developedImage, let sourceImage else { return }
    let stock = currentStock
    let decision = decisions.first
    let strength = intensity
    Task.detached(priority: .userInitiated) {
      let composed = blended(developed: developedImage, over: sourceImage, intensity: strength)
      let card = LightTestCard.single(photo: composed, stock: stock, decision: decision)
      await MainActor.run {
        Analytics.log(.photoShared)
        activeSheet = .share(card)
      }
    }
  }

  /// the Share sheet's composite-and-present path
  private func presentShareSheet() {
    // composite off-main; presenting inside the sheet's body re-ran the
    // full-frame blend on every view evaluation
    guard let developedImage, let sourceImage else { return }
    let strength = intensity
    Task.detached(priority: .userInitiated) {
      let composed = blended(developed: developedImage, over: sourceImage, intensity: strength)
      await MainActor.run {
        Analytics.log(.photoShared)
        activeSheet = .share(composed)
      }
    }
  }

  /// after the offer closes: if Plus now covers the camera, the develop the
  /// user was standing in front of simply happens — full ceremony, straight
  /// onto the Roll, like any owned camera
  private func handleSheetDismiss() {
    guard let sourceImage, developedImage == nil, !isDeveloping,
      store.developAccess(for: currentStock) == .open else { return }
    develop(sourceImage)
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
              .scaledFont(size: 10, design: .monospaced, relativeTo: .caption2)
              .foregroundStyle(Theme.accent)
            Text(decision)
              .scaledFont(size: 14, relativeTo: .footnote)
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
        sessionExposureAssets = [:]   // spends belong to the photograph they developed
        develop(image)
      } catch {
        isDeveloping = false
        errorMessage = error.localizedDescription
      }
    }
  }

  private func develop(_ image: UIImage, spendingExposure: Bool = false) {
    // An in-flight film-bought develop that never landed gives its frame
    // back before anything else starts (render failures refund in the catch;
    // this covers abandonment — a camera switch or a new photograph).
    if !spendingExposure, let abandoned = pendingExposureSpend {
      pendingExposureSpend = nil
      if let id = pendingExposureAssetID {
        ExposureLedger.shared.clearPendingSpend(assetID: id)
        pendingExposureAssetID = nil
      }
      store.refundExposure(on: Stock.find(abandoned))
    }
    // THE gate: a locked camera only fires on a spent exposure. The film
    // door (body) offers the spend while film remains; a spent roll renders
    // nothing at all. Every camera is .open while
    // Store.everythingFreeForNow — this path never runs.
    if !spendingExposure, sessionExposureAssets[currentStock.id] == nil,
      store.developAccess(for: currentStock) != .open {
      // orphan any in-flight render before standing at the door: this path
      // returns without minting a new renderID, so a develop started on the
      // previous camera (or the previous photograph) would otherwise still
      // pass the renderID guard and land its frame under this door — a
      // stale render the spent roll promised never to show
      renderID = UUID()
      isDeveloping = false
      developedImage = nil
      decisions = []
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
    // without re-running the whole pipeline. The reading is still the
    // Conductor's one read for this photo (kept for the view's lifetime), so a
    // cache-hit landing persists the same reading a fresh render would.
    if let cached = PreviewCache.shared.render(forKey: cacheKey) {
      applyDeveloped(
        image: cached.image, decisions: cached.decisions, source: image,
        reading: Conductor.shared.cachedReading(for: photoKey)
      )
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
        applyDeveloped(image: render.image, decisions: render.decisions, source: image, reading: reading)
      } catch {
        guard renderID == request else { return }
        // a film-bought render that failed gives its frame back — the
        // camera never eats an exposure it didn't deliver
        if pendingExposureSpend == currentStock.id {
          pendingExposureSpend = nil
          if let id = pendingExposureAssetID {
            ExposureLedger.shared.clearPendingSpend(assetID: id)
            pendingExposureAssetID = nil
          }
          store.refundExposure(on: currentStock)
        }
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
  /// state — and into the library only when the camera is the user's to keep.
  /// Runs on the main thread.
  private func applyDeveloped(
    image developed: UIImage, decisions newDecisions: [String], source: UIImage,
    reading: SceneReading? = nil
  ) {
    isDeveloping = false
    developedImage = developed
    decisions = newDecisions
    previewMode = harnessPreviewMode ?? .developed
    // Every develop that renders is kept — an open camera's lands with the
    // session-replace behavior, a film-bought one lands permanently. (While
    // Store.everythingFreeForNow every camera is open: unchanged behavior.)
    if store.isUnlocked(currentStock) {
      storeInLibrary(developed: developed, decisions: newDecisions, source: source, reading: reading)
    } else if pendingExposureSpend == currentStock.id {
      pendingExposureSpend = nil
      storeSpentExposureInLibrary(developed: developed, decisions: newDecisions, source: source, reading: reading)
    }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  /// land a film-bought develop on the Roll for good: a spent exposure is
  /// the user's photograph — it is never session-replaced by a later camera
  /// switch, and its id remembers the spend so this photograph re-develops
  /// on this camera without spending again
  private func storeSpentExposureInLibrary(
    developed: UIImage, decisions newDecisions: [String], source: UIImage,
    reading: SceneReading? = nil
  ) {
    if librarySource == nil {
      librarySource = boundedLibraryCopy(of: source)
    }
    // the frame lands under the id reserved at the spend, so launch
    // reconciliation recognizes this exposure as delivered and never refunds
    // it. The pending marker is retired at that launch check, not here — a
    // crash between the disk write and a here-and-now clear would otherwise
    // strand it; the delivered-id cross-check handles both orderings.
    let asset = DevelopedAsset(
      id: pendingExposureAssetID ?? UUID(),
      image: developed,
      source: librarySource ?? source,
      stock: currentStock,
      decisions: newDecisions
    )
    model.add(asset)
    // freeze the reading beside the kept frame so a later re-develop replays
    // this exact read instead of a drifted one (the one-reading law across time)
    if let reading { LibraryStore.persistReading(reading, for: asset.id) }
    sessionExposureAssets[currentStock.id] = asset.id
    pendingExposureAssetID = nil
  }

  /// the one Library landing (shared by applyDeveloped and
  /// the open-camera landing (session-scoped): bounded original copy, favorite-preserving
  /// session replace, model.add
  private func storeInLibrary(
    developed: UIImage, decisions newDecisions: [String], source: UIImage,
    reading: SceneReading? = nil
  ) {
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
    // freeze the reading beside the kept frame so a later re-develop replays
    // this exact read instead of a drifted one (the one-reading law across time)
    if let reading { LibraryStore.persistReading(reading, for: asset.id) }
    sessionAssetID = asset.id
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
    // No gate here by design: whatever rendered on the stage is the user's —
    // an open camera's develop freely, a locked camera's because a loaded
    // exposure was spent to make it. The film door gates the develop itself.
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
        saveTick += 1
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
