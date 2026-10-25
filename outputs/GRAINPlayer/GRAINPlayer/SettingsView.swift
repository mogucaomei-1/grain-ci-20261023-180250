import SwiftUI

// MARK: - 播放器全局设置面板

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("doubleTapSeekInterval") private var doubleTapSeekInterval: Int = 10
    @AppStorage("autoPictureInPicture") private var autoPiPEnabled: Bool = true
    @AppStorage("enableBackgroundAudio") private var backgroundAudioEnabled: Bool = true
    @AppStorage("appTheme") private var appTheme: String = "system"

    public init() {}

    public var body: some View {
        NavigationView {
            ZStack {
                GrainTheme.black.ignoresSafeArea()

                List {
                    // 外观主题设置 (白天/黑夜/系统)
                    Section(header: Text("外观模式").foregroundColor(GrainTheme.muted)) {
                        Picker("外观模式", selection: $appTheme) {
                            Text("跟随系统").tag("system")
                            Text("白天模式").tag("light")
                            Text("黑夜模式").tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(GrainTheme.surface)
                    }

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

                    // 目录与相册说明
                    Section(header: Text("相册与目录说明").foregroundColor(GrainTheme.muted)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("支持播放「已隐藏」相册")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(GrainTheme.paper)

                            Text("在「相册目录」横滑栏中选择「已隐藏」，可直接浏览并播放系统已隐藏的所有视频，无需在系统相册中手动恢复。")
                                .font(.system(size: 12))
                                .foregroundColor(GrainTheme.muted)
                                .lineSpacing(3)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(GrainTheme.surface)
                    }

                    // 电脑文件导入指南
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
                            Text("1.0 (Build 5)")
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
