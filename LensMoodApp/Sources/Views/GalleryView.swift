import SwiftUI
import UIKit

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
            VStack(alignment: .leading, spacing: 14) {
              LazyVGrid(columns: columns, spacing: 14) {
                ForEach(model.library) { asset in
                  Button {
                    selected = asset
                  } label: {
                    Color.clear
                      .aspectRatio(0.8, contentMode: .fit)
                      .overlay {
                        Image(uiImage: asset.image)
                          .resizable()
                          .scaledToFill()
                      }
                      .overlay(alignment: .topTrailing) {
                        if asset.favorite {
                          Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.28), in: Circle())
                            .padding(6)
                        }
                      }
                      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                      .oceanCardShadow()
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("\(asset.stock.name)\(asset.favorite ? ", favorite" : "")")
                }
              }
            }
            .padding(Theme.pagePadding)
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

  private var emptyState: some View {
    VStack(spacing: 14) {
      Image(systemName: "rectangle.stack")
        .font(.system(size: 36, weight: .ultraLight))
      Text("No developed frames")
        .font(.system(size: 25, weight: .heavy))
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

private struct GalleryDetailView: View {
  let asset: DevelopedAsset

  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var sharePresented = false
  @State private var isSaving = false
  @State private var saveConfirmation = false
  @State private var errorMessage: String?

  /// live favorite state (the passed asset is a snapshot; the model is truth)
  private var isFavorite: Bool {
    model.library.first(where: { $0.id == asset.id })?.favorite ?? asset.favorite
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Image(uiImage: asset.image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .background(Theme.viewfinder)

          VStack(alignment: .leading, spacing: 6) {
            TechnicalLabel(text: asset.stock.exif)
            Text(asset.stock.name)
              .font(.system(size: 28, weight: .heavy))
            Text(asset.stock.tagline)
              .font(.system(size: 14))
              .foregroundStyle(Theme.inkSoft)
          }

          Button(isSaving ? "Saving to Photos" : "Save to Photos") {
            save()
          }
          .buttonStyle(InstrumentButtonStyle(kind: .primary))
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
      .sheet(isPresented: $sharePresented) {
        ActivitySheet(items: [asset.image])
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

  private func save() {
    isSaving = true
    Task { @MainActor in
      do {
        try await PhotoLibraryWriter.save(image: asset.image)
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
