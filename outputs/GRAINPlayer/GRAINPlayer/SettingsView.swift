import SwiftUI

// MARK: - 播放器全局设置面板

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var biometricService = BiometricLockService.shared

    @AppStorage("doubleTapSeekInterval") private var doubleTapSeekInterval: Int = 10
    @AppStorage("autoPictureInPicture") private var autoPiPEnabled: Bool = true
    @AppStorage("enableBackgroundAudio") private var backgroundAudioEnabled: Bool = true
    @AppStorage("requireBiometricForHiddenVault") private var isBiometricRequired: Bool = true

    public init() {}

    public var body: some View {
        NavigationView {
            ZStack {
                GrainTheme.black.ignoresSafeArea()

                List {
                    // 播放体验设置
                    Section(header: Text("播放设置").foregroundColor(GrainTheme.muted)) {
                        Toggle(isOn: $autoPiPEnabled) {
                            Label("自动开启画中画 (PiP)", systemImage: "pip.enter")
                                .foregroundColor(GrainTheme.paper)
                        }
                        .tint(GrainTheme.accent)
                        .listRowBackground(GrainTheme.surface)

                        Toggle(isOn: $backgroundAudioEnabled) {
                            Label("后台继续播放音频", systemImage: "waveform")
                                .foregroundColor(GrainTheme.paper)
                        }
                        .tint(GrainTheme.accent)
                        .listRowBackground(GrainTheme.surface)

                        Picker(selection: $doubleTapSeekInterval) {
                            Text("5 秒").tag(5)
                            Text("10 秒").tag(10)
                            Text("15 秒").tag(15)
                            Text("30 秒").tag(30)
                        } label: {
                            Label("双击快进/快退跨度", systemImage: "goforward")
                                .foregroundColor(GrainTheme.paper)
                        }
                        .listRowBackground(GrainTheme.surface)
                    }

                    // 隐私与生物识别设置
                    Section(header: Text("隐私与加密").foregroundColor(GrainTheme.muted)) {
                        Toggle(isOn: $isBiometricRequired) {
                            Label("访问隐藏相册与保险箱需 \(biometricService.biometricName)", systemImage: biometricService.biometricIcon)
                                .foregroundColor(GrainTheme.paper)
                        }
                        .tint(GrainTheme.accent)
                        .listRowBackground(GrainTheme.surface)

                        HStack {
                            Text("退入后台自动上锁")
                                .foregroundColor(GrainTheme.paper)
                            Spacer()
                            Text("始终开启")
                                .font(.subheadline)
                                .foregroundColor(GrainTheme.accent)
                        }
                        .listRowBackground(GrainTheme.surface)
                    }

                    // 文件传输指南
                    Section(header: Text("电脑文件导入指南").foregroundColor(GrainTheme.muted)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Mac 访达 / Windows iTunes 共享")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(GrainTheme.paper)

                            Text("用数据线连接电脑后，在 Mac「访达」或 Windows「iTunes」的「文件共享」中找到「GRAIN Player」，将任意视频（MP4/MOV/MKV 等）直接拖入，即可在 App「文件目录」中即刻播放。")
                                .font(.system(size: 12))
                                .foregroundColor(GrainTheme.muted)
                                .lineSpacing(3)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(GrainTheme.surface)
                    }

                    // 关于与设计说明
                    Section(header: Text("关于").foregroundColor(GrainTheme.muted)) {
                        HStack {
                            Text("应用版本")
                                .foregroundColor(GrainTheme.paper)
                            Spacer()
                            Text("1.0 (Build 1)")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(GrainTheme.muted)
                        }
                        .listRowBackground(GrainTheme.surface)

                        HStack {
                            Text("设计系统")
                                .foregroundColor(GrainTheme.paper)
                            Spacer()
                            Text("GRAIN 胶片暗调美学")
                                .foregroundColor(GrainTheme.accent)
                        }
                        .listRowBackground(GrainTheme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(GrainTheme.accent)
                }
            }
        }
    }
}
