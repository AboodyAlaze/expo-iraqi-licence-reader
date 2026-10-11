import ExpoModulesCore
import AVFoundation
import UIKit

public class ExpoIraqiLicenceReaderModule: Module {

  public func definition() -> ModuleDefinition {
    Name("ExpoIraqiLicenceReader")

    Function("hasCameraPermission") { () -> Bool in
      return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// يفتح الكاميرا على وجه الإجازة ويرجع JSON نصي
    AsyncFunction("scanFront") { (promise: Promise) in
      self.start(side: .front, promise: promise)
    }

    /// يفتح الكاميرا على ظهر الإجازة (جدول الفئات) ويرجع JSON نصي
    AsyncFunction("scanBack") { (promise: Promise) in
      self.start(side: .back, promise: promise)
    }
  }

  // MARK: - الصلاحية

  private func start(side: ScanSide, promise: Promise) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      DispatchQueue.main.async { self.present(side: side, promise: promise) }

    case .notDetermined:
      // نطلب الإذن أول، وإذا وافق نفتح الماسح
      AVCaptureDevice.requestAccess(for: .video) { granted in
        if granted {
          DispatchQueue.main.async { self.present(side: side, promise: promise) }
        } else {
          promise.reject("CAMERA_DENIED", "صلاحية الكاميرا مرفوضة")
        }
      }

    default:
      promise.reject("CAMERA_DENIED", "صلاحية الكاميرا مرفوضة")
    }
  }

  // MARK: - عرض الماسح

  private func present(side: ScanSide, promise: Promise) {
    guard let presenter = self.appContext?.utilities?.currentViewController() else {
      promise.reject("NO_ACTIVITY", "ما لكيت الواجهة")
      return
    }

    let vc = LicenceScannerViewController(side: side) { json in
      if let json = json {
        promise.resolve(json)
      } else {
        promise.reject("SCAN_CANCELLED", "تم إلغاء المسح")
      }
    }

    vc.modalPresentationStyle = .fullScreen
    presenter.present(vc, animated: true)
  }
}
