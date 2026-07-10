// Develop — pick a photo, it develops through the chosen stock.
// Stage 1: native photo picking + display. Stage 2 wires FilmEngine
// (Core Image / Metal) so the picked photo develops through the real look.

import SwiftUI
import PhotosUI

struct DevelopView: View {
  let stock: Stock
  @State private var pickedItem: PhotosPickerItem?
  @State private var pickedImage: Image?

  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        stage
        PhotosPicker(selection: $pickedItem, matching: .images) {
          Text(pickedImage == nil ? "Pick a photo" : "New photo")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
        }
        Text("It develops right here on your phone. Nothing gets uploaded.")
          .font(.system(size: 13))
          .foregroundStyle(Theme.fog)
      }
      .padding(16)
    }
    .background(Theme.paper)
    .navigationTitle(stock.name)
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: pickedItem) { _, item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self),
           let ui = UIImage(data: data) {
          pickedImage = Image(uiImage: ui)
        }
      }
    }
  }

  private var stage: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 20)
        .fill(Theme.viewfinder)
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
      if let pickedImage {
        pickedImage
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: 20))
      } else {
        VStack(spacing: 8) {
          Text("Load a photo")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
          Text("Develops through \(stock.name) — the film engine lands in Stage 2.")
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
      }
    }
  }
}
