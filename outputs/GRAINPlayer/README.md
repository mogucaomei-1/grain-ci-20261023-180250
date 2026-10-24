# GRAIN Player 1.0 — 纯视频播放器

GRAIN Player 延续了 GRAIN 项目的极简暗调胶片美学与专业工作台交互设计，是一个面向 iOS 的高性能纯视频播放器。支持**系统相册目录**、**相册隐藏相册目录**与**本地文件目录**三大核心来源，并深度整合 Face ID 生物识别隐私加密保护与全套专业手势交互。

---

## 🌟 核心特性

### 1. 三大视频目录无缝支持
- **系统相册目录**：自动汇聚「全部视频」、智能相册（最近项目、个人收藏、慢动作、延时摄影、屏幕录制、电影效果）以及用户自建相册，支持 4K/60fps/HDR 规格徽标解析。
- **相册「已隐藏」相册目录**：直接穿透读取系统相册隐藏目录（`smartAlbumAllHidden`）中的所有视频，无需恢复隐藏即可直接流畅播放，杜绝隐私泄露。
- **本地文件目录**：
  - 支持 **Mac 访达 (Finder) / Windows iTunes 文件共享**：通过数据线直接将视频文件批量拷贝到 App 内；
  - 支持从 iOS 系统「文件」App 导入任意外部存储、iCloud Drive、U 盘内的视频；
  - 支持创建分类文件夹、多级目录浏览、重命名与文件移动；
  - 支持独立于系统的 **「本地私密保险箱」**，隐藏在加密沙盒目录中。

### 2. 生物识别隐私加密保护 (Face ID / Touch ID)
- 进入「已隐藏相册」视频或「本地私密保险箱」时，默认需通过 **Face ID / Touch ID / 设备密码** 认证；
- App 退入后台时自动瞬间重新上锁，确保在他人借用手机时不泄露私密视频；
- 可在「设置」中根据个人偏好开启或关闭生物识别验证要求。

### 3. 全套专业手势交互
- **左半屏垂直滑动**：无级调节屏幕亮度，配备拟真磨砂 HUD 指示条；
- **右半屏垂直滑动**：调节系统音量，配备动态喇叭与音量百分比 HUD；
- **水平拖拽滑动**：时间轴精准微调，实时显示跳转目标时间与偏移差值（如 `+00:15s`）；
- **左右半屏双击**：触发 ±10s（可在设置中自定义为 5s/10s/15s/30s）快进/快退，带微触觉反馈与动效涟漪；
- **屏幕中心双击**：极速播放 / 暂停切换；
- **长按屏幕任意位置**：触发 **2.0× 瞬时极速快进**，松手立即恢复原有倍速；
- **防误触屏幕锁**：一键锁定画面所有手势与控制条，观影不误触。

### 4. 影院级播放控制与专业技术面板
- **画面比例自由切换**：原画比例 (Aspect Fit)、全屏铺满裁切 (Aspect Fill)、强制 16:9、强制 4:3；
- **多档倍速**：0.5×、0.75×、1.0×、1.25×、1.5×、2.0×、3.0×；
- **画中画 (PiP)**：支持系统原生画中画浮窗播放，退回桌面继续观影；
- **后台纯音频播放**：息屏或切换应用时持续聆听声音；
- **一键截取原画高清视频帧**：采用 `AVAssetImageGenerator` 提取当前时间戳无损全分辨率帧并直接保存到系统相册；
- **视频详细技术规格面板 (Info Sheet)**：
  - 物理分辨率与画幅比例（如 `3840 × 2160 (16:9)`）
  - 真实帧率（如 `59.94 fps`）与平均码率
  - 视频解码器（HEVC / H.264 / Apple ProRes 422HQ 等）
  - 色彩原色与动态范围（ITU-R BT.2020、HDR10、HLG、Dolby Vision）
  - 音频流规格（编码、声道数、采样率）
- **字幕系统**：支持内嵌字幕轨道解析，以及通过文件选择器导入外部 `.srt` 与 `.vtt` 外挂字幕，带自动时间轴对齐与样式清洗；
- **原生 AirPlay 投屏** 与 **单曲无缝循环**。

---

## 📁 项目结构

```
outputs/GRAINPlayer/
├── GRAINPlayer/
│   ├── GRAINPlayerApp.swift          # 应用主入口
│   ├── RootView.swift                # 主框架与全屏播放容器
│   ├── DesignSystem.swift            # GRAIN 视觉系统、色彩、触觉、卡片
│   ├── Models.swift                  # 视频模型、元数据、枚举、字幕模型
│   ├── PlayerViewModel.swift         # AVPlayer 播放器核心、手势调度、HUD 控制
│   ├── CustomVideoPlayerView.swift   # AVPlayerLayer 渲染视图与画中画对接
│   ├── PlayerOverlayView.swift       # 播放器顶栏、底栏、手势捕获、状态 HUD
│   ├── VideoMetadataExtractor.swift  # 底层专业元数据与 HDR 提取器
│   ├── PhotoLibraryService.swift     # 相册与「已隐藏相册」读取服务
│   ├── PhotoLibraryView.swift        # 相册视频网格与分类栏
│   ├── FileManagerService.swift      # 本地文件沙盒、文件夹、私密保险箱管理
│   ├── FileDirectoryView.swift       # 文件目录浏览与管理视图
│   ├── BiometricLockService.swift    # Face ID / Touch ID 生物识别认证
│   ├── HiddenVaultView.swift         # 私密空间（相册隐藏 + 本地保险箱）视图
│   ├── SubtitleParser.swift          # SRT / VTT 外挂字幕解析器
│   ├── VideoInfoSheet.swift          # 视频详细参数信息面板
│   ├── SettingsView.swift            # 播放器全局设置
│   └── Assets.xcassets/              # 应用图标与主题色资产
├── GRAINPlayer.xcodeproj/            # Xcode 工程文件
└── README.md                         # 项目说明文档
```

---

## 🛠 打开与构建方式

### 本地 Xcode 运行
1. 用 **Xcode 15 / 16 或更高版本** 打开 `outputs/GRAINPlayer/GRAINPlayer.xcodeproj`。
2. 在 `Signing & Capabilities` 中选定你的 Apple Developer Team。
3. 选择 iPhone 真机或 iOS 17+ 模拟器直接运行。

### 自动打包未签名 IPA (GitHub Actions CI)
本工程已配置 `.github/workflows/build-unsigned-player-ipa.yml`：
1. 推送代码至远程仓库；
2. 在 GitHub 的 `Actions` 标签页选择 **Build Unsigned Player IPA**；
3. 点击 `Run workflow` 触发自动构建；
4. 构建完成后即可在 Artifacts 中下载 `GRAINPlayer-unsigned.ipa` 安装包。
