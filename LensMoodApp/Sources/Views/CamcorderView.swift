import AVKit
import CoreTransferable
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private struct ImportedMovie: Transferable {
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .movie) { received in
      let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("lensmood-input-\(UUID().uuidString).mov")
      try FileManager.default.copyItem(at: received.file, to: destination)
      return ImportedMovie(url: destination)
    }
  }
}

struct CamcorderView: View {
  @State private var pickerItem: PhotosPickerItem?
  @State private var inputURL: URL?
  @State private var outputURL: URL?
  @State private var cameraPresented = false
  @State private var isExporting = false
  @State private var errorMessage: String?
  @State private var saved = false
  @State private var cameraUnavailable = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          introduction
          tapeWindow

          if isExporting {
            exportState
          } else {
            controls
          }

          InstrumentPanel {
            VStack(alignment: .leading, spacing: 10) {
              TechnicalLabel(text: "Tape behavior")
              Text("One authored response: muted tube color, slow auto-gain breathing, crawling luminance grain, restrained vignette, and a counting timecode.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(4)
            }
            .padding(16)
          }
        }
        .padding(Theme.pagePadding)
      }
      .background(Theme.paper)
      .navigationTitle("Tape")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $cameraPresented) {
        VideoCameraPicker { url in
          inputURL = url
          developTape(url)
        }
        .ignoresSafeArea()
      }
      .onChange(of: pickerItem) { item in
        importMovie(item)
      }
      .alert("Tape saved", isPresented: $saved) {
        Button("OK", role: .cancel) {}
      }
      .alert("Tape could not be developed", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "Try another clip.")
      }
      .alert("Camera unavailable", isPresented: $cameraUnavailable) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("Recording is not available on this device. You can load an existing clip instead.")
      }
    }
  }

  private var introduction: some View {
    VStack(alignment: .leading, spacing: 7) {
      TechnicalLabel(text: "Tape 94")
      Text("One camera. One tape.")
        .font(.system(size: 33, weight: .bold, design: .serif))
        .foregroundStyle(Theme.ink)
      Text("There are no dials and no fake damage controls. Record a moment; the tape decides the rest.")
        .font(.system(size: 15))
        .foregroundStyle(Theme.inkSoft)
        .lineSpacing(4)
    }
  }

  private var tapeWindow: some View {
    ZStack {
      Rectangle()
        .fill(Theme.viewfinder)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)

      if let url = outputURL ?? inputURL {
        VideoPlayer(player: AVPlayer(url: url))
      } else {
        VStack(spacing: 12) {
          Image(systemName: "video.fill")
            .font(.system(size: 34, weight: .light))
          Text("NO TAPE")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1.6)
        }
        .foregroundStyle(Theme.viewfinderChrome)
      }
    }
    .overlay(alignment: .top) {
      HStack {
        HStack(spacing: 6) {
          Circle().fill(Theme.recRed).frame(width: 7, height: 7)
          Text("REC")
        }
        Spacer()
        Text("SP · AUTO")
      }
      .font(.system(size: 9, weight: .semibold, design: .monospaced))
      .foregroundStyle(Theme.viewfinderChrome)
      .padding(12)
    }
    .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
  }

  private var exportState: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        ProgressView().tint(Theme.accent)
        Text("Developing tape")
          .font(.system(size: 15, weight: .semibold))
      }
      Text("Color, grain, exposure breathing, and timecode are being rendered into every frame.")
        .font(.system(size: 13))
        .foregroundStyle(Theme.fog)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface)
    .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
  }

  private var controls: some View {
    VStack(spacing: 10) {
      Button {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
          cameraUnavailable = true
          return
        }
        cameraPresented = true
      } label: {
        Label("Record a tape", systemImage: "record.circle")
      }
      .buttonStyle(InstrumentButtonStyle(kind: .primary))

      PhotosPicker(selection: $pickerItem, matching: .videos) {
        Text("Load an existing clip")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(InstrumentButtonStyle(kind: .secondary))

      if outputURL != nil {
        Button("Save developed tape") {
          saveTape()
        }
        .buttonStyle(InstrumentButtonStyle(kind: .secondary))
      }
    }
  }

  private func importMovie(_ item: PhotosPickerItem?) {
    guard let item else { return }
    isExporting = true
    Task {
      do {
        guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
          throw VhsError.badInput("The selected clip could not be opened.")
        }
        inputURL = movie.url
        developTape(movie.url)
      } catch {
        isExporting = false
        errorMessage = error.localizedDescription
      }
    }
  }

  private func developTape(_ url: URL) {
    isExporting = true
    outputURL = nil
    Task {
      do {
        let developed = try await VhsExporter.export(videoURL: url)
        outputURL = developed
        isExporting = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch {
        isExporting = false
        errorMessage = error.localizedDescription
      }
    }
  }

  private func saveTape() {
    guard let outputURL else { return }
    PHPhotoLibrary.shared().performChanges {
      PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL)
    } completionHandler: { success, error in
      DispatchQueue.main.async {
        if success {
          saved = true
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
          errorMessage = error?.localizedDescription ?? "The tape could not be saved."
        }
      }
    }
  }
}
