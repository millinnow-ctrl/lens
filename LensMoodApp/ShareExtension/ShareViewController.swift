import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Share-Sheet entry point (`NSExtensionPrincipalClass`): a thin UIKit
/// shell that pulls the shared photograph off the extension context and hosts
/// the SwiftUI develop surface. UIKit here, SwiftUI for everything visible.
final class ShareViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(Theme.paper)
    let host = UIHostingController(rootView: ShareDevelopView(
      loadPhoto: { [weak self] in await self?.loadSharedPhoto() },
      finish: { [weak self] in
        self?.extensionContext?.completeRequest(returningItems: nil)
      }
    ))
    addChild(host)
    host.view.frame = view.bounds
    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.view.backgroundColor = .clear
    view.addSubview(host.view)
    host.didMove(toParent: self)
  }

  /// First image attachment in the share payload, decoded and re-rendered to
  /// the extension's working frame (1500 px longest edge, orientation
  /// normalized) BEFORE anything else touches it — the ~120 MB extension
  /// memory ceiling is the budget every develop works inside.
  private func loadSharedPhoto() async -> UIImage? {
    let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
      .compactMap(\.attachments)
      .flatMap { $0 } ?? []
    guard let provider = providers.first(where: {
      $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
    }) else { return nil }

    let raw: UIImage? = await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
        // hosts hand images over as a file URL, a UIImage, or raw data
        if let url = item as? URL, let data = try? Data(contentsOf: url) {
          continuation.resume(returning: UIImage(data: data))
        } else if let image = item as? UIImage {
          continuation.resume(returning: image)
        } else if let data = item as? Data {
          continuation.resume(returning: UIImage(data: data))
        } else {
          continuation.resume(returning: nil)
        }
      }
    }
    guard let raw else { return nil }
    return await Task.detached(priority: .userInitiated) {
      Self.workingFrame(from: raw, maxEdge: 1500)
    }.value
  }

  /// Render into a fresh bitmap: normalizes EXIF orientation and caps the
  /// longest edge so both the preview and the saved develop are bounded.
  nonisolated static func workingFrame(from image: UIImage, maxEdge: CGFloat) -> UIImage {
    let pixelWidth = image.size.width * image.scale
    let pixelHeight = image.size.height * image.scale
    let largest = max(pixelWidth, pixelHeight)
    guard largest > 0 else { return image }
    let scale = min(1, maxEdge / largest)
    let size = CGSize(
      width: max(1, (pixelWidth * scale).rounded(.down)),
      height: max(1, (pixelHeight * scale).rounded(.down))
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: size))
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }
}
