import SwiftUI
import UIKit

struct CaptureView: View {
  @EnvironmentObject private var model: AppModel
  @State private var stock = Stock.all[0]
  @State private var captured: UIImage?
  @State private var developed: UIImage?
  @State private var decisions: [String] = []
  @State private var cameraPresented = false
  @State private var isDeveloping = false
  @State private var isSaving = false
  @State private var cameraUnavailable = false
  @State private var saveConfirmation = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 7) {
            TechnicalLabel(text: "In-app camera")
            Text("Make the frame here.")
              .font(.system(size: 32, weight: .bold, design: .serif))
              .foregroundStyle(Theme.ink)
            Text("Choose the camera personality before the shutter. LensMood develops the photograph immediately after capture.")
              .font(.system(size: 15))
              .foregroundStyle(Theme.inkSoft)
              .lineSpacing(4)
          }

          cameraChooser
          viewfinder

          Button {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
              cameraUnavailable = true
              return
            }
            cameraPresented = true
          } label: {
            Label("Open camera", systemImage: "camera.fill")
          }
          .buttonStyle(InstrumentButtonStyle(kind: .primary))

          if developed != nil {
            Button(isSaving ? "Preparing full resolution" : "Save developed photograph") {
              save()
            }
            .buttonStyle(InstrumentButtonStyle(kind: .secondary))
            .disabled(isSaving)
          }

          if !decisions.isEmpty {
            InstrumentPanel {
              VStack(alignment: .leading, spacing: 10) {
                TechnicalLabel(text: "Camera decisions")
                ForEach(decisions, id: \.self) { decision in
                  Text(decision)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
                }
              }
              .padding(16)
            }
          }
        }
        .padding(Theme.pagePadding)
        .padding(.bottom, 72)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Theme.paper)
      .navigationTitle("Capture")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $cameraPresented) {
        StillCameraPicker { image in
          captured = image
          develop(image)
        }
        .ignoresSafeArea()
      }
      .alert("Camera unavailable", isPresented: $cameraUnavailable) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("Camera capture is not available on this device. Choose a photograph from any camera’s Develop screen instead.")
      }
      .alert("Saved to Photos", isPresented: $saveConfirmation) {
        Button("OK", role: .cancel) {}
      }
      .alert("Could not complete that action", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "Please try again.")
      }
    }
  }

  private var cameraChooser: some View {
    VStack(alignment: .leading, spacing: 8) {
      TechnicalLabel(text: "Loaded camera")
      Picker("Camera personality", selection: $stock) {
        ForEach(Stock.all) { camera in
          Text(camera.name).tag(camera)
        }
      }
      .pickerStyle(.menu)
      .tint(Theme.ink)
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .padding(.horizontal, 12)
      .background(Theme.surface)
      .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
    }
  }

  private var viewfinder: some View {
    ZStack {
      Rectangle()
        .fill(Theme.viewfinder)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)

      if let image = developed ?? captured {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else {
        VStack(spacing: 10) {
          Image(systemName: "viewfinder")
            .font(.system(size: 36, weight: .ultraLight))
          Text("The viewfinder opens with the system camera.")
            .font(.system(size: 13))
        }
        .foregroundStyle(Theme.viewfinderChrome)
      }

      if isDeveloping {
        Rectangle().fill(Theme.paper.opacity(0.92))
        VStack(spacing: 10) {
          ProgressView().tint(Theme.accent)
          Text("DEVELOPING")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.2)
        }
        .foregroundStyle(Theme.ink)
      }
    }
    .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
  }

  private func develop(_ image: UIImage) {
    isDeveloping = true
    developed = nil
    let selected = stock
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result {
        try FilmEngine.shared.develop(
          image,
          with: selected.recipe,
          maxPixelSize: 2048,
          seed: 43
        )
      }
      DispatchQueue.main.async {
        isDeveloping = false
        switch result {
        case .success(let render):
          developed = render.image
          decisions = render.decisions
          model.add(DevelopedAsset(
            image: render.image,
            source: image,
            stock: selected,
            decisions: render.decisions
          ))
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .failure(let error):
          errorMessage = error.localizedDescription
        }
      }
    }
  }

  private func save() {
    guard let captured else { return }
    isSaving = true
    let selected = stock
    DispatchQueue.global(qos: .userInitiated).async {
      let result = Result {
        try FilmEngine.shared.develop(captured, with: selected.recipe, maxPixelSize: 8192, seed: 43).image
      }
      DispatchQueue.main.async {
        switch result {
        case .success(let fullResolution):
          Task {
            do {
              try await PhotoLibraryWriter.save(image: fullResolution)
              isSaving = false
              saveConfirmation = true
              UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
              isSaving = false
              errorMessage = error.localizedDescription
            }
          }
        case .failure(let error):
          isSaving = false
          errorMessage = error.localizedDescription
        }
      }
    }
  }
}
