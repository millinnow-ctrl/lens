import AVFoundation
import UIKit

/// The live camera behind the Red Ring viewfinder. Wraps an AVCaptureSession
/// and applies the manual DSLR controls (ISO, shutter, exposure bias) to the
/// real device where the hardware allows. On the Simulator / CI there is no
/// camera device, so `isAvailable` stays false, no session is ever built, and
/// `capture` substitutes the loaded camera's plate image — which lets the whole
/// shoot → develop → review flow run (and screenshot) without hardware.
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
  @Published private(set) var isAvailable = false
  @Published private(set) var authorization: AVAuthorizationStatus = .notDetermined
  @Published private(set) var isRunning = false
  @Published private(set) var isCapturing = false
  @Published var settings = CaptureSettings()
  @Published private(set) var limits = CaptureLimits()

  @Published private(set) var position: AVCaptureDevice.Position = .back

  let session = AVCaptureSession()
  private let photoOutput = AVCapturePhotoOutput()
  private var device: AVCaptureDevice?
  private let sessionQueue = DispatchQueue(label: "app.lensmood.camera.session")
  // nil result = a real hardware capture failed. Only the no-hardware path
  // (Simulator/CI) ever completes with the loaded camera's plate; on a device a
  // failure returns nil so the caller refunds instead of developing the plate.
  private var captureCompletion: ((UIImage?) -> Void)?

  // MARK: lifecycle

  func configure() {
    // already configured (returning to the tab): just resume the session
    guard device == nil else {
      start()
      return
    }
    // No camera hardware at all (Simulator / CI / iPod-style device): never
    // raise the permission prompt — just fall back to the plate viewfinder.
    guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
      isAvailable = false
      return
    }
    authorization = AVCaptureDevice.authorizationStatus(for: .video)
    switch authorization {
    case .authorized:
      buildSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        Task { @MainActor in
          self?.authorization = granted ? .authorized : .denied
          if granted { self?.buildSession() }
        }
      }
    default:
      isAvailable = false
    }
  }

  private func buildSession() {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      guard let camera = AVCaptureDevice.default(
        .builtInWideAngleCamera, for: .video, position: .back
      ) else {
        Task { @MainActor in self.isAvailable = false }   // Simulator / no hardware
        return
      }
      self.session.beginConfiguration()
      self.session.sessionPreset = .photo
      if let input = try? AVCaptureDeviceInput(device: camera), self.session.canAddInput(input) {
        self.session.addInput(input)
      }
      if self.session.canAddOutput(self.photoOutput) {
        self.session.addOutput(self.photoOutput)
      }
      if let connection = self.photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
        connection.videoOrientation = .portrait
      }
      self.session.commitConfiguration()
      self.device = camera

      let format = camera.activeFormat
      let minISO = Double(format.minISO), maxISO = Double(format.maxISO)
      let minDur = CMTimeGetSeconds(format.minExposureDuration)
      let maxDur = CMTimeGetSeconds(format.maxExposureDuration)
      let minBias = Double(camera.minExposureTargetBias)
      let maxBias = Double(camera.maxExposureTargetBias)
      let maxZoom = Double(min(camera.maxAvailableVideoZoomFactor, 8))

      Task { @MainActor in
        self.limits.minISO = minISO; self.limits.maxISO = maxISO
        self.limits.minShutter = minDur; self.limits.maxShutter = maxDur
        self.limits.minBias = minBias; self.limits.maxBias = maxBias
        self.limits.maxZoom = maxZoom
        self.isAvailable = true
        self.start()
      }
    }
  }

  func start() {
    guard isAvailable else { return }
    sessionQueue.async { [weak self] in
      guard let self, !self.session.isRunning else { return }
      self.session.startRunning()
      Task { @MainActor in self.isRunning = true }
    }
  }

  func stop() {
    sessionQueue.async { [weak self] in
      guard let self, self.session.isRunning else { return }
      self.session.stopRunning()
      Task { @MainActor in self.isRunning = false }
    }
  }

  // MARK: dials → hardware

  /// seed the dials to a camera personality's rated EXIF home
  func load(stock: Stock) {
    let home = CaptureSettings.home(for: stock)
    var next = home
    next.mode = settings.mode
    next.captureMode = settings.captureMode
    next.autoRelight = settings.autoRelight
    next.zoom = settings.zoom
    next.manualFocus = settings.manualFocus
    settings = next
    applyManualExposure()
  }

  /// push the current manual exposure to the device where supported
  func applyManualExposure() {
    guard isAvailable else { return }
    let s = settings
    let lim = limits
    sessionQueue.async { [weak self] in
      guard let self, let device = self.device else { return }
      guard (try? device.lockForConfiguration()) != nil else { return }
      var realizedEV = 0.0
      if s.mode == .manual {
        let iso = Float(min(lim.maxISO, max(lim.minISO, s.iso)))
        let dur = CMTime(
          seconds: min(lim.maxShutter, max(lim.minShutter, s.shutter)),
          preferredTimescale: 1_000_000
        )
        if device.isExposureModeSupported(.custom) {
          device.setExposureModeCustom(duration: dur, iso: iso, completionHandler: nil)
        }
      } else if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
        let bias = Float(min(lim.maxBias, max(lim.minBias, s.exposureBiasEV)))
        device.setExposureTargetBias(bias, completionHandler: nil)
        realizedEV = Double(bias)
      }
      device.unlockForConfiguration()
      Task { @MainActor in self.settings.hardwareAppliedEV = realizedEV }
    }
  }

  func applyZoom(_ factor: Double) {
    settings.zoom = factor
    guard isAvailable else { return }
    sessionQueue.async { [weak self] in
      guard let self, let device = self.device else { return }
      guard (try? device.lockForConfiguration()) != nil else { return }
      device.videoZoomFactor = max(1, min(device.maxAvailableVideoZoomFactor, CGFloat(factor)))
      device.unlockForConfiguration()
    }
  }

  func flip() {
    let next: AVCaptureDevice.Position = position == .back ? .front : .back
    position = next
    guard isAvailable else { return }
    sessionQueue.async { [weak self] in
      guard let self,
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: next),
            let input = try? AVCaptureDeviceInput(device: camera) else { return }
      self.session.beginConfiguration()
      for existing in self.session.inputs { self.session.removeInput(existing) }
      if self.session.canAddInput(input) { self.session.addInput(input) }
      self.session.commitConfiguration()
      self.device = camera
    }
  }

  /// `point` is the tap in normalized view space (top-left origin) — the
  /// engine's depth-of-field plane keeps that space. `devicePoint` is the
  /// same tap converted by the preview layer into AVFoundation's
  /// point-of-interest space (unrotated-sensor coordinates); only that
  /// converted point may ever reach the hardware.
  func focus(at point: CGPoint, devicePoint: CGPoint?) {
    settings.focusPoint = point
    // MF: the tap places the focal plane for the developer's depth of field
    // only — the lens stays where the photographer left it
    guard isAvailable, !settings.manualFocus, let poi = devicePoint else { return }
    sessionQueue.async { [weak self] in
      guard let self, let device = self.device else { return }
      guard (try? device.lockForConfiguration()) != nil else { return }
      if device.isFocusPointOfInterestSupported {
        device.focusPointOfInterest = poi
        if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
      }
      if device.isExposurePointOfInterestSupported {
        device.exposurePointOfInterest = poi
      }
      device.unlockForConfiguration()
    }
  }

  // MARK: shutter

  /// `fallback` is the loaded camera's plate, used ONLY when there is no
  /// hardware (Simulator/CI). On a device, a failed capture completes with nil.
  func capture(fallback: UIImage?, completion: @escaping (UIImage?) -> Void) {
    isCapturing = true
    guard isAvailable else {
      // Simulator / CI: hand back the plate so develop + review still run —
      // honoring zoom and facing, so those controls change the shot too
      isCapturing = false
      let plate = fallback ?? Self.solidPlaceholder()
      completion(Self.fallbackFrame(from: plate, zoom: settings.zoom, mirrored: position == .front))
      return
    }
    captureCompletion = completion
    let photoSettings = AVCapturePhotoSettings()
    photoSettings.flashMode = settings.flashMode == .on ? .on
      : (settings.flashMode == .auto ? .auto : .off)
    sessionQueue.async { [weak self] in
      guard let self else { return }
      self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    let image: UIImage? = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
    Task { @MainActor in
      self.isCapturing = false
      // a real failure (error, or no decodable data) returns nil — the caller
      // refunds the exposure and shows an error rather than substituting the
      // loaded camera's plate as if it were the user's photograph
      self.captureCompletion?(image)
      self.captureCompletion = nil
    }
  }

  /// What the "sensor" hands back when there is no hardware: the test plate
  /// center-cropped by the zoom factor and mirrored for the front camera, so
  /// every control produces a genuinely different photograph.
  static func fallbackFrame(from image: UIImage, zoom: Double, mirrored: Bool) -> UIImage {
    var cg = image.cgImage
    if zoom > 1.01, let base = cg {
      let z = CGFloat(zoom)
      let width = CGFloat(base.width), height = CGFloat(base.height)
      let crop = CGRect(
        x: (width - width / z) / 2, y: (height - height / z) / 2,
        width: width / z, height: height / z
      )
      cg = base.cropping(to: crop) ?? base
    }
    guard let final = cg else { return image }
    return UIImage(cgImage: final, scale: image.scale, orientation: mirrored ? .upMirrored : image.imageOrientation)
  }

  private static func solidPlaceholder() -> UIImage {
    let size = CGSize(width: 1200, height: 1600)
    return UIGraphicsImageRenderer(size: size).image { ctx in
      UIColor(red: 0.16, green: 0.19, blue: 0.24, alpha: 1).setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
    }
  }
}
