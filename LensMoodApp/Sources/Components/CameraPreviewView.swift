import AVFoundation
import SwiftUI
import UIKit

/// The live viewfinder feed. On a real device it shows the AVCaptureSession via
/// an AVCaptureVideoPreviewLayer. When there is no camera (Simulator / CI /
/// permission denied) it shows the loaded camera's signature plate, letterboxed,
/// so the whole pro-camera chrome still reads as a photographic frame.
struct CameraPreviewView: UIViewRepresentable {
  let session: AVCaptureSession
  let isAvailable: Bool
  let placeholder: UIImage?

  func makeUIView(context: Context) -> PreviewUIView {
    let view = PreviewUIView()
    view.previewLayer.session = session
    view.previewLayer.videoGravity = .resizeAspectFill
    return view
  }

  func updateUIView(_ view: PreviewUIView, context: Context) {
    view.previewLayer.isHidden = !isAvailable
    view.setPlaceholder(isAvailable ? nil : placeholder)
  }

  final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    // swiftlint:disable:next force_cast
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    private let plate = UIImageView()

    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = UIColor(red: 0.078, green: 0.102, blue: 0.122, alpha: 1)
      plate.contentMode = .scaleAspectFill
      plate.clipsToBounds = true
      plate.translatesAutoresizingMaskIntoConstraints = false
      addSubview(plate)
      NSLayoutConstraint.activate([
        plate.leadingAnchor.constraint(equalTo: leadingAnchor),
        plate.trailingAnchor.constraint(equalTo: trailingAnchor),
        plate.topAnchor.constraint(equalTo: topAnchor),
        plate.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPlaceholder(_ image: UIImage?) {
      plate.image = image
      plate.isHidden = image == nil
    }
  }
}
