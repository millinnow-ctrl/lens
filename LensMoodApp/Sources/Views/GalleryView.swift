import SwiftUI
import UIKit

struct GalleryView: View {
  @EnvironmentObject private var model: AppModel
  @State private var selected: DevelopedAsset?

  private let columns = [
    GridItem(.flexible(), spacing: 3),
    GridItem(.flexible(), spacing: 3),
    GridItem(.flexible(), spacing: 3),
  ]

  var body: some View {
    NavigationStack {
      Group {
        if model.library.isEmpty {
          emptyState
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 14) {
              HStack {
                TechnicalLabel(text: "Session contact sheet")
                Spacer()
                Text("\(model.library.count) frames")
                  .font(.system(size: 10, design: .monospaced))
                  .foregroundStyle(Theme.fog)
              }

              LazyVGrid(columns: columns, spacing: 3) {
                ForEach(Array(model.library.enumerated()), id: \.element.id) { index, asset in
                  Button {
                    selected = asset
                  } label: {
                    VStack(alignment: .leading, spacing: 5) {
                      Image(uiImage: asset.image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(0.8, contentMode: .fill)
                        .clipped()
                      HStack {
                        Text(String(format: "%02d", model.library.count - index))
                        Spacer()
                        Text(asset.stock.name.uppercased())
                          .lineLimit(1)
                      }
                      .font(.system(size: 8, weight: .medium, design: .monospaced))
                      .foregroundStyle(Theme.viewfinderChrome)
                    }
                  }
                  .buttonStyle(.plain)
                }
              }
            }
            .padding(12)
            .background(Theme.viewfinder)
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
        .font(.system(size: 25, weight: .bold, design: .serif))
      Text("Photographs developed in this session appear here as a contact sheet.")
        .font(.system(size: 14))
        .foregroundStyle(Theme.inkSoft)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 38)
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
              .font(.system(size: 28, weight: .bold, design: .serif))
            Text(asset.stock.tagline)
              .font(.system(size: 14))
              .foregroundStyle(Theme.inkSoft)
          }

          Button("Save to Photos") {
            UIImageWriteToSavedPhotosAlbum(asset.image, nil, nil, nil)
          }
          .buttonStyle(InstrumentButtonStyle(kind: .primary))

          Button("Share") {
            sharePresented = true
          }
          .buttonStyle(InstrumentButtonStyle(kind: .secondary))

          Button(role: .destructive) {
            model.remove(asset)
            dismiss()
          } label: {
            Text("Remove from this session")
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
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $sharePresented) {
        ActivitySheet(items: [asset.image])
      }
    }
  }
}
