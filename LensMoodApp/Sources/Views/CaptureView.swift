import SwiftUI
import UIKit

/// The Red Ring — LensMood's own pro camera. A full-screen DSLR viewfinder with
/// a top-plate LCD, command dials for aperture / shutter / ISO / exposure, a
/// mechanical shutter, and a lens-mount picker for the loaded camera personality.
/// The shot develops through that camera, with the dials genuinely changing the
/// look. No system camera, no upload chooser.
struct CaptureView: View {
  @EnvironmentObject private var model: AppModel
  @StateObject private var camera = CameraController()

  @State private var loadedStock = Stock.all[0]
  @State private var activeDial: ActiveDial = .aperture
  @State private var showGrid = false
  @State private var mountPickerShown = false

  @State private var isDeveloping = false
  @State private var review: DevelopedAsset?
  @State private var shutterFlash = false
  @State private var errorMessage: String?
  @State private var saveConfirmation = false
  @State private var renderToken = UUID()

  enum ActiveDial: CaseIterable { case aperture, shutter, iso, ev }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        Color.black.ignoresSafeArea()

        // the frame the sensor sees
        viewfinder(size: geo.size)

        // pro-camera chrome over the frame
        VStack(spacing: 0) {
          topPlateLCD
          Spacer()
          bottomCluster
        }
        .padding(.top, geo.safeAreaInsets.top > 0 ? 0 : 8)

        if shutterFlash {
          Color.white.ignoresSafeArea().transition(.opacity)
        }
      }
      .ignoresSafeArea(edges: .bottom)
    }
    .overlay { if isDeveloping { developingOverlay } }
    .overlay { if let review { reviewCard(review) } }
    .sheet(isPresented: $mountPickerShown) { mountPicker }
    .alert("Saved to Photos", isPresented: $saveConfirmation) {
      Button("OK", role: .cancel) {}
    }
    .alert("Could not complete that", isPresented: Binding(
      get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
    )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Try again.") }
    .onAppear {
      camera.load(stock: loadedStock)
      camera.configure()
    }
    .onDisappear { camera.stop() }
    .statusBarHidden(true)
  }

  // MARK: viewfinder + framelines

  private func viewfinder(size: CGSize) -> some View {
    let gateW = size.width
    let gateH = gateW * 2 / 3          // full-frame 3:2
    return ZStack {
      CameraPreviewView(
        session: camera.session,
        isAvailable: camera.isAvailable,
        placeholder: BundleMedia.image("style-\(loadedStock.id)")
      )
      .frame(width: size.width, height: size.height)
      .contentShape(Rectangle())
      .onTapGesture { location in
        camera.focus(at: CGPoint(x: location.x / size.width, y: location.y / size.height))
      }

      // 3:2 letterbox mattes
      VStack {
        Rectangle().fill(Theme.viewfinder.opacity(0.86))
          .frame(height: max(0, (size.height - gateH) / 2))
        Spacer()
        Rectangle().fill(Theme.viewfinder.opacity(0.86))
          .frame(height: max(0, (size.height - gateH) / 2))
      }
      .allowsHitTesting(false)

      // gate + corner ticks + optional grid
      framelines(gateW: gateW, gateH: gateH)
        .allowsHitTesting(false)
    }
  }

  private func framelines(gateW: CGFloat, gateH: CGFloat) -> some View {
    ZStack {
      Rectangle().stroke(Theme.viewfinderChrome.opacity(0.55), lineWidth: 1)
        .frame(width: gateW - 2, height: gateH)
      if showGrid {
        GridOverlay().stroke(Theme.viewfinderChrome.opacity(0.16), lineWidth: 0.5)
          .frame(width: gateW - 2, height: gateH)
      }
      CornerTicks().stroke(Theme.viewfinderChrome, lineWidth: 1.5)
        .frame(width: gateW - 2, height: gateH)
      // center AF reticle
      Rectangle().stroke(Theme.viewfinderChrome.opacity(0.8), lineWidth: 1)
        .frame(width: 62, height: 62)
    }
  }

  // MARK: top-plate LCD

  private var topPlateLCD: some View {
    VStack(spacing: 8) {
      HStack(spacing: 14) {
        lcdToken(camera.settings.mode.rawValue, dial: nil, wide: true)
        lcdToken("ƒ/\(fmtF(camera.settings.aperture))", dial: .aperture)
        lcdToken(fmtShutter(camera.settings.shutter), dial: .shutter)
        lcdToken("ISO \(Int(camera.settings.iso))", dial: .iso)
        lcdToken(fmtEV(camera.settings.exposureBiasEV), dial: .ev)
        Spacer(minLength: 0)
        VStack(alignment: .trailing, spacing: 3) {
          Text(loadedStock.name.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.viewfinderChrome)
          LinearGradient(colors: [Color(hex: loadedStock.g0), Color(hex: loadedStock.g1)],
                         startPoint: .leading, endPoint: .trailing)
            .frame(width: 54, height: 3).clipShape(Capsule())
        }
      }
      // EV ruler
      evRuler
      if !camera.isAvailable {
        Text("SIM · NO CAM")
          .font(.system(size: 8, weight: .semibold, design: .monospaced))
          .tracking(1)
          .foregroundStyle(Theme.viewfinderChrome.opacity(0.7))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 16).padding(.vertical, 10)
    .background(Theme.viewfinder.opacity(0.72))
  }

  private func lcdToken(_ text: String, dial: ActiveDial?, wide: Bool = false) -> some View {
    let isActive = dial != nil && dial == activeDial
    return Text(text)
      .font(.system(size: wide ? 15 : 13, weight: .semibold, design: .monospaced))
      .foregroundStyle(dialBeyondHardware(dial) ? Theme.viewfinderChrome.opacity(0.45) : Theme.viewfinderChrome)
      .overlay(alignment: .bottom) {
        if isActive { Rectangle().fill(Theme.accentLight).frame(height: 2).offset(y: 5) }
      }
      .overlay(alignment: .topTrailing) {
        if dialBeyondHardware(dial) {
          Text("LOOK").font(.system(size: 6, weight: .bold)).foregroundStyle(Theme.accentLight).offset(x: 4, y: -4)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture { if let dial { activeDial = dial; tick() } }
  }

  private var evRuler: some View {
    GeometryReader { g in
      let mid = g.size.width / 2
      let ev = camera.settings.captureEV
      ZStack(alignment: .leading) {
        ForEach(-9...9, id: \.self) { i in
          Rectangle()
            .fill(Theme.viewfinderChrome.opacity(i % 3 == 0 ? 0.5 : 0.25))
            .frame(width: 1, height: i % 3 == 0 ? 8 : 5)
            .offset(x: mid + CGFloat(i) * (mid / 9.5) - 0.5, y: i % 3 == 0 ? 0 : 1.5)
        }
        Circle().fill(Theme.recRed)
          .frame(width: 6, height: 6)
          .offset(x: mid + CGFloat(min(3, max(-3, ev)) / 3) * (mid * 0.95) - 3, y: 1)
      }
    }
    .frame(height: 12)
  }

  // MARK: bottom command cluster

  private var bottomCluster: some View {
    VStack(spacing: 14) {
      commandWheel
      modeChips
      HStack(alignment: .center) {
        mountChip
        Spacer()
        shutterButton
        Spacer()
        reviewThumb
      }
      .padding(.horizontal, 26)
      HStack(spacing: 10) {
        focalPill
        flashButton
        gridButton
      }
    }
    .padding(.top, 16)
    .padding(.bottom, 30)
    .background(
      LinearGradient(colors: [.clear, Theme.viewfinder.opacity(0.92)],
                     startPoint: .top, endPoint: .bottom)
    )
  }

  private var commandWheel: some View {
    VStack(spacing: 4) {
      Text(activeDialLabel)
        .font(.system(size: 22, weight: .bold, design: .monospaced))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 4)
      CommandWheel(steps: activeStepCount, index: activeIndex) { newIndex in
        setActiveDial(to: newIndex)
      }
      .frame(height: 46)
      Text(activeDialCaption)
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .tracking(1.5)
        .foregroundStyle(Theme.viewfinderChrome)
    }
    .padding(.horizontal, 24)
  }

  private var modeChips: some View {
    HStack(spacing: 8) {
      ForEach(ExposureMode.allCases, id: \.self) { mode in
        let on = camera.settings.mode == mode
        Text(mode.rawValue)
          .font(.system(size: 13, weight: .bold, design: .monospaced))
          .foregroundStyle(on ? .white : Theme.viewfinderChrome)
          .frame(width: 40, height: 30)
          .background(on ? AnyShapeStyle(Theme.brandFill) : AnyShapeStyle(Color.white.opacity(0.06)))
          .clipShape(Capsule())
          .onTapGesture { camera.settings.mode = mode; camera.applyManualExposure(); tick() }
      }
    }
  }

  private var shutterButton: some View {
    Button { shoot() } label: {
      ZStack {
        Circle().fill(Theme.surface).frame(width: 78, height: 78)
        Circle().stroke(Theme.recRed, lineWidth: 3).frame(width: 66, height: 66)
        Circle().fill(Theme.surface).frame(width: 58, height: 58)
      }
      .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
      .scaleEffect(camera.isCapturing ? 0.92 : 1)
    }
    .buttonStyle(.plain)
    .disabled(camera.isCapturing || isDeveloping)
    .accessibilityLabel("Shutter")
  }

  private var mountChip: some View {
    Button { mountPickerShown = true } label: {
      ZStack {
        Circle().fill(Color.white.opacity(0.08)).frame(width: 52, height: 52)
        Circle().stroke(LinearGradient(colors: [Color(hex: loadedStock.g0), Color(hex: loadedStock.g1)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 3)
          .frame(width: 46, height: 46)
        Image(systemName: loadedStock.symbol).font(.system(size: 18)).foregroundStyle(.white)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Choose camera: \(loadedStock.name)")
  }

  private var reviewThumb: some View {
    Button { if let last = model.library.first { review = last } } label: {
      ZStack {
        RoundedRectangle(cornerRadius: 8).stroke(Theme.viewfinderChrome, lineWidth: 1).frame(width: 48, height: 48)
        if let last = model.library.first {
          Image(uiImage: last.image).resizable().scaledToFill().frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
          Image(systemName: "photo.on.rectangle").font(.system(size: 16)).foregroundStyle(Theme.viewfinderChrome)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Review last frame")
  }

  private var focalPill: some View {
    let focals: [Double] = [24, 35, 50, 85]
    return Button {
      let i = focals.firstIndex(of: camera.settings.focalLength) ?? 1
      camera.settings.focalLength = focals[(i + 1) % focals.count]; tick()
    } label: {
      Text("\(Int(camera.settings.focalLength))mm")
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white).padding(.horizontal, 12).frame(height: 30)
        .background(Color.white.opacity(0.08)).clipShape(Capsule())
    }.buttonStyle(.plain)
  }

  private var flashButton: some View {
    Button {
      camera.settings.flashMode = camera.settings.flashMode == .off ? .auto
        : (camera.settings.flashMode == .auto ? .on : .off)
      tick()
    } label: {
      HStack(spacing: 4) {
        Image(systemName: camera.settings.flashMode == .off ? "bolt.slash" : "bolt.fill")
        Text(flashLabel).font(.system(size: 11, weight: .semibold, design: .monospaced))
      }
      .foregroundStyle(camera.settings.flashMode == .off ? Theme.viewfinderChrome : Theme.accentLight)
      .padding(.horizontal, 12).frame(height: 30)
      .background(Color.white.opacity(0.08)).clipShape(Capsule())
    }.buttonStyle(.plain)
  }

  private var gridButton: some View {
    Button { showGrid.toggle(); tick() } label: {
      Image(systemName: "grid")
        .foregroundStyle(showGrid ? Theme.accentLight : Theme.viewfinderChrome)
        .frame(width: 34, height: 30)
        .background(Color.white.opacity(0.08)).clipShape(Capsule())
    }.buttonStyle(.plain)
  }

  // MARK: mount picker

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
                  .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                    stock.id == loadedStock.id ? Theme.accent : .clear, lineWidth: 2.5))
                Text(stock.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(stock.exif).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Theme.fog).lineLimit(1)
              }
            }.buttonStyle(.plain)
          }
        }.padding(16)
      }
      .background(Theme.paper)
      .navigationTitle("Mount a camera")
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.medium, .large])
  }

  // MARK: review

  private var developingOverlay: some View {
    ZStack {
      Color.black.opacity(0.55).ignoresSafeArea()
      VStack(spacing: 12) {
        ProgressView().tint(.white)
        Text("DEVELOPING").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(.white)
      }
    }
  }

  private func reviewCard(_ asset: DevelopedAsset) -> some View {
    ZStack {
      Color.black.ignoresSafeArea()
      VStack(spacing: 16) {
        HStack {
          Text("REVIEW").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Theme.viewfinderChrome)
          Spacer()
          Button { review = nil } label: { Image(systemName: "xmark").foregroundStyle(.white) }
        }.padding(.horizontal, 20)

        Image(uiImage: asset.image).resizable().scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .padding(.horizontal, 16)

        HStack {
          Text(asset.stock.name.uppercased())
          Spacer()
          Text("ƒ/\(fmtF(camera.settings.aperture)) · \(fmtShutter(camera.settings.shutter)) · ISO \(Int(camera.settings.iso))")
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .foregroundStyle(Theme.viewfinderChrome).padding(.horizontal, 20)

        if !asset.decisions.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(asset.decisions, id: \.self) { d in
              Text("· \(d)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            }
          }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
        }

        Spacer()
        HStack(spacing: 12) {
          Button("Retake") { review = nil }
            .buttonStyle(InstrumentButtonStyle(kind: .secondary))
          Button("Save to Photos") { save(asset) }
            .buttonStyle(InstrumentButtonStyle(kind: .primary))
        }.padding(.horizontal, 20).padding(.bottom, 30)
      }
      .padding(.top, 60)
    }
    .transition(.opacity)
  }

  // MARK: actions

  private func shoot() {
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
      withAnimation(.easeIn(duration: 0.12)) { shutterFlash = false }
    }
    let plate = BundleMedia.image("style-\(loadedStock.id)")
    camera.capture(fallback: plate) { image in
      develop(image)
    }
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
    let stock = asset.stock
    let capture = camera.settings
    let source = asset.source
    DispatchQueue.global(qos: .userInitiated).async {
      let full = try? FilmEngine.shared.develop(source, with: stock.recipe, maxPixelSize: 8192, seed: 43, capture: capture).image
      DispatchQueue.main.async {
        Task {
          do {
            try await PhotoLibraryWriter.save(image: full ?? asset.image)
            saveConfirmation = true
            review = nil
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
    camera.applyManualExposure()
    tick()
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
  private var activeDialCaption: String {
    switch activeDial {
    case .aperture: return "APERTURE"
    case .shutter: return "SHUTTER"
    case .iso: return "ISO"
    case .ev: return "EXPOSURE COMP"
    }
  }

  private func dialBeyondHardware(_ dial: ActiveDial?) -> Bool {
    guard camera.isAvailable, let dial else { return false }
    switch dial {
    case .iso: return camera.settings.iso < camera.limits.minISO || camera.settings.iso > camera.limits.maxISO
    case .shutter: return camera.settings.shutter < camera.limits.minShutter || camera.settings.shutter > camera.limits.maxShutter
    case .aperture: return true   // the iPhone lens aperture is fixed — always a look control
    case .ev: return false
    }
  }

  private var flashLabel: String {
    switch camera.settings.flashMode { case .off: return "OFF"; case .auto: return "AUTO"; case .on: return "ON" }
  }

  private func tick() { UISelectionFeedbackGenerator().selectionChanged() }

  // value tables (1/3-stop)
  static let apertures: [Double] = [1.2,1.4,1.6,1.8,2,2.2,2.5,2.8,3.2,3.5,4,4.5,5,5.6,6.3,7.1,8,9,10,11,13,14,16,18,20,22]
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

/// A horizontal command wheel: drag to scrub the active parameter in detented
/// 1/3-stop steps, with a fixed center index and tick marks that slide beneath.
private struct CommandWheel: View {
  let steps: Int
  let index: Int
  let onChange: (Int) -> Void
  @State private var dragBase: Int?

  private let spacing: CGFloat = 14

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06))
      HStack(spacing: spacing - 1) {
        ForEach(0..<40, id: \.self) { i in
          Rectangle().fill(Theme.viewfinderChrome.opacity(i % 5 == 0 ? 0.5 : 0.22))
            .frame(width: 1, height: i % 5 == 0 ? 22 : 14)
        }
      }
      .offset(x: -CGFloat(index) * spacing)
      .mask(RoundedRectangle(cornerRadius: 12))
      Rectangle().fill(Theme.accentLight).frame(width: 2, height: 30)   // fixed center
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

private struct CornerTicks: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path(); let t: CGFloat = 14
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
