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

  let session = AVCaptureSession()
  private let photoOutput = AVCapturePhotoOutput()
  private var device: AVCaptureDevice?
  private let sessionQueue = DispatchQueue(label: "app.lensmood.camera.session")
  private var captureCompletion: ((UIImage) -> Void)?
  private var fallbackImage: UIImage?

  // MARK: lifecycle

  func configure() {
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

  func focus(at point: CGPoint) {
    settings.focusPoint = point
    guard isAvailable else { return }
    sessionQueue.async { [weak self] in
      guard let self, let device = self.device else { return }
      guard (try? device.lockForConfiguration()) != nil else { return }
      let poi = CGPoint(x: point.x, y: point.y)
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

  /// `fallback` is the loaded camera's plate, used when there is no hardware
  func capture(fallback: UIImage?, completion: @escaping (UIImage) -> Void) {
    isCapturing = true
    guard isAvailable else {
      // Simulator / CI: hand back the plate so develop + review still run
      isCapturing = false
      completion(fallback ?? Self.solidPlaceholder())
      return
    }
    captureCompletion = completion
    fallbackImage = fallback
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
      let result = image ?? self.fallbackImage ?? Self.solidPlaceholder()
      self.captureCompletion?(result)
      self.captureCompletion = nil
    }
  }

  private static func solidPlaceholder() -> UIImage {
    let size = CGSize(width: 1200, height: 1600)
    return UIGraphicsImageRenderer(size: size).image { ctx in
      UIColor(red: 0.16, green: 0.19, blue: 0.24, alpha: 1).setFill()
      ctx.fill(CGRect(origin: .zero, size: size))
    }
  }
}
