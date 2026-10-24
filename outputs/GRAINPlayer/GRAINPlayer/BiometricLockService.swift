import Combine
import LocalAuthentication
import SwiftUI

// MARK: - 生物识别与隐私加密解锁服务 (Face ID / Touch ID / 设备密码)

@MainActor
public final class BiometricLockService: ObservableObject {
    public static let shared = BiometricLockService()

    @Published public private(set) var isUnlocked: Bool = false
    @Published public private(set) var isAuthenticating: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    @AppStorage("requireBiometricForHiddenVault") public var isBiometricRequired: Bool = true

    private var cancellables = Set<AnyCancellable>()

    public init() {
        // 监听进入后台通知，自动重新上锁以保证隐私绝对安全
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.lock()
                }
            }
            .store(in: &cancellables)
    }

    /// 当前设备支持的生物识别名称
    public var biometricName: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "设备密码"
        }
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        @unknown default:
            return "生物识别"
        }
    }

    public var biometricIcon: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        @unknown default:
            return "lock.shield"
        }
    }

    /// 发起生物识别解锁
    public func unlock(reason: String = "验证身份以访问相册隐藏视频与私密保险箱") async -> Bool {
        guard isBiometricRequired else {
            isUnlocked = true
            return true
        }

        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "取消"

        var authError: NSError?
        // 优先使用生物识别，若不可用或被拒绝则允许设备密码兜底
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)
            ? .deviceOwnerAuthenticationWithBiometrics
            : .deviceOwnerAuthentication

        do {
            let success = try await context.evaluatePolicy(policy, localizedReason: reason)
            if success {
                isUnlocked = true
                errorMessage = nil
                GrainHaptics.success()
                return true
            } else {
                isUnlocked = false
                GrainHaptics.error()
                return false
            }
        } catch let err as LAError {
            if err.code != .userCancel && err.code != .systemCancel {
                // 如果生物识别失败或取消，尝试密码兜底
                if policy == .deviceOwnerAuthenticationWithBiometrics {
                    return await unlockWithPasscode(context: LAContext(), reason: reason)
                }
                errorMessage = err.localizedDescription
            }
            isUnlocked = false
            GrainHaptics.error()
            return false
        } catch {
            errorMessage = error.localizedDescription
            isUnlocked = false
            GrainHaptics.error()
            return false
        }
    }

    private func unlockWithPasscode(context: LAContext, reason: String) async -> Bool {
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if success {
                isUnlocked = true
                errorMessage = nil
                GrainHaptics.success()
                return true
            }
        } catch {
            isUnlocked = false
        }
        return false
    }

    /// 立即上锁
    public func lock() {
        isUnlocked = false
        errorMessage = nil
    }
}
