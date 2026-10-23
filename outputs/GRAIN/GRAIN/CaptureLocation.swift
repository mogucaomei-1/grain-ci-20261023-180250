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

    func start() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        isStarted = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
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
