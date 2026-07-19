import SwiftUI
import UIKit

/// The LensMood camera — a warm-gold pro instrument. Full-screen viewfinder with
/// a top-plate readout, aperture/shutter/ISO/EV dials, zoom + AF/MF, a film-canister
/// stock selector, Photo/Video/Portrait/Night modes, and a mechanical shutter. On
/// capture the scene is auto-relit and developed through the loaded camera.
struct CaptureView: View {
  @EnvironmentObject private var model: AppModel
  @StateObject private var camera = CameraController()
  /// film-door state (see ExposureRoll.swift): observed so the mount
  /// picker's counters and the film bar follow spends live. Inert while
  /// Store.everythingFreeForNow — every camera is .open.
  @ObservedObject private var store = Store.shared

  @State private var loadedStock = Stock.all[0]
  /// the camera id whose exposure the in-flight shot spent, so a failed
  /// develop can give the frame back
  @State private var pendingShotSpend: String?
  /// the id the shot's frame will carry on the Roll — reserved at the spend so
  /// a crash-safe pending marker (ExposureLedger) refunds the exposure at
  /// launch only if the frame never landed
  @State private var pendingShotAssetID: UUID?
  @State private var activeDial: ActiveDial = .aperture
  @State private var showGrid = true
  @State private var mountPickerShown = false
  @State private var libraryShown = false

  @State private var isDeveloping = false
  @State private var review: DevelopedAsset?
  /// confirm before an archived Roll frame opened for review is destroyed —
  /// "Retake" only makes sense for the just-taken shot
  @State private var reviewDeleteRequested = false
  /// full frame for a Roll pick under review, keyed by asset id so a stale
  /// decode can never show under a different frame (two-tier: persisted
  /// assets only carry a thumbnail in memory; fresh shots hold their frame)
  @State private var reviewFullImage: (id: UUID, image: UIImage)?
  @State private var shutterFlash = false
  @State private var errorMessage: String?
  /// monotonic save counter driving the SavedTick (see SavedTick.swift)
  @State private var saveTick = 0
  @State private var isSavingShot = false
  @State private var renderToken = UUID()
  @State private var cameraSeeded = false

  // legibility helpers: tap-to-focus confirmation, a mode explainer, and a
  // one-time guide so a first-time user knows what every control does
  @State private var focusPulse: FocusPulse?
  /// converts tap points into the device's point-of-interest space (the
  /// preview layer registers itself; see CaptureDevicePointConverter)
  @State private var focusConverter = CaptureDevicePointConverter()
  @State private var modeHint: String?
  @State private var modeHintToken = UUID()
  @State private var guideShown = false
  @AppStorage("cameraGuideSeen") private var guideSeen = false
  @Environment(\.dynamicTypeSize) private var typeSize

  struct FocusPulse: Equatable { let id = UUID(); let point: CGPoint }

  enum ActiveDial: CaseIterable { case aperture, shutter, iso, ev }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        CameraTheme.bg.ignoresSafeArea()
        // accessibility sizes: the grown readouts, film bar, and mode labels
        // no longer fit the fixed instrument column beside the 62% viewfinder
        // — the column scrolls so the shutter and modes stay reachable.
        // Identical below accessibility sizes.
        if typeSize.isAccessibilitySize {
          ScrollView(showsIndicators: false) {
            instrumentColumn(size: geo.size)
          }
        } else {
          instrumentColumn(size: geo.size)
        }

        closeButton
        if shutterFlash { Color.white.ignoresSafeArea().transition(.opacity) }
      }
      // pin to the screen box so an intrinsically-wide child (the dial) can
      // never push the centered viewfinder off to one side
      .frame(width: geo.size.width, height: geo.size.height)
      .ignoresSafeArea(edges: .bottom)
    }
    .overlay { if isDeveloping { developingOverlay } }
    .overlay { if let review { reviewCard(review) } }
    .overlay { if guideShown { guideOverlay } }
    .sheet(isPresented: $mountPickerShown) { mountPicker }
    .sheet(isPresented: $libraryShown) { librarySheet }
    .savedTick(trigger: saveTick)
    .alert("Could not complete that", isPresented: Binding(
      get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
    )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Try again.") }
    .onAppear {
      // seed once — returning to the tab must not wipe the photographer's dials
      if !cameraSeeded {
        cameraSeeded = true
        camera.settings.autoRelight = true
        camera.load(stock: loadedStock)
      }
      camera.configure()
      // first-run guide — but never over a CI/screenshot launch (LENSMOOD_TAB set)
      let scripted = ProcessInfo.processInfo.environment["LENSMOOD_TAB"] != nil
      if !guideSeen && !scripted { guideShown = true }
    }
    .onDisappear { camera.stop() }
    .statusBarHidden(true)
    // the camera is a dark instrument, so frosted materials render as the iOS
    // camera's translucent charcoal glass rather than white
    .environment(\.colorScheme, .dark)
  }

  // MARK: top readout

  private func instrumentColumn(size: CGSize) -> some View {
    VStack(spacing: 0) {
      topBar
      viewfinder(size: size)
      modeHintBar
      filmBar
      modesRow
      captureRow
    }
  }

  @ViewBuilder
  private var topBar: some View {
    // accessibility sizes: five grown readouts cannot share one screen width
    // — the row keeps full-size values and pans sideways instead of
    // shrinking exposure numbers into unreadable truncation
    if typeSize.isAccessibilitySize {
      ScrollView(.horizontal, showsIndicators: false) { topBarRow }
        .background(.ultraThinMaterial)
    } else {
      topBarRow.background(.ultraThinMaterial)
    }
  }

  private var topBarRow: some View {
    HStack(alignment: .bottom, spacing: 4) {
      flashReadout
      readout("ISO", "\(Int(camera.settings.iso))", .iso)
      readout("SHUTTER", fmtShutter(camera.settings.shutter), .shutter)
      readout("APERTURE", "ƒ/\(fmtF(camera.settings.aperture))", .aperture)
      readout("EV", fmtEV(camera.settings.exposureBiasEV), .ev)
      Spacer(minLength: 0)
      autoLightToggle
    }
    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 12)
  }

  /// the scene-relight switch — tapping it turns the Vision + Core Image
  /// lighting model on/off for the next shot, and says so
  private var autoLightToggle: some View {
    let on = camera.settings.autoRelight
    return Button {
      camera.settings.autoRelight.toggle()
      showModeHint(camera.settings.autoRelight
        ? "Auto light on — the next shot is scene-relit"
        : "Auto light off — the film develops the frame as metered")
      tick()
    } label: {
      HStack(spacing: 5) {
        Image(systemName: on ? "wand.and.stars" : "wand.and.stars.inverse").scaledFont(size: 10, relativeTo: .caption2)
        Text("AUTO LIGHT").font(.spaceMono(9, bold: true)).tracking(0.5)
      }
      .foregroundStyle(on ? CameraTheme.gold : CameraTheme.dim)
      .padding(.horizontal, 8).padding(.vertical, 5)
      .background(on ? CameraTheme.gold.opacity(0.14) : .clear)
      .clipShape(Capsule())
      .overlay(Capsule().stroke(on ? CameraTheme.gold.opacity(0.5) : CameraTheme.line, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Auto light")
    .accessibilityAddTraits(on ? .isSelected : [])
  }

  private func readout(_ label: String, _ value: String, _ dial: ActiveDial) -> some View {
    let on = activeDial == dial
    return Button { activeDial = dial; tick() } label: {
      VStack(spacing: 3) {
        Text(label).scaledFont(size: 9, weight: .semibold, relativeTo: .caption2)
          .lineLimit(1).minimumScaleFactor(0.8).tracking(0.12 * 9).foregroundStyle(CameraTheme.faint)
        Text(value).scaledFont(size: 16, weight: .semibold, design: .monospaced, relativeTo: .callout)
          .lineLimit(1).minimumScaleFactor(0.8)
          .foregroundStyle(on ? CameraTheme.gold : CameraTheme.dim)
      }
      .frame(minWidth: 46)
    }.buttonStyle(.plain)
    // VoiceOver hears which readout the wheel is currently driving
    .accessibilityAddTraits(on ? .isSelected : [])
  }

  private var flashReadout: some View {
    Button {
      camera.settings.flashMode = camera.settings.flashMode == .off ? .auto
        : (camera.settings.flashMode == .auto ? .on : .off)
      tick()
    } label: {
      VStack(spacing: 3) {
        Image(systemName: camera.settings.flashMode == .off ? "bolt.slash.fill" : "bolt.fill")
          .scaledFont(size: 15, relativeTo: .subheadline)
          .foregroundStyle(camera.settings.flashMode == .off ? CameraTheme.text : CameraTheme.gold)
        Text(flashLabel).scaledFont(size: 9, weight: .semibold, relativeTo: .caption2)
          .lineLimit(1).minimumScaleFactor(0.8).tracking(1).foregroundStyle(CameraTheme.faint)
      }.frame(minWidth: 44)
    }.buttonStyle(.plain)
    // the glyph alone reads as "bolt" — name the control and its state
    .accessibilityLabel("Flash \(flashLabel.capitalized)")
  }

  // MARK: viewfinder

  private func viewfinder(size: CGSize) -> some View {
    ZStack {
      CameraPreviewView(
        session: camera.session,
        isAvailable: camera.isAvailable,
        placeholder: BundleMedia.image("style-\(loadedStock.id)"),
        converter: focusConverter
      )
      // no hardware (Simulator): the plate itself answers the zoom and flip
      // controls, so every button still visibly changes the frame
      .scaleEffect(
        x: plateZoom * (plateMirrored ? -1 : 1),
        y: plateZoom
      )
      .animation(.easeOut(duration: 0.22), value: camera.settings.zoom)
      .animation(.easeOut(duration: 0.22), value: camera.position)
      .contentShape(Rectangle())
      .onTapGesture { location in focusHere(location, in: size) }

      if showGrid {
        GridOverlay().stroke(Color.white.opacity(0.28), lineWidth: 0.5).allowsHitTesting(false)
      }
      reticle.allowsHitTesting(false)

      // tap-to-focus confirmation: a gold box snaps onto the point you touched
      if let pulse = focusPulse {
        FocusReticle().position(pulse.point).id(pulse.id).allowsHitTesting(false)
      }

      // right control stack
      VStack(spacing: 12) {
        zoomPill
        afmfPill
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
      .padding(.trailing, 14)

      // hardware present but access declined: never let the shutter develop
      // the bundled plate as if it were the user's photograph — explain and
      // point at Settings instead
      if cameraAccessDenied { permissionOverlay }

      // command wheel — bottom-aligned; empty area above stays tappable (focus)
      VStack(spacing: 4) {
        Text(activeDialLabel)
          .scaledFont(size: 22, weight: .bold, design: .monospaced, relativeTo: .title2)
          .foregroundStyle(.white).shadow(color: .black.opacity(0.55), radius: 5)
        HStack(spacing: 8) {
          Image(systemName: "chevron.compact.left").foregroundStyle(.white.opacity(0.4))
          CommandWheel(steps: activeStepCount, index: activeIndex) { setActiveDial(to: $0) }
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
            .clipped()
          Image(systemName: "chevron.compact.right").foregroundStyle(.white.opacity(0.4))
        }
        .scaledFont(size: 15, weight: .semibold, relativeTo: .subheadline)
        .padding(.horizontal, 30)
        Text("DRAG TO \(activeDialName)")
          .scaledFont(size: 8, weight: .semibold, design: .monospaced, relativeTo: .caption2)
          .lineLimit(1).tracking(1.5)
          .foregroundStyle(.white.opacity(0.45))
      }
      // the wheel is a drag-only instrument — expose it to VoiceOver as one
      // adjustable element (swipe up/down steps the active parameter). Scoped
      // before the expanding frame so the element is the wheel itself, not a
      // viewfinder-sized plate over the zoom and focus pills.
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(spokenDialName) dial")
      .accessibilityValue(activeDialLabel)
      .accessibilityAdjustableAction { direction in
        switch direction {
        case .increment: setActiveDial(to: activeIndex + 1)
        case .decrement: setActiveDial(to: activeIndex - 1)
        @unknown default: break
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      .padding(.bottom, 16)
    }
    .frame(width: size.width, height: size.height * 0.62)
    .clipped()
  }

  private var reticle: some View {
    ZStack {
      CornerTicks().stroke(.white, lineWidth: 2).frame(width: 108, height: 108)
      // fixed on purpose: the crosshair glyph centered in the fixed 108pt reticle
      Image(systemName: "plus").font(.system(size: 16, weight: .regular)).foregroundStyle(.white)
    }
  }

  private var zoomPill: some View {
    VStack(spacing: 2) {
      ForEach([1.0, 2.0, 5.0], id: \.self) { z in
        let on = abs(camera.settings.zoom - z) < 0.01
        Button { camera.applyZoom(z); tick() } label: {
          Text(z == 1 ? "1×" : "\(Int(z))")
            .scaledFont(size: 13, weight: .semibold, design: .monospaced, relativeTo: .footnote)
            // the pill button stays 44pt wide: grown numerals shrink to fit
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(on ? CameraTheme.gold : CameraTheme.dim)
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityLabel(z == 1 ? "1× zoom" : "\(Int(z))× zoom")
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.45), lineWidth: 1))
  }

  private var afmfPill: some View {
    VStack(spacing: 2) {
      ForEach([false, true], id: \.self) { manual in
        let on = camera.settings.manualFocus == manual
        Button { camera.settings.manualFocus = manual; tick() } label: {
          Text(manual ? "MF" : "AF")
            .scaledFont(size: 13, weight: .semibold, design: .monospaced, relativeTo: .footnote)
            // the pill button stays 44pt wide: grown letters shrink to fit
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(on ? CameraTheme.gold : CameraTheme.dim)
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityLabel(manual ? "Manual focus" : "Autofocus")
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.45), lineWidth: 1))
  }

  // MARK: film canister selector

  private var filmBar: some View {
    Button { mountPickerShown = true } label: {
      HStack(spacing: 10) {
        canisterIcon
        Text(loadedStock.name).font(.spaceMono(15, bold: true)).foregroundStyle(CameraTheme.text)
          // one film bar row: a grown name shrinks a touch, never wraps mid-word
          .lineLimit(1).minimumScaleFactor(0.7)
        filmCounter
        Image(systemName: "chevron.down").scaledFont(size: 11, weight: .semibold, relativeTo: .caption2).foregroundStyle(CameraTheme.dim)
        Spacer()
        Button { showGrid.toggle(); tick() } label: {
          // glyph fixed on purpose: it sits inside the fixed 40pt bordered control
          Image(systemName: "grid")
            .font(.system(size: 15))
            .foregroundStyle(showGrid ? CameraTheme.gold : CameraTheme.dim)
            .frame(width: 40, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(showGrid ? CameraTheme.gold : CameraTheme.line, lineWidth: 1))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityLabel("Composition grid")
        .accessibilityAddTraits(showGrid ? .isSelected : [])
      }
      .padding(.horizontal, 12).padding(.vertical, 10)
      .background(CameraTheme.panel)
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(CameraTheme.line, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 14).padding(.top, 12)
  }

  /// the loaded camera's frame counter in the film bar — an engraved fact,
  /// present only when film is metered at all (never while gates are open)
  @ViewBuilder
  private var filmCounter: some View {
    switch store.developAccess(for: loadedStock) {
    case .open:
      EmptyView()
    case .loaded(let remaining):
      Text("·\(remaining) EXP")
        .font(.spaceMono(11, bold: true))
        .foregroundStyle(CameraTheme.gold)
        .accessibilityLabel("\(remaining) exposure\(remaining == 1 ? "" : "s") left")
    case .spent:
      Text("EMPTY")
        .font(.spaceMono(11, bold: true)).tracking(1)
        .foregroundStyle(CameraTheme.dim)
        .accessibilityLabel("Out of film")
    }
  }

  @ViewBuilder
  private var canisterIcon: some View {
    if let img = BundleMedia.image("film-canister") {
      Image(uiImage: img).resizable().scaledToFit().frame(width: 30, height: 38)
    } else {
      // fixed on purpose: a stand-in for the 30×38 canister artwork
      Image(systemName: "film").font(.system(size: 20)).foregroundStyle(CameraTheme.gold).frame(width: 30, height: 38)
    }
  }

  // MARK: modes

  private var modesRow: some View {
    HStack(spacing: 0) {
      ForEach(CaptureMode.allCases, id: \.self) { mode in
        let on = camera.settings.captureMode == mode
        Button { selectMode(mode) } label: {
          VStack(spacing: 5) {
            Image(systemName: mode.systemImage).scaledFont(size: 20, relativeTo: .title3)
            Text(mode.rawValue.uppercased()).font(.spaceMono(11, bold: on)).tracking(0.5)
              // four fixed slots: a grown mode name shrinks, never wraps mid-word
              .lineLimit(1).minimumScaleFactor(0.6)
            Rectangle().fill(on ? CameraTheme.gold : .clear).frame(width: 18, height: 2).clipShape(Capsule())
          }
          .foregroundStyle(on ? CameraTheme.gold : CameraTheme.dim)
          .frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
        // spell the mode name (the all-caps label may read letter-by-letter)
        // and let VoiceOver hear which mode the camera is in
        .accessibilityLabel(mode.rawValue)
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
    .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 4)
  }

  private func selectMode(_ mode: CaptureMode) {
    if mode == .video { model.selectedTab = .tape; return }   // the camcorder owns video
    camera.settings.captureMode = mode
    showModeHint(mode.blurb)
    tick()
  }

  /// a mode explainer that fades in under the viewfinder, then clears itself
  private var modeHintBar: some View {
    Text(modeHint ?? " ")
      .font(.spaceMono(10))
      .foregroundStyle(CameraTheme.gold)
      .frame(maxWidth: .infinity)
      .frame(height: 16)
      .opacity(modeHint == nil ? 0 : 1)
      .padding(.top, 6)
  }

  private func showModeHint(_ text: String) {
    let token = UUID(); modeHintToken = token
    withAnimation(.easeOut(duration: 0.2)) { modeHint = text }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
      if modeHintToken == token { withAnimation(.easeIn(duration: 0.3)) { modeHint = nil } }
    }
  }

  // MARK: capture row

  private var captureRow: some View {
    HStack {
      Button { libraryShown = true } label: {
        Group {
          if let last = model.library.first {
            // 56 pt chip — the grid-tier thumbnail is the right size here
            Image(uiImage: last.thumbnail).resizable().scaledToFill()
          } else {
            ZStack {
              CameraTheme.panel
              // fixed on purpose: a stand-in inside the fixed 56pt thumbnail
              Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(CameraTheme.dim)
            }
          }
        }
        .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CameraTheme.line, lineWidth: 1.5))
      }
      .buttonStyle(.plain).accessibilityLabel("Library")

      Spacer()
      shutterButton
      Spacer()

      Button { camera.flip() } label: {
        // glyph fixed on purpose: it sits inside the fixed 52pt ring control
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.system(size: 20)).foregroundStyle(CameraTheme.dim)
          .frame(width: 52, height: 52).overlay(Circle().stroke(CameraTheme.line, lineWidth: 1))
      }.buttonStyle(.plain).accessibilityLabel("Flip camera")
    }
    .padding(.horizontal, 30).padding(.top, 6).padding(.bottom, 22)
  }

  private var shutterButton: some View {
    Button { shoot() } label: {
      ZStack {
        // glassy outer rim (frosted, like the iOS default camera)
        Circle().stroke(.ultraThinMaterial, lineWidth: 6).frame(width: 84, height: 84)
        Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5).frame(width: 84, height: 84)
        // solid white shutter button with a soft edge
        Circle().fill(.white).frame(width: 66, height: 66)
          .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
          .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
      }
      .scaleEffect(camera.isCapturing ? 0.92 : 1)
    }
    .buttonStyle(.plain).disabled(camera.isCapturing || isDeveloping)
    .accessibilityLabel("Shutter")
  }

  private var closeButton: some View {
    VStack {
      HStack {
        Button { model.selectedTab = .cameras } label: {
          HStack(spacing: 6) {
            Image(systemName: "chevron.left").scaledFont(size: 13, weight: .bold, relativeTo: .footnote)
            Text("LensMood").font(.spaceMono(13, bold: true))
          }
          .foregroundStyle(CameraTheme.text)
          .padding(.horizontal, 14).frame(height: 44)
          .background(.regularMaterial, in: Capsule())
          .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
          .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to LensMood")
        Spacer()
      }
      .padding(.leading, 14).padding(.top, 72)
      Spacer()
    }
  }

  // MARK: pickers + review

  private var mountPicker: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
          ForEach(Stock.all) { stock in
            mountCell(stock)
          }
        }.padding(16)
      }
      .background(CameraTheme.bg)
      .navigationTitle("Load a film").navigationBarTitleDisplayMode(.inline)
      .toolbarColorScheme(.dark, for: .navigationBar)
    }
    .presentationDetents([.medium, .large])
  }

  /// One camera on the mount shelf. Open and loaded cameras mount as ever —
  /// loading is free, the SHUTTER spends film (shoot()). A spent camera
  /// can't be mounted: its cell opens the offer instead, in-fiction
  /// acquisition, not a dead end. All cameras mount freely while
  /// Store.everythingFreeForNow.
  @ViewBuilder
  private func mountCell(_ stock: Stock) -> some View {
    let access = store.developAccess(for: stock)
    if case .spent = access {
      NavigationLink {
        PaywallView(context: .reload(
          stock: stock,
          kept: Array(model.library.filter { $0.stock.id == stock.id }.prefix(3).map(\.thumbnail))
        ))
        // the offer is a paper-light surface: lift the camera instrument's
        // forced dark scheme, which the mount sheet inherits — otherwise
        // this pushed screen's system pieces (bar title, back chevron,
        // Divider) render dark-scheme over Theme.paper. The bar gets the
        // explicit per-screen scheme, the counterpart of the mount grid's
        // own .toolbarColorScheme(.dark).
        .environment(\.colorScheme, .light)
        .toolbarColorScheme(.light, for: .navigationBar)
      } label: {
        mountCellLabel(stock, access: access)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(stock.name), out of film — see LensMood Plus")
    } else {
      Button {
        loadedStock = stock; camera.load(stock: stock); mountPickerShown = false
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
      } label: {
        mountCellLabel(stock, access: access)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(mountAccessibilityLabel(stock, access: access))
    }
  }

  private func mountAccessibilityLabel(_ stock: Stock, access: ExposureRoll.Access) -> String {
    if case .loaded(let remaining) = access {
      return "Load \(stock.name), \(remaining) exposure\(remaining == 1 ? "" : "s") in it"
    }
    return "Load \(stock.name)"
  }

  private func mountCellLabel(_ stock: Stock, access: ExposureRoll.Access) -> some View {
    VStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 12)
        .fill(LinearGradient(colors: [Color(hex: stock.g0), Color(hex: stock.g1)],
                             startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(height: 66)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(stock.id == loadedStock.id ? CameraTheme.gold : .clear, lineWidth: 2.5))
        .overlay(alignment: .bottomTrailing) {
          // frame counter / lock — the rail-chip idiom, invisible while
          // every gate is open. Fixed sizes: badges pinned to the swatch.
          switch access {
          case .open:
            EmptyView()
          case .loaded(let remaining):
            Text("\(remaining)")
              .font(.system(size: 10, weight: .bold, design: .monospaced))
              .foregroundStyle(.white)
              .padding(.horizontal, 5).padding(.vertical, 3)
              .background(Capsule().fill(Color.black.opacity(0.55)))
              .padding(5)
          case .spent:
            Image(systemName: "lock.fill")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(.white)
              .padding(4)
              .background(Circle().fill(Color.black.opacity(0.55)))
              .padding(5)
          }
        }
      Text(stock.name).scaledFont(size: 12, weight: .semibold, relativeTo: .caption)
        .foregroundStyle(CameraTheme.text).lineLimit(1).minimumScaleFactor(0.8)
      Text(stock.exif).scaledFont(size: 8, weight: .medium, design: .monospaced, relativeTo: .caption2)
        .foregroundStyle(CameraTheme.dim).lineLimit(1).minimumScaleFactor(0.7)
    }
  }

  private var librarySheet: some View {
    NavigationStack {
      ScrollView {
        if model.library.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle")
              .scaledFont(size: 30, weight: .light, relativeTo: .largeTitle).foregroundStyle(CameraTheme.dim)
            Text("Nothing on your Roll yet")
              .font(.subheadline.weight(.semibold)).foregroundStyle(CameraTheme.text)   // 15pt at the default size
            Text("Shoot a photo and it lands here.")
              .font(.caption).foregroundStyle(CameraTheme.dim)   // 12pt at the default size
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 56)
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            ForEach(model.library) { asset in
              Button { libraryShown = false; review = asset } label: {
                // grid tier only — the sheet never decodes stored 2048 px frames
                Image(uiImage: asset.thumbnail).resizable().scaledToFill()
                  .frame(height: 140).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
              }.buttonStyle(.plain)
              // an unlabeled image button reads as nothing — name the frame
              .accessibilityLabel("\(asset.stock.name) photograph")
              .accessibilityHint("Opens this frame for review")
            }
          }.padding(12)
        }
      }
      .background(CameraTheme.bg)
      .navigationTitle("Roll").navigationBarTitleDisplayMode(.inline)
      .toolbarColorScheme(.dark, for: .navigationBar)
    }
    .presentationDetents([.medium, .large])
  }

  /// hardware exists but the photographer declined (or is restricted from)
  /// camera access — distinct from the Simulator/no-hardware path, which never
  /// prompts and leaves authorization at .notDetermined. Guarding on the
  /// authorization status (not the target) keeps the CI plate fallback intact.
  private var cameraAccessDenied: Bool {
    camera.authorization == .denied || camera.authorization == .restricted
  }

  /// the viewfinder's access-off state: a plain explanation and one route to
  /// Settings, over the plate. The shutter is inert while this shows.
  private var permissionOverlay: some View {
    ZStack {
      Color.black.opacity(0.72)
      VStack(spacing: 12) {
        Image(systemName: "lock.slash")
          .font(.system(size: 30)).foregroundStyle(CameraTheme.dim)
        Text("Camera access is off")
          .font(.spaceMono(14, bold: true)).foregroundStyle(CameraTheme.text)
        Text("Turn on camera access to shoot with LensMood.")
          .font(.spaceMono(10)).foregroundStyle(CameraTheme.dim)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
        }
        .buttonStyle(InstrumentButtonStyle(kind: .primary))
        .frame(maxWidth: 220)
      }
      .padding(28)
    }
    .accessibilityElement(children: .contain)
  }

  private var developingOverlay: some View {
    ZStack {
      Color.black.opacity(0.6).ignoresSafeArea()
      VStack(spacing: 12) {
        ProgressView().tint(CameraTheme.gold)
        Text("DEVELOPING").scaledFont(size: 11, weight: .bold, design: .monospaced, relativeTo: .caption2).tracking(2).foregroundStyle(.white)
        Text("metering · relighting · developing \(loadedStock.name)")
          .font(.spaceMono(9)).foregroundStyle(.white.opacity(0.7))
      }
    }
  }

  // MARK: first-run guide

  private var guideOverlay: some View {
    ZStack {
      Color.black.opacity(0.82).ignoresSafeArea()
      // accessibility sizes: the grown guide outruns the screen and its
      // centered card would clip both ends — trapping the user, since the
      // only way out is the button. The card scrolls instead.
      Group {
        if typeSize.isAccessibilitySize {
          ScrollView(showsIndicators: false) { guideCard }
        } else {
          guideCard
        }
      }
      .background(CameraTheme.panel)
      .clipShape(RoundedRectangle(cornerRadius: 20))
      .overlay(RoundedRectangle(cornerRadius: 20).stroke(CameraTheme.line, lineWidth: 1))
      .padding(28)
    }
    .transition(.opacity)
  }

  private var guideCard: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("YOUR CAMERA").font(.spaceMono(12, bold: true)).tracking(2).foregroundStyle(CameraTheme.gold)
      guideRow("camera.aperture", "Tap the shutter to shoot",
               "The frame is metered, auto-relit, and developed through the loaded film.")
      guideRow("hand.draw", "Drag the dial to expose",
               "Tap ISO / Shutter / Aperture / EV up top, then drag the wheel to change it.")
      guideRow("viewfinder", "Tap the frame to focus",
               "Sets focus and metering on the spot you touch.")
      guideRow("photo.on.rectangle", "Where your photos go",
               "Every shot lands on your in-app Roll. Tap Save to Photos to export it to your iPhone’s camera roll.")
      Button { dismissGuide() } label: { Text("Start shooting").frame(maxWidth: .infinity) }
        .buttonStyle(InstrumentButtonStyle(kind: .primary)).padding(.top, 4)
    }
    .padding(24)
  }

  private func guideRow(_ icon: String, _ title: String, _ body: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: icon).scaledFont(size: 18, relativeTo: .title3).foregroundStyle(CameraTheme.gold)
        .frame(width: 26, alignment: .center)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).scaledFont(size: 14, weight: .semibold, relativeTo: .footnote).foregroundStyle(CameraTheme.text)
        Text(body).font(.caption).foregroundStyle(CameraTheme.dim)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func dismissGuide() {
    withAnimation { guideShown = false }
    guideSeen = true
  }

  private func reviewCard(_ asset: DevelopedAsset) -> some View {
    ZStack {
      Color.black.ignoresSafeArea()
      VStack(spacing: 16) {
        HStack {
          Text("REVIEW").scaledFont(size: 11, weight: .bold, design: .monospaced, relativeTo: .caption2).tracking(2).foregroundStyle(CameraTheme.dim)
          Spacer()
          Button { review = nil } label: { Image(systemName: "xmark").foregroundStyle(.white) }
            .accessibilityLabel("Close review")   // the bare glyph reads as "xmark"
        }.padding(.horizontal, 20)

        Image(uiImage: reviewFrame(for: asset))
          .resizable().scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16)

        HStack {
          Text(asset.stock.name.uppercased())
          Spacer()
          Text("\(camera.settings.captureMode.rawValue.uppercased()) · ƒ/\(fmtF(camera.settings.aperture)) · ISO \(Int(camera.settings.iso))")
        }
        .scaledFont(size: 10, weight: .semibold, design: .monospaced, relativeTo: .caption2)
        .lineLimit(1).minimumScaleFactor(0.8)
        .foregroundStyle(CameraTheme.dim).padding(.horizontal, 20)

        if !asset.decisions.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(asset.decisions, id: \.self) { Text("· \($0)").font(.caption).foregroundStyle(.white.opacity(0.85)) }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
        }

        // honest attribution for the lighting model
        Text("Scene-aware lighting · Apple Vision + Core Image, on device")
          .font(.spaceMono(9))
          .foregroundStyle(CameraTheme.faint)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 20).padding(.top, 4)

        Spacer()

        // make the photo's destination unmistakable
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill")
          Text("On your Roll — Save to Photos to export to your iPhone")
        }
        .font(.spaceMono(10))
        .foregroundStyle(CameraTheme.gold)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)

        HStack(spacing: 12) {
          if asset.image != nil {
            // the fresh shot: retaking discards a frame just taken — no confirm
            Button("Retake") { model.remove(asset); review = nil }
              .buttonStyle(InstrumentButtonStyle(kind: .secondary))
              .disabled(isSavingShot)
          } else {
            // an archived Roll frame: destroying a kept photograph must confirm
            // and name the consequence, the Library's delete-confirm idiom
            Button(role: .destructive) {
              reviewDeleteRequested = true
            } label: {
              Text("Delete")
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.controlHeight)
            }
            .disabled(isSavingShot)
            .confirmationDialog(
              "Delete this frame?",
              isPresented: $reviewDeleteRequested,
              titleVisibility: .visible
            ) {
              Button("Delete Frame", role: .destructive) { model.remove(asset); review = nil }
              Button("Cancel", role: .cancel) {}
            } message: {
              Text("It leaves your roll for good. Anything already saved to Photos stays saved.")
            }
          }
          Button(isSavingShot ? "Saving…" : "Save to Photos") { save(asset) }
            .buttonStyle(InstrumentButtonStyle(kind: .primary))
            .disabled(isSavingShot)
        }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 30)
      }.padding(.top, 60)
    }
    .transition(.opacity)
    .task(id: asset.id) {
      // Roll picks arrive with only their thumbnail resident — decode the
      // stored 2048 px frame off-main for the full-screen review
      guard asset.image == nil, reviewFullImage?.id != asset.id else { return }
      let full = await Task.detached(priority: .userInitiated) {
        asset.loadFullImage()
      }.value
      if let full { reviewFullImage = (asset.id, full) }
    }
  }

  /// the frame the review shows: the fresh shot's in-memory frame, the landed
  /// full decode for a Roll pick, or the thumbnail while the decode runs
  private func reviewFrame(for asset: DevelopedAsset) -> UIImage {
    asset.image
      ?? (reviewFullImage?.id == asset.id ? reviewFullImage?.image : nil)
      ?? asset.thumbnail
  }

  // MARK: actions

  private func focusHere(_ location: CGPoint, in size: CGSize) {
    camera.focus(
      at: CGPoint(x: location.x / size.width, y: max(0, location.y) / (size.height * 0.62)),
      // the hardware's point-of-interest space is the unrotated sensor's, not
      // the view's — the preview layer performs the honest conversion
      devicePoint: focusConverter.devicePoint(fromViewPoint: location)
    )
    let pulse = FocusPulse(point: location)
    focusPulse = pulse
    UISelectionFeedbackGenerator().selectionChanged()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
      if focusPulse?.id == pulse.id { withAnimation(.easeOut(duration: 0.25)) { focusPulse = nil } }
    }
  }

  private func shoot() {
    // a double-fired shutter tap must not spend two frames for one shot —
    // .disabled() only lands on the next render pass (the save() precedent)
    guard !camera.isCapturing, !isDeveloping else { return }
    // access declined on a real device: the shutter is inert — developing the
    // bundled plate into the user's Roll (or spending a loaded exposure on it)
    // is never the answer. The overlay's Open Settings is the way forward.
    if cameraAccessDenied {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      showModeHint("Camera access is off — open Settings to shoot.")
      return
    }
    // The film door, at the shutter (the same ExposureRoll every develop
    // obeys — DevelopView documents the design). .open for every camera
    // while Store.everythingFreeForNow.
    switch store.developAccess(for: loadedStock) {
    case .open:
      break
    case .loaded:
      // shooting spends a loaded exposure; the shot is the user's — it
      // lands on the Roll and exports exactly like any other
      guard store.spendExposure(on: loadedStock) else { return }
      let assetID = UUID()
      pendingShotSpend = loadedStock.id
      pendingShotAssetID = assetID
      // park a crash-safe marker: force-quit before the develop lands and
      // launch reconciliation gives the exposure back
      ExposureLedger.shared.recordPendingSpend(assetID: assetID, on: loadedStock.id)
    case .spent:
      // out of film: the shutter goes slack — a fact, not a scold. The
      // offer lives behind the film bar, never over the viewfinder.
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      showModeHint("Out of film — \(loadedStock.name) is spent. Load another camera.")
      return
    }
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
      withAnimation(.easeIn(duration: 0.12)) { shutterFlash = false }
    }
    camera.capture(fallback: BundleMedia.image("style-\(loadedStock.id)")) { develop($0) }
  }

  private func develop(_ image: UIImage) {
    isDeveloping = true
    let token = UUID(); renderToken = token
    let stock = loadedStock
    let capture = camera.settings
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result {
        try FilmEngine.shared.develop(image, with: stock.recipe, maxPixelSize: 2048, seed: 43, capture: capture)
      }
      DispatchQueue.main.async {
        guard renderToken == token else { return }
        isDeveloping = false
        switch result {
        case .success(let render):
          pendingShotSpend = nil   // the spent frame delivered — it's kept
          // land under the id reserved at the spend so launch reconciliation
          // recognizes this exposure as delivered (the marker is retired at
          // that cross-check, never refunded)
          let asset = DevelopedAsset(
            id: pendingShotAssetID ?? UUID(),
            image: render.image, source: image, stock: stock, decisions: render.decisions
          )
          pendingShotAssetID = nil
          model.add(asset)
          withAnimation { review = asset }
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failure(let error):
          // a film-bought shot that failed to develop gives its frame
          // back — the camera never eats an exposure it didn't deliver
          if pendingShotSpend == stock.id {
            pendingShotSpend = nil
            if let id = pendingShotAssetID {
              ExposureLedger.shared.clearPendingSpend(assetID: id)
              pendingShotAssetID = nil
            }
            store.refundExposure(on: stock)
          }
          errorMessage = error.localizedDescription
        }
      }
    }
  }

  private func save(_ asset: DevelopedAsset) {
    guard !isSavingShot else { return }   // a double-tap must not develop twice
    isSavingShot = true
    let stock = asset.stock, capture = camera.settings, source = asset.source
    DispatchQueue.global(qos: .userInitiated).async {
      // Fresh shots still hold their original: re-develop it at 4096 (peak
      // memory stays safe on 2–3 GB devices; 8192 risked jetsam). A frame
      // reopened from the Roll no longer holds its original (two-tier memory
      // law), so its stored 2048 px develop exports as-is.
      let full: UIImage?
      if let source {
        full = try? FilmEngine.shared.develop(source, with: stock.recipe, maxPixelSize: 4096, seed: 43, capture: capture).image
      } else {
        full = asset.loadFullImage()
      }
      let export = full ?? asset.image ?? asset.thumbnail
      DispatchQueue.main.async {
        Task { @MainActor in
          defer { isSavingShot = false }
          do {
            try await PhotoLibraryWriter.save(image: export)
            saveTick += 1; review = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
          } catch { errorMessage = error.localizedDescription }
        }
      }
    }
  }

  // MARK: dial plumbing

  private func setActiveDial(to index: Int) {
    switch activeDial {
    case .aperture: camera.settings.aperture = Self.apertures[clamp(index, Self.apertures)]
    case .shutter: camera.settings.shutter = Self.shutters[clamp(index, Self.shutters)]
    case .iso: camera.settings.iso = Self.isos[clamp(index, Self.isos)]
    case .ev: camera.settings.exposureBiasEV = Self.evs[clamp(index, Self.evs)]
    }
    camera.applyManualExposure(); tick()
  }

  private var activeIndex: Int {
    switch activeDial {
    case .aperture: return nearest(camera.settings.aperture, Self.apertures)
    case .shutter: return nearest(camera.settings.shutter, Self.shutters)
    case .iso: return nearest(camera.settings.iso, Self.isos)
    case .ev: return nearest(camera.settings.exposureBiasEV, Self.evs)
    }
  }
  private var activeStepCount: Int {
    switch activeDial {
    case .aperture: return Self.apertures.count
    case .shutter: return Self.shutters.count
    case .iso: return Self.isos.count
    case .ev: return Self.evs.count
    }
  }
  private var activeDialLabel: String {
    switch activeDial {
    case .aperture: return "ƒ/\(fmtF(camera.settings.aperture))"
    case .shutter: return fmtShutter(camera.settings.shutter)
    case .iso: return "ISO \(Int(camera.settings.iso))"
    case .ev: return fmtEV(camera.settings.exposureBiasEV)
    }
  }
  private var activeDialName: String {
    switch activeDial {
    case .aperture: return "APERTURE"
    case .shutter: return "SHUTTER"
    case .iso: return "ISO"
    case .ev: return "EXPOSURE"
    }
  }
  /// mixed-case for VoiceOver — the engraved all-caps labels can be spelled
  /// out letter by letter
  private var spokenDialName: String {
    switch activeDial {
    case .aperture: return "Aperture"
    case .shutter: return "Shutter"
    case .iso: return "ISO"
    case .ev: return "Exposure"
    }
  }

  private var flashLabel: String {
    switch camera.settings.flashMode { case .off: return "OFF"; case .auto: return "AUTO"; case .on: return "ON" }
  }

  // hardware answers zoom/flip on a device; without hardware the plate does
  private var plateZoom: CGFloat { camera.isAvailable ? 1 : CGFloat(max(1, camera.settings.zoom)) }
  private var plateMirrored: Bool { !camera.isAvailable && camera.position == .front }
  private func tick() { UISelectionFeedbackGenerator().selectionChanged() }

  static let apertures: [Double] = [1.2,1.4,1.6,1.8,2,2.2,2.5,2.8,3.2,3.5,4,4.5,5,5.6,6.3,7.1,8,9,11,13,16,22]
  static let shutters: [Double] = [30,15,8,4,2,1,0.5,0.25,1.0/8,1.0/15,1.0/30,1.0/60,1.0/125,1.0/250,1.0/500,1.0/1000,1.0/2000,1.0/4000,1.0/8000]
  static let isos: [Double] = [25,50,64,100,125,160,200,250,320,400,640,800,1250,1600,3200,6400,12800]
  static let evs: [Double] = stride(from: -3.0, through: 3.0, by: 1.0/3).map { ($0 * 100).rounded() / 100 }

  private func clamp(_ i: Int, _ arr: [Double]) -> Int { min(arr.count - 1, max(0, i)) }
  private func nearest(_ v: Double, _ arr: [Double]) -> Int {
    arr.enumerated().min(by: { abs($0.element - v) < abs($1.element - v) })?.offset ?? 0
  }
  private func fmtF(_ f: Double) -> String { f == f.rounded() ? String(format: "%.0f", f) : String(format: "%.1f", f) }
  private func fmtShutter(_ t: Double) -> String { t >= 1 ? "\(Int(t.rounded()))\"" : "1/\(Int((1 / t).rounded()))" }
  private func fmtEV(_ e: Double) -> String { abs(e) < 0.05 ? "±0.0" : String(format: "%+.1f", e) }
}

/// A horizontal command wheel: drag to scrub the active parameter in 1/3-stop
/// detents, with a fixed gold center index and ticks that slide beneath.
private struct CommandWheel: View {
  let steps: Int
  let index: Int
  let onChange: (Int) -> Void
  @State private var dragBase: Int?
  private let spacing: CGFloat = 13

  var body: some View {
    GeometryReader { geo in
      // draw a window of ticks CENTERED on the current index instead of a
      // fixed 40-tick strip offset left: the old strip (508pt) ran out from
      // under the gold index at high dial positions — and, being wider than the
      // screen, forced the whole wheel row to overflow. The window fills the
      // visible strip at every position and never exceeds it.
      let half = Int((geo.size.width / spacing / 2).rounded(.up)) + 2
      ZStack {
        ForEach(index - half...index + half, id: \.self) { i in
          Rectangle().fill(Color.white.opacity(i % 5 == 0 ? 0.5 : 0.22))
            .frame(width: 1, height: i % 5 == 0 ? 20 : 12)
            // tall ticks stay pinned to absolute multiples of 5 as you scrub
            .offset(x: CGFloat(i - index) * spacing)
        }
        Rectangle().fill(CameraTheme.gold).frame(width: 2, height: 26)
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .clipped()
      .contentShape(Rectangle())
      .gesture(
        DragGesture()
          .onChanged { value in
            if dragBase == nil { dragBase = index }
            let delta = Int((-value.translation.width / spacing).rounded())
            onChange((dragBase ?? index) + delta)
          }
          .onEnded { _ in dragBase = nil }
      )
    }
  }
}

/// A tap-to-focus confirmation box that snaps in, then holds — the standard
/// camera affordance that tells the user the focus point registered.
private struct FocusReticle: View {
  @State private var landed = false
  var body: some View {
    RoundedRectangle(cornerRadius: 5)
      .stroke(CameraTheme.gold, lineWidth: 1.5)
      .frame(width: 74, height: 74)
      .scaleEffect(landed ? 1 : 1.4)
      .opacity(landed ? 0.95 : 0)
      .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { landed = true } }
  }
}

private struct CornerTicks: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path(); let t: CGFloat = 18
    for corner in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight] {
      let dx: CGFloat = corner.x == rect.minX ? t : -t
      let dy: CGFloat = corner.y == rect.minY ? t : -t
      p.move(to: CGPoint(x: corner.x, y: corner.y + dy)); p.addLine(to: corner); p.addLine(to: CGPoint(x: corner.x + dx, y: corner.y))
    }
    return p
  }
}

private struct GridOverlay: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    for i in 1..<3 {
      let x = rect.minX + rect.width * CGFloat(i) / 3
      p.move(to: CGPoint(x: x, y: rect.minY)); p.addLine(to: CGPoint(x: x, y: rect.maxY))
      let y = rect.minY + rect.height * CGFloat(i) / 3
      p.move(to: CGPoint(x: rect.minX, y: y)); p.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    return p
  }
}

private extension CGRect {
  var topLeft: CGPoint { CGPoint(x: minX, y: minY) }
  var topRight: CGPoint { CGPoint(x: maxX, y: minY) }
  var bottomLeft: CGPoint { CGPoint(x: minX, y: maxY) }
  var bottomRight: CGPoint { CGPoint(x: maxX, y: maxY) }
}
