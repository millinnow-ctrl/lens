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
  let stock: Stock

  @EnvironmentObject private var model: AppModel
  @State private var pickedItem: PhotosPickerItem?
  @State private var sourceImage: UIImage?
  @State private var developedImage: UIImage?
  @State private var decisions: [String] = []
  @State private var previewMode: PreviewMode = .developed
  @State private var compareFraction: CGFloat = 0.5
  @State private var isDeveloping = false
  @State private var errorMessage: String?
  @State private var sharePresented = false
  @State private var saveConfirmation = false
  @State private var renderID = UUID()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        cameraIdentity
        stage
        previewControl

        if isDeveloping {
          developingState
        } else if sourceImage == nil {
          photoPicker(title: "Choose a photograph")
        } else {
          actions
          if !decisions.isEmpty { decisionPanel }
        }

        privacyNote
      }
      .padding(Theme.pagePadding)
    }
    .background(Theme.paper)
    .navigationTitle(stock.name)
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: pickedItem) { item in
      load(item)
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

  private var cameraIdentity: some View {
    VStack(alignment: .leading, spacing: 5) {
      TechnicalLabel(text: stock.exif)
      Text(stock.tagline)
        .font(.system(size: 23, weight: .bold, design: .serif))
        .foregroundStyle(Theme.ink)
      Text("Best for \(stock.bestFor.lowercased()).")
        .font(.system(size: 14))
        .foregroundStyle(Theme.inkSoft)
    }
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
          Image(systemName: stock.symbol)
            .font(.system(size: 34, weight: .light))
          Text("Load one photograph")
            .font(.system(size: 17, weight: .semibold))
          Text("\(stock.name) will read the light and subject before it develops the frame.")
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.viewfinderChrome.opacity(0.78))
            .padding(.horizontal, 30)
        }
        .foregroundStyle(Theme.viewfinderChrome)
      }
    }
    .overlay(alignment: .top) {
      HStack {
        Text(stock.name.uppercased())
        Spacer()
        Text(isDeveloping ? "DEVELOPING" : stock.exif)
      }
      .font(.system(size: 9, weight: .semibold, design: .monospaced))
      .tracking(0.8)
      .foregroundStyle(Theme.viewfinderChrome)
      .padding(11)
    }
    .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
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
      Text("Measuring light, color, contrast, and dynamic range.")
        .font(.system(size: 13))
        .foregroundStyle(Theme.fog)
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
        Button("Save") { save() }
          .buttonStyle(InstrumentButtonStyle(kind: .primary))
          .disabled(developedImage == nil)
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

  private var privacyNote: some View {
    Label("Developed on this device", systemImage: "lock.fill")
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(Theme.fog)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.vertical, 4)
  }

  private func load(_ item: PhotosPickerItem?) {
    guard let item else { return }
    isDeveloping = true
    errorMessage = nil
    Task {
      do {
        guard let data = try await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
          throw FilmEngineError.unreadableImage
        }
        sourceImage = image
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
    let recipe = stock.recipe
    let seed = Double(stock.id.unicodeScalars.reduce(17) { ($0 * 31 + Int($1.value)) % 100_000 })

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
            stock: stock,
            decisions: render.decisions
          )
          model.add(asset)
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }

  private func save() {
    guard let developedImage else { return }
    UIImageWriteToSavedPhotosAlbum(developedImage, nil, nil, nil)
    saveConfirmation = true
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }
}

#Preview {
  NavigationStack {
    DevelopView(stock: Stock.all[0])
      .environmentObject(AppModel())
  }
}
