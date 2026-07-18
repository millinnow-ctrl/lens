import SwiftUI
import UIKit

/// The LensMood camera — a warm-gold pro instrument. Full-screen viewfinder with
/// a top-plate readout, aperture/shutter/ISO/EV dials, zoom + AF/MF, a film-canister
/// stock selector, Photo/Video/Portrait/Night modes, and a mechanical shutter. On
/// capture the scene is auto-relit and developed through the loaded camera.
struct CaptureView: View {
  @EnvironmentObject private var model: AppModel
  @StateObject private var camera = CameraController()

  @State private var loadedStock = Stock.all[0]
  @State private var activeDial: ActiveDial = .aperture
  @State private var showGrid = true
  @State private var mountPickerShown = false
  @State private var libraryShown = false

  @State private var isDeveloping = false
  @State private var review: DevelopedAsset?
  @State private var shutterFlash = false
  @State private var errorMessage: String?
  @State private var saveConfirmation = false
  @State private var isSavingShot = false
  @State private var renderToken = UUID()
  @State private var cameraSeeded = false

  // legibility helpers: tap-to-focus confirmation, a mode explainer, and a
  // one-time guide so a first-time user knows what every control does
  @State private var focusPulse: FocusPulse?
  @State private var modeHint: String?
  @State private var modeHintToken = UUID()
  @State private var guideShown = false
  @AppStorage("cameraGuideSeen") private var guideSeen = false

  struct FocusPulse: Equatable { let id = UUID(); let point: CGPoint }

  enum ActiveDial: CaseIterable { case aperture, shutter, iso, ev }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        CameraTheme.bg.ignoresSafeArea()
        VStack(spacing: 0) {
          topBar
          viewfinder(size: geo.size)
          modeHintBar
          filmBar
          modesRow
          captureRow
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
    .alert("Saved to Photos", isPresented: $saveConfirmation) { Button("OK", role: .cancel) {} }
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

  private var topBar: some View {
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
    .background(.ultraThinMaterial)
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
  }

  // MARK: viewfinder

  private func viewfinder(size: CGSize) -> some View {
    ZStack {
      CameraPreviewView(
        session: camera.session,
        isAvailable: camera.isAvailable,
        placeholder: BundleMedia.image("style-\(loadedStock.id)")
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
            Rectangle().fill(on ? CameraTheme.gold : .clear).frame(width: 18, height: 2).clipShape(Capsule())
          }
          .foregroundStyle(on ? CameraTheme.gold : CameraTheme.dim)
          .frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
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
            Image(uiImage: last.image).resizable().scaledToFill()
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
            Button {
              loadedStock = stock; camera.load(stock: stock); mountPickerShown = false
              UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            } label: {
              VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12)
                  .fill(LinearGradient(colors: [Color(hex: stock.g0), Color(hex: stock.g1)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                  .frame(height: 66)
                  .overlay(RoundedRectangle(cornerRadius: 12).stroke(stock.id == loadedStock.id ? CameraTheme.gold : .clear, lineWidth: 2.5))
                Text(stock.name).scaledFont(size: 12, weight: .semibold, relativeTo: .caption)
                  .foregroundStyle(CameraTheme.text).lineLimit(1).minimumScaleFactor(0.8)
                Text(stock.exif).scaledFont(size: 8, weight: .medium, design: .monospaced, relativeTo: .caption2)
                  .foregroundStyle(CameraTheme.dim).lineLimit(1).minimumScaleFactor(0.7)
              }
            }.buttonStyle(.plain)
          }
        }.padding(16)
      }
      .background(CameraTheme.bg)
      .navigationTitle("Load a film").navigationBarTitleDisplayMode(.inline)
      .toolbarColorScheme(.dark, for: .navigationBar)
    }
    .presentationDetents([.medium, .large])
  }

  private var librarySheet: some View {
    NavigationStack {
      ScrollView {
        if model.library.isEmpty {
          Image(systemName: "photo.on.rectangle")
            .scaledFont(size: 30, weight: .light, relativeTo: .largeTitle).foregroundStyle(CameraTheme.dim).padding(48)
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            ForEach(model.library) { asset in
              Button { libraryShown = false; review = asset } label: {
                Image(uiImage: asset.image).resizable().scaledToFill()
                  .frame(height: 140).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
              }.buttonStyle(.plain)
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
      .background(CameraTheme.panel)
      .clipShape(RoundedRectangle(cornerRadius: 20))
      .overlay(RoundedRectangle(cornerRadius: 20).stroke(CameraTheme.line, lineWidth: 1))
      .padding(28)
    }
    .transition(.opacity)
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
        }.padding(.horizontal, 20)

        Image(uiImage: asset.image).resizable().scaledToFit()
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
          Button("Retake") { model.remove(asset); review = nil }
            .buttonStyle(InstrumentButtonStyle(kind: .secondary))
            .disabled(isSavingShot)
          Button(isSavingShot ? "Saving…" : "Save to Photos") { save(asset) }
            .buttonStyle(InstrumentButtonStyle(kind: .primary))
            .disabled(isSavingShot)
        }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 30)
      }.padding(.top, 60)
    }.transition(.opacity)
  }

  // MARK: actions

  private func focusHere(_ location: CGPoint, in size: CGSize) {
    camera.focus(at: CGPoint(x: location.x / size.width, y: max(0, location.y) / (size.height * 0.62)))
    let pulse = FocusPulse(point: location)
    focusPulse = pulse
    UISelectionFeedbackGenerator().selectionChanged()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
      if focusPulse?.id == pulse.id { withAnimation(.easeOut(duration: 0.25)) { focusPulse = nil } }
    }
  }

  private func shoot() {
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
          let asset = DevelopedAsset(image: render.image, source: image, stock: stock, decisions: render.decisions)
          model.add(asset)
          withAnimation { review = asset }
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failure(let error):
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
      // 4096 keeps peak memory safe on 2–3 GB devices (8192 risked jetsam)
      let full = try? FilmEngine.shared.develop(source, with: stock.recipe, maxPixelSize: 4096, seed: 43, capture: capture).image
      DispatchQueue.main.async {
        Task { @MainActor in
          defer { isSavingShot = false }
          do {
            try await PhotoLibraryWriter.save(image: full ?? asset.image)
            saveConfirmation = true; review = nil
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
    ZStack {
      HStack(spacing: spacing - 1) {
        ForEach(0..<40, id: \.self) { i in
          Rectangle().fill(Color.white.opacity(i % 5 == 0 ? 0.5 : 0.22))
            .frame(width: 1, height: i % 5 == 0 ? 20 : 12)
        }
      }
      .offset(x: -CGFloat(index) * spacing)
      .mask(Rectangle())
      Rectangle().fill(CameraTheme.gold).frame(width: 2, height: 26)
    }
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
