import AVFoundation
import Photos
import SwiftUI
import UIKit

private enum PermissionStepState {
    case idle
    case requesting
    case granted
    case denied
}

struct PermissionOnboardingView: View {
    let onComplete: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("networkPermissionReady") private var networkPermissionReady = false
    @State private var networkState: PermissionStepState = .idle
    @State private var cameraState: PermissionStepState = .idle
    @State private var microphoneState: PermissionStepState = .idle
    @State private var photoState: PermissionStepState = .idle
    @State private var isCheckingNetwork = false

    var body: some View {
        ZStack {
            GrainBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        AnimatedEditorMark(size: 72)
                        Text("GRAIN")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .tracking(4)
                            .foregroundStyle(GrainTheme.paper)
                        Text("开始前请分别开启需要使用的系统权限")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }

                    VStack(spacing: 10) {
                        permissionRow(
                            icon: "wifi",
                            title: "网络",
                            detail: "从 iCloud 获取原始照片",
                            state: networkState,
                            deniedTitle: "重试",
                            action: requestNetwork
                        )
                        permissionRow(
                            icon: "camera.fill",
                            title: "相机",
                            detail: "拍摄照片和实况照片",
                            state: cameraState,
                            action: requestCamera
                        )
                        permissionRow(
                            icon: "mic.fill",
                            title: "麦克风",
                            detail: "拍摄实况照片需要录制声音",
                            state: microphoneState,
                            action: requestMicrophone
                        )
                        permissionRow(
                            icon: "photo.on.rectangle.angled",
                            title: "照片图库",
                            detail: "读取和保存照片",
                            state: photoState,
                            action: requestPhotos
                        )
                    }

                    Button {
                        onComplete()
                    } label: {
                        Text("进入 GRAIN")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(canContinue ? GrainTheme.black : GrainTheme.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                canContinue ? GrainTheme.paper : GrainTheme.raised,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canContinue)

                    Text("权限状态由 iOS 管理，可随时在系统设置中修改。")
                        .font(.system(size: 8.5, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 22)
                .padding(.top, 34)
                .padding(.bottom, 28)
            }
        }
        .task {
            refreshExistingPermissions()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshExistingPermissions()
                if networkState == .requesting, !isCheckingNetwork {
                    Task { await probeNetwork() }
                }
            }
        }
    }

    private var canContinue: Bool {
        networkPermissionReady
            && cameraState == .granted
            && microphoneState == .granted
            && photoState == .granted
    }

    private func permissionRow(
        icon: String,
        title: String,
        detail: String,
        state: PermissionStepState,
        deniedTitle: String = "去设置",
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(GrainTheme.accent)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
                Text(detail)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(GrainTheme.muted)
            }

            Spacer()

            Button(action: action) {
                Group {
                    switch state {
                    case .idle:
                        Text("开启")
                    case .requesting:
                        ProgressView().controlSize(.mini)
                    case .granted:
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                            Text("已开启")
                        }
                    case .denied:
                        Text(deniedTitle)
                    }
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(state == .granted ? GrainTheme.accent : GrainTheme.paper)
                .frame(width: 72, height: 32)
                .background(
                    state == .granted
                        ? GrainTheme.accent.opacity(0.14)
                        : GrainTheme.raised,
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(state == .requesting || state == .granted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(GrainTheme.line, lineWidth: 0.8)
        }
    }

    private func refreshExistingPermissions() {
        if networkPermissionReady {
            networkState = .granted
        } else if networkState != .requesting {
            networkState = .idle
        }
        cameraState = status(for: AVCaptureDevice.authorizationStatus(for: .video))
        microphoneState = status(for: AVCaptureDevice.authorizationStatus(for: .audio))
        photoState = photoPermissionGranted(
            PHPhotoLibrary.authorizationStatus(for: .readWrite)
        ) ? .granted : .idle
    }

    private func requestNetwork() {
        Task { await probeNetwork() }
    }

    private func probeNetwork() async {
        guard !isCheckingNetwork, networkState != .granted else { return }
        isCheckingNetwork = true
        networkState = .requesting
        defer { isCheckingNetwork = false }

        var connected = false
        for attempt in 0..<3 {
            var request = URLRequest(
                url: URL(string: "https://captive.apple.com/hotspot-detect.html")!
            )
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = attempt == 0 ? 10 : 6
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let status = (response as? HTTPURLResponse)?.statusCode,
                   (200...399).contains(status) {
                    connected = true
                    break
                }
            } catch {
                // The first request can be interrupted while iOS presents its
                // connectivity prompt. Retry after returning to the screen.
            }
            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
        networkPermissionReady = connected
        networkState = connected ? .granted : .denied
    }

    private func requestCamera() {
        guard cameraState != .granted else { return }
        if cameraState == .denied {
            openSystemSettings()
            return
        }
        cameraState = .requesting
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                cameraState = granted ? .granted : .denied
            }
        }
    }

    private func requestMicrophone() {
        guard microphoneState != .granted else { return }
        if microphoneState == .denied {
            openSystemSettings()
            return
        }
        microphoneState = .requesting
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                microphoneState = granted ? .granted : .denied
            }
        }
    }

    private func requestPhotos() {
        guard photoState != .granted else { return }
        if photoState == .denied {
            openSystemSettings()
            return
        }
        photoState = .requesting
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                photoState = photoPermissionGranted(status) ? .granted : .denied
            }
        }
    }

    private func status(for value: AVAuthorizationStatus) -> PermissionStepState {
        switch value {
        case .authorized:
            return .granted
        case .notDetermined:
            return .idle
        default:
            return .denied
        }
    }

    private func photoPermissionGranted(_ status: PHAuthorizationStatus) -> Bool {
        status == .authorized || status == .limited
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
