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
  @Environment(\.dynamicTypeSize) private var typeSize

  /// three mounts across at regular sizes; two at accessibility sizes, where
  /// a third-width mount reduces the mono caption to a couple of glyphs
  private var columns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(), spacing: 10),
      count: typeSize.isAccessibilitySize ? 2 : 3
    )
  }

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
    .scaledFont(size: 10.5, weight: .semibold, design: .monospaced, relativeTo: .caption2)
    // one tight sleeve strip: shrink, never wrap
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .tracking(1)
    .foregroundStyle(Theme.viewfinderChrome)
    .padding(.horizontal, 12)
    .frame(minHeight: 32)
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
              // fixed on purpose: a badge glyph pinned over the photograph
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
        .scaledFont(size: 8, weight: .semibold, design: .monospaced, relativeTo: .caption2)
        .lineLimit(1)
        .padding(.horizontal, 2)
      }
      .padding(4)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .stroke(Theme.hairline, lineWidth: 1)
      )
      .oceanCardShadow(.resting)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      "\(asset.stock.name), exposure \(exposure)\(asset.favorite ? ", favorite" : "")"
    )
  }

  private var emptyState: some View {
    VStack(spacing: 14) {
      Image(systemName: "rectangle.stack")
        .scaledFont(size: 36, weight: .ultraLight, relativeTo: .largeTitle)
      Text("No developed frames")
        .scaledFont(size: 25, weight: .heavy, relativeTo: .title)
      Text("Developed photographs are kept here, in monthly rolls.")
        .scaledFont(size: 14, relativeTo: .footnote)
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

  /// what the share sheet is holding — the bare frame or the camera card.
  /// One item-typed presentation seat, for the same reason DevelopView has
  /// one: two boolean sheets on a single view chain can race.
  private struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
  }

  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var shareItem: ShareItem?
  /// guards the detached camera-card compose so a double-tap can't race two
  /// renders into the one share seat
  @State private var isComposingCard = false
  @State private var isSaving = false
  /// monotonic save counter driving the SavedTick (see SavedTick.swift)
  @State private var saveTick = 0
  @State private var deleteRequested = false
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
            // the photograph sits in a well, not on a card: the recessed tier
            // seats the dark stage against the paper instead of hovering it
            .oceanCardShadow(.well)
            // the unlabeled photograph was silent to VoiceOver
            .accessibilityLabel("Photograph developed on \(asset.stock.name)")

          TechnicalLabel(text: "Developed \(Self.developedAt.string(from: asset.createdAt))")

          filmPanel

          // The one action left in the body, and deliberately the quiet one.
          // Re-developing is a low-frequency choice; it used to hold the
          // primary slot at the top of a six-capsule wall while Save and
          // Share — the reason a frame gets opened at all — sat below the
          // fold. Save/Share are now toolbar chrome, one tap from open.
          Button {
            shootThisFilmAgain()
          } label: {
            Text("Shoot this film again")
          }
          .buttonStyle(InstrumentButtonStyle(kind: .secondary))
          .accessibilityHint("Opens \(asset.stock.name) to develop a new photograph")
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

        // Export is what a frame is opened for, so it lives in the chrome —
        // the Photos idiom: share as a glyph at the trailing edge, everything
        // else folded behind an ellipsis. The trailing edge caps at three
        // controls (share, ellipsis, Done) so a 375 pt device or a large
        // Dynamic Type size never collides them with the title; Save rides
        // first in the menu. Every control carries an explicit VoiceOver
        // label; a glyph alone is silent.
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            // resolvedFrame: by now the decode has landed; the synchronous
            // fallback is one bounded (≤2048 px) JPEG decode
            shareItem = ShareItem(image: resolvedFrame())
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
          .accessibilityLabel("Share")
          .accessibilityHint("Opens the share sheet with this photograph")
          .accessibilityShowsLargeContentViewer {
            Label("Share", systemImage: "square.and.arrow.up")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button {
              save()
            } label: {
              Label(isSaving ? "Saving to Photos…" : "Save to Photos",
                    systemImage: "square.and.arrow.down")
            }
            .disabled(isSaving)

            Button {
              shareCard()
            } label: {
              Label("Share as camera card", systemImage: "rectangle.on.rectangle.angled")
            }
            .disabled(isComposingCard)

            Button {
              printThisFrame()
            } label: {
              Label("Print this frame", systemImage: "photo.artframe")
            }

            Divider()

            Button(role: .destructive) {
              deleteRequested = true
            } label: {
              Label("Delete", systemImage: "trash")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .accessibilityLabel("More actions")
          .accessibilityHint("Save, share as a camera card, print this frame, or delete it")
          .accessibilityShowsLargeContentViewer {
            Label("More actions", systemImage: "ellipsis.circle")
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      // deleting is irreversible (no undo, no trash) — it must confirm and
      // name the consequence before anything is destroyed. Anchored on the
      // scroll view rather than on the button, because the button that raises
      // it now lives inside a Menu that dismisses itself on the tap.
      .confirmationDialog(
        "Delete this frame?",
        isPresented: $deleteRequested,
        titleVisibility: .visible
      ) {
        Button("Delete Frame", role: .destructive) {
          model.remove(asset)
          dismiss()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Leaves your roll for good. Saved copies stay in Photos.")
      }
      .task {
        // the frame detail's own vocabulary: a light impact on the re-develop
        // and print hand-offs, a success notification when a save lands.
        // Warmed on arrival, before any of the toolbar actions can be tapped.
        Haptics.prepare(.light)
        Haptics.prepare()
        // decode the stored frame off-main; session assets already hold it
        guard fullImage == nil, asset.image == nil else { return }
        let asset = asset
        fullImage = await Task.detached(priority: .userInitiated) {
          asset.loadFullImage()
        }.value
      }
      .sheet(item: $shareItem) { item in
        ActivitySheet(items: [item.image])
      }
      .savedTick(trigger: saveTick)
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
              .font(.body.weight(.bold))   // 17pt at the default size
              .foregroundStyle(Theme.ink)
            Text(asset.stock.tagline)
              .font(.footnote)   // 13pt at the default size
              .foregroundStyle(Theme.inkSoft)
            Text(asset.stock.exif)
              .scaledFont(size: 10, weight: .medium, design: .monospaced, relativeTo: .caption2)
              .lineLimit(1)
              .minimumScaleFactor(0.8)
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
                .scaledFont(size: 10, design: .monospaced, relativeTo: .caption2)
                .foregroundStyle(Theme.accent)
              Text(decision)
                .scaledFont(size: 14, relativeTo: .footnote)
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
  /// same pending hand-off HomeView uses for hero photo picks.
  ///
  /// Byte-stable replay: when this frame's original photograph and its reading
  /// were both persisted, carry the SAME source pixels and adopt the SAME
  /// reading into the Conductor (under a fresh key the develop then replays),
  /// so re-developing — on this camera or, via the rail, another — reads the
  /// photograph exactly once and reproduces the develop instead of a drifted
  /// re-read (the one-reading law across time). If either sidecar is missing
  /// (an old keep, or a schema-gated reading) fall back to the prior behavior:
  /// the camera opens and the user picks a photograph — never a broken flow,
  /// and never a fresh re-read masquerading as the persisted replay.
  private func shootThisFilmAgain() {
    let asset = asset
    let stock = asset.stock
    let id = asset.id
    Haptics.impact(.light)
    Task { @MainActor in
      // decode the persisted original + reading off-main; the replay needs
      // both — the original alone would re-read (drift), so require the pair
      let replay = await Task.detached(priority: .userInitiated) {
        () -> (UIImage, SceneReading)? in
        guard let original = asset.loadOriginalImage(),
              let reading = LibraryStore.loadReading(for: id) else { return nil }
        return (original, reading)
      }.value
      if let (original, reading) = replay {
        let key = UUID()
        // seed the Conductor with the persisted reading so the develop's
        // `reading(for:key:)` is a cache hit — no second subject pass
        Conductor.shared.adopt(reading, key: key)
        model.pendingDevelopImage = original
        model.pendingDevelopKey = key
      }
      model.pendingStock = stock
      model.selectedTab = .cameras
      dismiss()
    }
  }

  /// the kept object's next life: carry this frame to the Print Room —
  /// before this hand-off existed, only the newest frame (or a fresh
  /// Photos pick) could ever be printed
  private func printThisFrame() {
    model.pendingPrintAsset = asset
    model.selectedTab = .printRoom
    Haptics.impact(.light)
    dismiss()
  }

  /// The best frame available right now: the decoded full frame, the session
  /// asset's in-memory frame, a fresh bounded decode, or (only if the stored
  /// file is unreadable) the thumbnail.
  private func resolvedFrame() -> UIImage {
    fullImage ?? asset.image ?? asset.loadFullImage() ?? asset.thumbnail
  }

  /// the same designed frame DevelopView shares — composed off-main from the
  /// kept develop, its camera, and its first decision note. The Library keeps
  /// parity: any kept frame can leave the app in the identifiable format.
  private func shareCard() {
    guard !isComposingCard, shareItem == nil else { return }
    isComposingCard = true
    let asset = asset
    let resident = fullImage ?? asset.image
    Task { @MainActor in
      let card = await Task.detached(priority: .userInitiated) { () -> UIImage in
        let frame = resident ?? asset.loadFullImage() ?? asset.thumbnail
        return LightTestCard.single(
          photo: frame, stock: asset.stock, decision: asset.decisions.first)
      }.value
      Analytics.log(.photoShared)
      shareItem = ShareItem(image: card)
      isComposingCard = false
    }
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
        saveTick += 1
        Haptics.notify(.success)
      } catch {
        isSaving = false
        errorMessage = error.localizedDescription
      }
    }
  }
}
