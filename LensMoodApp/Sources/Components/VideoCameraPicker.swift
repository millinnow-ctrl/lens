import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct VideoCameraPicker: UIViewControllerRepresentable {
  let onCapture: (URL) -> Void
  @Environment(\.dismiss) private var dismiss

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let controller = UIImagePickerController()
    controller.sourceType = .camera
    controller.cameraCaptureMode = .video
    controller.mediaTypes = [UTType.movie.identifier]
    controller.videoMaximumDuration = 60
    controller.videoQuality = .typeHigh
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: VideoCameraPicker

    init(parent: VideoCameraPicker) {
      self.parent = parent
    }

    func imagePickerController(
      _ picker: UIImagePickerController,
      didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let url = info[.mediaURL] as? URL {
        parent.onCapture(url)
      }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }
  }
}
