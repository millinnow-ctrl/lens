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
  @State private var isSaving = false

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

        }
        .padding(Theme.pagePadding)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Theme.paper)
      .navigationTitle("Tape")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $cameraPresented) {
        VideoCameraPicker { url in
          adopt(input: url)
        }
        .ignoresSafeArea()
      }
      .onChange(of: pickerItem) { item in
        importMovie(item)
      }
      .onAppear { sweepOrphanedTapes() }
      .savedTick(isPresented: $saved, text: "Tape saved to Photos")
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
    Text("One camera. One tape.")
      .scaledFont(size: 33, weight: .heavy, relativeTo: .largeTitle)
      .foregroundStyle(Theme.ink)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
  }

  private var tapeWindow: some View {
    ZStack {
      Rectangle()
        .fill(Theme.viewfinder)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)

      if let url = outputURL ?? inputURL {
        VideoPlayer(player: AVPlayer(url: url))
      } else if let cover = BundleMedia.image("tape-idle") ?? BundleMedia.image("camcorder-cover") {
        // idle deck: a purpose-made 3:4 camcorder frame fills the window
        // (falls back to the 16:9 cover if the portrait asset is missing)
        Image(uiImage: cover)
          .resizable()
          .scaledToFill()
          .overlay(
            LinearGradient(
              colors: [.black.opacity(0.20), .clear, .black.opacity(0.45)],
              startPoint: .top, endPoint: .bottom
            )
          )
          .allowsHitTesting(false)
      } else {
        Image(systemName: "video.fill")
          .scaledFont(size: 34, weight: .light, relativeTo: .largeTitle)
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
      .scaledFont(size: 9, weight: .semibold, design: .monospaced, relativeTo: .caption2)
      // one tight chrome strip over the tape window: shrink, never wrap
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .foregroundStyle(Theme.viewfinderChrome)
      .padding(12)
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    .oceanCardShadow(deep: true)
  }

  private var exportState: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        ProgressView().tint(Theme.accent)
        Text("Developing tape")
          .font(.subheadline.weight(.semibold))   // 15pt at the default size
      }
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
        Label("Load an existing clip", systemImage: "video.badge.plus")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(InstrumentButtonStyle(kind: .secondary))

      if outputURL != nil {
        Button {
          saveTape()
        } label: {
          Label(isSaving ? "Saving developed tape" : "Save developed tape",
                systemImage: "square.and.arrow.down")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(InstrumentButtonStyle(kind: .secondary))
        .disabled(isSaving)
      }
    }
  }

  private func importMovie(_ item: PhotosPickerItem?) {
    guard let item else { return }
    isExporting = true
    Task { @MainActor in
      do {
        guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
          throw VhsError.badInput("The selected clip could not be opened.")
        }
        adopt(input: movie.url)
      } catch {
        isExporting = false
        errorMessage = error.localizedDescription
      }
    }
  }

  /// a new clip replaces the working pair — discard the old temp files first
  private func adopt(input url: URL) {
    discardTemp(inputURL)
    discardTemp(outputURL)
    inputURL = url
    developTape(url)
  }

  /// remove one of our own temporary tape files (never touches user files)
  private func discardTemp(_ url: URL?) {
    guard let url, url.lastPathComponent.hasPrefix("lensmood-") else { return }
    try? FileManager.default.removeItem(at: url)
  }

  /// clear temp tapes left behind by earlier sessions (they otherwise
  /// accumulate for the app's lifetime)
  private func sweepOrphanedTapes() {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory
    let keep = Set([inputURL, outputURL].compactMap { $0?.lastPathComponent })
    guard let names = try? fm.contentsOfDirectory(atPath: tmp.path) else { return }
    for name in names
    where (name.hasPrefix("lensmood-input-") || name.hasPrefix("lensmood-tape-")) && !keep.contains(name) {
      try? fm.removeItem(at: tmp.appendingPathComponent(name))
    }
  }

  private func developTape(_ url: URL) {
    isExporting = true
    discardTemp(outputURL)
    outputURL = nil
    Task { @MainActor in
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
    isSaving = true
    Task { @MainActor in
      do {
        try await PhotoLibraryWriter.save(videoAt: outputURL)
        isSaving = false
        saved = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch {
        isSaving = false
        errorMessage = error.localizedDescription
      }
    }
  }
}
