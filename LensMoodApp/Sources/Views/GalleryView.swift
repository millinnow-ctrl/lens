import SwiftUI
import UIKit

/// The Library as a story: developed frames grouped into monthly rolls
/// (`Roll.group`), each roll presented as a film sleeve — a dark chrome strip
/// naming the month like a printed label ("JULY 2026 · 14 EXPOSURES", the same
/// strip idiom as the Home hero card) over a grid of mounted frames, each
/// mount carrying its camera's name and exposure number as a mono caption.
struct GalleryView: View {
  @EnvironmentObject private var model: AppModel
  @State private var selected: DevelopedAsset?

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    NavigationStack {
      Group {
        if model.library.isEmpty {
          emptyState
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
              ForEach(model.rolls) { roll in
                rollSection(roll)
              }
            }
            .padding(Theme.pagePadding)
            .padding(.bottom, 20)
          }
          .background(Theme.paper)
        }
      }
      .navigationTitle("Library")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(item: $selected) { asset in
        GalleryDetailView(asset: asset)
          .environmentObject(model)
      }
    }
  }

  // MARK: - Rolls

  private func rollSection(_ roll: Roll) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sleeveHeader(roll)
      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(Array(roll.assets.enumerated()), id: \.element.id) { index, asset in
          // exposures count up chronologically, so the newest frame (first in
          // the roll) wears the highest number — like a wound-on film counter
          frameCell(asset, exposure: roll.assets.count - index)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Roll \(roll.title), \(roll.exposureCount) exposures")
  }

  /// the sleeve's printed label — the dark chrome strip from the hero card,
  /// reused so the Library reads as the same designer's work
  private func sleeveHeader(_ roll: Roll) -> some View {
    HStack {
      HStack(spacing: 7) {
        Circle().fill(Theme.recRed).frame(width: 6, height: 6)
        Text(roll.title)
      }
      Spacer()
      Text("\(roll.exposureCount) \(roll.exposureCount == 1 ? "EXPOSURE" : "EXPOSURES")")
    }
    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
    .tracking(1)
    .foregroundStyle(Theme.viewfinderChrome)
    .padding(.horizontal, 12)
    .frame(height: 32)
    .frame(maxWidth: .infinity)
    .background(Theme.viewfinder)
    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(roll.sleeveLabel)
  }

  /// one mounted frame: the photograph in a thin white mount with its
  /// camera's name and exposure number as the technical caption
  private func frameCell(_ asset: DevelopedAsset, exposure: Int) -> some View {
    Button {
      selected = asset
    } label: {
      VStack(spacing: 5) {
        Color.clear
          .aspectRatio(0.8, contentMode: .fit)
          .overlay {
            // grid tier: the always-resident ≤480 px thumbnail — the grid
            // never decodes a stored 2048 px frame
            Image(uiImage: asset.thumbnail)
              .resizable()
              .scaledToFill()
          }
          .overlay(alignment: .topTrailing) {
            if asset.favorite {
              Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(.black.opacity(0.28), in: Circle())
                .padding(5)
            }
          }
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        HStack(spacing: 3) {
          Text(asset.stock.name.uppercased())
            .tracking(0.4)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(Theme.fog)
          Spacer(minLength: 2)
          Text(String(format: "%02d", exposure))
            .foregroundStyle(Theme.fog.opacity(0.65))
        }
        .font(.system(size: 8, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 2)
      }
      .padding(4)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .stroke(Theme.hairline, lineWidth: 1)
      )
      .oceanCardShadow()
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      "\(asset.stock.name), exposure \(exposure)\(asset.favorite ? ", favorite" : "")"
    )
  }

  private var emptyState: some View {
    VStack(spacing: 14) {
      Image(systemName: "rectangle.stack")
        .font(.system(size: 36, weight: .ultraLight))
      Text("No developed frames")
        .font(.system(size: 25, weight: .heavy))
      Text("Photographs you develop are kept here, in monthly rolls.")
        .font(.system(size: 14))
        .foregroundStyle(Theme.inkSoft)
        .multilineTextAlignment(.center)
      Button("Choose a camera") {
        model.selectedTab = .cameras
      }
      .buttonStyle(InstrumentButtonStyle(kind: .primary))
      .padding(.top, 8)
    }
    .foregroundStyle(Theme.ink)
    .padding(Theme.pagePadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.paper)
  }
}

/// One frame, remembered in full: the photograph, when it was developed, the
/// film it was developed on (with its develop decisions — the receipts), and
/// the actions — shoot that film again, save, share, delete.
private struct GalleryDetailView: View {
  let asset: DevelopedAsset

  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var sharePresented = false
  @State private var isSaving = false
  @State private var saveConfirmation = false
  @State private var errorMessage: String?
  /// the stored 2048 px frame, decoded once on appearance (two-tier: a
  /// persisted asset only carries its thumbnail in memory)
  @State private var fullImage: UIImage?

  /// "12 JUL 2026 · 14:32" — the frame's timestamp as a technical readout
  private static let developedAt: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMM yyyy · HH:mm"
    return formatter
  }()

  /// live favorite state (the passed asset is a snapshot; the model is truth)
  private var isFavorite: Bool {
    model.library.first(where: { $0.id == asset.id })?.favorite ?? asset.favorite
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          // thumbnail first, replaced by the full frame the moment its
          // decode lands — same geometry, so nothing jumps
          Image(uiImage: fullImage ?? asset.image ?? asset.thumbnail)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .background(Theme.viewfinder)

          TechnicalLabel(text: "Developed \(Self.developedAt.string(from: asset.createdAt))")

          filmPanel

          Button {
            shootThisFilmAgain()
          } label: {
            Text("Shoot this film again")
          }
          .buttonStyle(InstrumentButtonStyle(kind: .primary))
          .accessibilityHint("Opens \(asset.stock.name) to develop a new photograph")

          Button(isSaving ? "Saving to Photos" : "Save to Photos") {
            save()
          }
          .buttonStyle(InstrumentButtonStyle(kind: .secondary))
          .disabled(isSaving)

          Button("Share") {
            sharePresented = true
          }
          .buttonStyle(InstrumentButtonStyle(kind: .secondary))

          Button(role: .destructive) {
            model.remove(asset)
            dismiss()
          } label: {
            Text("Delete")
              .frame(maxWidth: .infinity)
              .frame(minHeight: Theme.controlHeight)
          }
        }
        .padding(Theme.pagePadding)
      }
      .background(Theme.paper)
      .navigationTitle("Frame")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            model.toggleFavorite(id: asset.id)
          } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
              .foregroundStyle(isFavorite ? Color(hex: "#E1251B") : Theme.inkSoft)
          }
          .accessibilityLabel(isFavorite ? "Remove favorite" : "Add favorite")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task {
        // decode the stored frame off-main; session assets already hold it
        guard fullImage == nil, asset.image == nil else { return }
        let asset = asset
        fullImage = await Task.detached(priority: .userInitiated) {
          asset.loadFullImage()
        }.value
      }
      .sheet(isPresented: $sharePresented) {
        // resolvedFrame: by presentation time the decode has landed; the
        // synchronous fallback is one bounded (≤2048 px) JPEG decode
        ActivitySheet(items: [resolvedFrame()])
      }
      .alert("Saved to Photos", isPresented: $saveConfirmation) {
        Button("OK", role: .cancel) {}
      }
      .alert("Could not save this photograph", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "Please try again.")
      }
    }
  }

  /// the photo remembers its film: the stock it was developed on, and the
  /// decisions that camera made for this photograph (the receipts)
  private var filmPanel: some View {
    InstrumentPanel {
      VStack(alignment: .leading, spacing: 14) {
        TechnicalLabel(text: "Developed on")
        HStack(spacing: 12) {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
              LinearGradient(
                colors: [Color(hex: asset.stock.g0), Color(hex: asset.stock.g1)],
                startPoint: .topLeading, endPoint: .bottomTrailing
              )
            )
            .frame(width: 44, height: 44)
            .overlay(
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
            )
          VStack(alignment: .leading, spacing: 2) {
            Text(asset.stock.name)
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(Theme.ink)
            Text(asset.stock.tagline)
              .font(.system(size: 13))
              .foregroundStyle(Theme.inkSoft)
            Text(asset.stock.exif)
              .font(.system(size: 10, weight: .medium, design: .monospaced))
              .tracking(0.4)
              .foregroundStyle(Theme.fog)
              .padding(.top, 1)
          }
          Spacer(minLength: 0)
        }

        if !asset.decisions.isEmpty {
          Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
          TechnicalLabel(text: "Development decisions")
          ForEach(Array(asset.decisions.enumerated()), id: \.offset) { index, decision in
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
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "Developed on \(asset.stock.name)."
        + (asset.decisions.isEmpty ? "" : " Decisions: \(asset.decisions.joined(separator: ". "))")
    )
  }

  /// route back into the develop flow with this frame's film loaded — the
  /// same pending hand-off HomeView uses for hero photo picks
  private func shootThisFilmAgain() {
    model.pendingStock = asset.stock
    model.selectedTab = .cameras
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    dismiss()
  }

  /// The best frame available right now: the decoded full frame, the session
  /// asset's in-memory frame, a fresh bounded decode, or (only if the stored
  /// file is unreadable) the thumbnail.
  private func resolvedFrame() -> UIImage {
    fullImage ?? asset.image ?? asset.loadFullImage() ?? asset.thumbnail
  }

  private func save() {
    isSaving = true
    let asset = asset
    let resident = fullImage ?? asset.image
    Task { @MainActor in
      do {
        // exports always use the full stored frame, decoded off-main if the
        // detail decode has not landed yet
        let frame = await Task.detached(priority: .userInitiated) {
          resident ?? asset.loadFullImage() ?? asset.thumbnail
        }.value
        try await PhotoLibraryWriter.save(image: frame)
        isSaving = false
        saveConfirmation = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch {
        isSaving = false
        errorMessage = error.localizedDescription
      }
    }
  }
}
