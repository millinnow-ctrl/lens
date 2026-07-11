import Photos
import UIKit

enum PhotoLibraryError: LocalizedError {
  case permissionDenied
  case writeFailed

  var errorDescription: String? {
    switch self {
    case .permissionDenied:
      return "LensMood needs permission to add this work to Photos. You can change access in Settings."
    case .writeFailed:
      return "Photos did not confirm the save. Please try again."
    }
  }
}

enum PhotoLibraryWriter {
  static func save(image: UIImage) async throws {
    try await ensureAddPermission()
    try await withCheckedThrowingContinuation { continuation in
      PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAsset(from: image)
      } completionHandler: { success, error in
        if success {
          continuation.resume()
        } else {
          continuation.resume(throwing: error ?? PhotoLibraryError.writeFailed)
        }
      }
    }
  }

  static func save(videoAt url: URL) async throws {
    try await ensureAddPermission()
    try await withCheckedThrowingContinuation { continuation in
      PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
      } completionHandler: { success, error in
        if success {
          continuation.resume()
        } else {
          continuation.resume(throwing: error ?? PhotoLibraryError.writeFailed)
        }
      }
    }
  }

  private static func ensureAddPermission() async throws {
    let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    let status: PHAuthorizationStatus
    if current == .notDetermined {
      status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    } else {
      status = current
    }

    guard status == .authorized || status == .limited else {
      throw PhotoLibraryError.permissionDenied
    }
  }
}
