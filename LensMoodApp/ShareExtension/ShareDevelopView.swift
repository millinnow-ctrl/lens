import Photos
import SwiftUI
import UIKit

/// The Share-Sheet develop surface: one photograph in, the film rail (every
/// camera the user can develop with — all 18 while everything is free),
/// one intensity slider, Save to Photos. A compact cut of the app's
/// Develop flow wearing the same ocean identity, budgeted for the extension's
/// ~120 MB memory ceiling: the working frame is capped at 1500 px, previews
/// develop at 1024 px, and the subject pass (Vision faces + person mask) is
/// off (`analyzeSubjects: false`). The scene meter still reads every
/// photograph — adaptive exposure, light physics, and grain all behave — but
/// face protection and flash-falloff subject masking are deliberately absent
/// here; the full app runs them.
struct ShareDevelopView: View {
  // explicit init: the private @State below would otherwise make the
  // synthesized memberwise init private to this file
  init(loadPhoto: @escaping () async -> UIImage?, finish: @escaping () -> Void) {
    self.loadPhoto = loadPhoto
    self.finish = finish
  }

  let loadPhoto: () async -> UIImage?
  let finish: () -> Void

  @State private var source: UIImage?
  @State private var preview: UIImage?
  @State private var selectedID: String = Stock.all[0].id
  @State private var intensity: CGFloat = 1
  @State private var loading = true
  @State private var isSaving = false
  @State private var saved = false
  @State private var errorMessage: String?
  @State private var developTask: Task<Void, Never>?
  /// observed for the entitlement: post-flip the rail lists only unlocked
  /// cameras — the extension is a compact surface, not a side door around
  /// the develop gate. Identical to today while everything is free.
  @ObservedObject private var store = Store.shared

  private var selected: Stock { Stock.find(selectedID) }

  /// the cameras this user can develop with here: free-forever plus owned.
  /// The film door is an in-app ceremony (the exposure meter and its copy
  /// live in the app's Develop flow); the extension simply doesn't list
  /// what isn't open. All 18 while Store.everythingFreeForNow is true.
  private var availableStocks: [Stock] {
    Stock.all.filter { store.isUnlocked($0) }
  }

  var body: some View {
    VStack(spacing: 12) {
      header
      previewArea
      filmRail
      intensityRow
      actions
    }
    .padding(14)
    .background(Theme.paper.ignoresSafeArea())
    .task {
      // ownership first, so the rail and the default camera are right
      // before the first develop runs (instant while everything is free)
      await store.refreshEntitlement()
      if !store.isUnlocked(selected) {
        selectedID = availableStocks.first?.id ?? Stock.all[0].id
      }
      let photo = await loadPhoto()
      loading = false
      source = photo
      if let photo { develop(photo, with: selected) }
    }
    .alert("Could not develop", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "Please try again.")
    }
  }

  // MARK: pieces

  private var header: some View {
    HStack {
      Text("LENSMOOD")
        .scaledFont(size: 14, weight: .bold, design: .monospaced, relativeTo: .footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .tracking(2)
        .foregroundStyle(Theme.brandText)
      Spacer()
      Button {
        finish()
      } label: {
        // glyph fixed on purpose: it sits inside the fixed 30pt circle control
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.inkSoft)
          .frame(width: 30, height: 30)
          .background(Theme.surface)
          .clipShape(Circle())
          .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
          // 44pt minimum touch target around the 30pt glyph
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Close")
    }
  }

  @ViewBuilder private var previewArea: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        .fill(Theme.viewfinder)
      if let source {
        // strength blend, same idiom as the app's Develop flow: the developed
        // frame over the original at `intensity`
        ZStack {
          fitted(source)
          if let preview {
            fitted(preview).opacity(Double(intensity))
          }
        }
        .padding(8)
      } else if loading {
        ProgressView().tint(.white)
      } else {
        VStack(spacing: 8) {
          Image(systemName: "photo")
            .scaledFont(size: 26, relativeTo: .title)
            .foregroundStyle(.white.opacity(0.5))
          Text("No photograph arrived. Close and share an image again.")
            .font(.footnote)   // 13pt at the default size
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func fitted(_ image: UIImage) -> some View {
    Image(uiImage: image)
      .resizable()
      .scaledToFit()
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var filmRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(availableStocks) { stock in
          Button {
            select(stock)
          } label: {
            chip(stock)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(stock.name). \(stock.tagline)")
          .accessibilityAddTraits(stock.id == selectedID ? .isSelected : [])
        }
      }
      .padding(.horizontal, 2)
      .padding(.vertical, 2)
    }
  }

  private func chip(_ stock: Stock) -> some View {
    let on = stock.id == selectedID
    return VStack(spacing: 5) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(LinearGradient(
          colors: [Color(hex: stock.g0), Color(hex: stock.g1)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ))
        .frame(width: 52, height: 52)
        .overlay(
          // glyph fixed on purpose: pinned to the fixed 52pt swatch artwork
          Image(systemName: stock.symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(on ? Theme.accent : Theme.hairline, lineWidth: on ? 2 : 1)
        )
      Text(stock.name)
        .scaledFont(size: 9, weight: on ? .bold : .medium, relativeTo: .caption2)
        .foregroundStyle(on ? Theme.accent : Theme.fog)
        .lineLimit(1)
        // the rail chip stays 58pt wide: a grown name shrinks, never wraps
        .minimumScaleFactor(0.8)
        .frame(width: 58)
    }
  }

  private var intensityRow: some View {
    VStack(spacing: 6) {
      HStack {
        TechnicalLabel(text: "Intensity")
        Spacer()
        Text("\(Int((intensity * 100).rounded()))%")
          .scaledFont(size: 12, weight: .semibold, design: .monospaced, relativeTo: .caption)
          .foregroundStyle(Theme.inkSoft)
      }
      Slider(value: $intensity, in: 0...1)
        .tint(Theme.accent)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Intensity")
    .accessibilityValue("\(Int((intensity * 100).rounded())) percent")
  }

  private var actions: some View {
    HStack(spacing: 10) {
      Button("Cancel") {
        finish()
      }
      .buttonStyle(InstrumentButtonStyle(kind: .secondary))
      .frame(maxWidth: 110)
      Button {
        if saved { finish() } else { save() }
      } label: {
        if isSaving {
          ProgressView().tint(.white)
        } else if saved {
          Label("Saved — Done", systemImage: "checkmark")
        } else {
          Label("Save to Photos", systemImage: "square.and.arrow.down")
        }
      }
      .buttonStyle(InstrumentButtonStyle(kind: .primary))
      .disabled(source == nil || isSaving)
    }
  }

  // MARK: work

  private func select(_ stock: Stock) {
    guard stock.id != selectedID else { return }
    selectedID = stock.id
    saved = false
    if let source { develop(source, with: stock) }
  }

  private func develop(_ photo: UIImage, with stock: Stock) {
    developTask?.cancel()
    let previous = developTask
    let recipe = stock.recipe
    let seed = Self.seed(for: stock.id)
    developTask = Task { @MainActor in
      // serialize renders: at most one develop in flight keeps the extension
      // inside its memory ceiling even when the rail is swiped quickly
      await previous?.value
      guard !Task.isCancelled else { return }
      let image = try? await Task.detached(priority: .userInitiated) {
        try FilmEngine.shared.develop(
          photo,
          with: recipe,
          maxPixelSize: 1024,
          seed: seed,
          analyzeSubjects: false
        ).image
      }.value
      guard !Task.isCancelled else { return }
      if let image {
        preview = image
      } else {
        errorMessage = FilmEngineError.renderFailed.errorDescription
      }
    }
  }

  private func save() {
    guard let source, !isSaving else { return }
    isSaving = true
    developTask?.cancel()
    let pending = developTask
    let recipe = selected.recipe
    let seed = Self.seed(for: selected.id)
    let strength = intensity
    Task { @MainActor in
      // wait out any in-flight preview render before the save render
      await pending?.value
      do {
        // the working frame is already capped at 1500 px, so this is the
        // extension's full-quality develop
        let frame = try await Task.detached(priority: .userInitiated) { () -> UIImage in
          let developedFrame = try FilmEngine.shared.develop(
            source,
            with: recipe,
            seed: seed,
            analyzeSubjects: false
          ).image
          return blendedFrame(developed: developedFrame, over: source, intensity: strength)
        }.value
        try await PhotoLibraryWriter.save(image: frame)
        isSaving = false
        saved = true
      } catch {
        isSaving = false
        errorMessage = error.localizedDescription
      }
    }
  }

  /// per-camera deterministic grain seed — the same formula the app's Develop
  /// flow uses, so the extension's frame matches an in-app develop
  static func seed(for stockID: String) -> Double {
    Double(stockID.unicodeScalars.reduce(17) { ($0 * 31 + Int($1.value)) % 100_000 })
  }
}

/// Composite the developed frame over the original at `intensity`. Returns
/// the developed frame untouched at full strength (mirrors the app's Develop
/// save path).
private func blendedFrame(developed: UIImage, over base: UIImage, intensity: CGFloat) -> UIImage {
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
