import CoreLocation

/// 为相机拍摄提供最近一次定位，供 EXIF GPS 与相册资源位置使用。
/// 只有用户在设置里打开“位置信息”时才会启动。
final class CaptureLocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = CaptureLocationProvider()

    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var storedLocation: CLLocation?
    private var isStarted = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var latestLocation: CLLocation? {
        lock.lock()
        defer { lock.unlock() }
        return storedLocation
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// 只在启动页或设置里由用户主动触发时申请，避免使用过程中弹出系统弹窗
    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        default:
            break
        }
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        isStarted = true
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            // 未授权时保持静默：不申请、不弹窗，照片就不写位置
            break
        }
    }

    func stop() {
        isStarted = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isStarted else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            manager.stopUpdatingLocation()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        lock.lock()
        storedLocation = location
        lock.unlock()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 定位失败时保留上一次有效位置；没有就留空，照片不写入 GPS。
    }
}
