import Photos
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var photoLibrary = PhotoLibraryViewModel()
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("cameraAppearanceMode") private var cameraAppearanceMode = CameraAppearanceMode.dark
    @AppStorage("showHistogram") private var showHistogram = true
    @AppStorage("showCameraButton") private var showCameraButton = true
    @AppStorage("showFileImportButton") private var showFileImportButton = false
    @AppStorage("showCollageButton") private var showCollageButton = true
    /// 设置里选了“相机”时，首屏就是相机（读完一次即可，后续由用户操作切换）
    @State private var launchCameraActive = UserDefaults.standard
        .bool(forKey: "launchWithCamera")
    @State private var showDocumentPicker = false
    @State private var showExportSheet = false
    @State private var showInfoSheet = false
    @State private var showSettings = false
    @State private var showCamera = false
    @State private var showHomeCollage = false
    @State private var pendingCapturedAssetID: String?
    @State private var showDeleteConfirmation = false
    @State private var libraryImportTask: Task<Void, Never>?
    @State private var libraryImportGeneration = 0
    @State private var editingVideoAsset: PHAsset?
    @State private var targetCameraMode: CameraMode = .photo
    @State private var isLibrarySelecting = false
    @State private var browsingAsset: PHAsset? = nil
    @State private var browsingAssetList: [PHAsset] = []
    @State private var browserShareURL: URL? = nil
    @State private var showBrowserShareSheet = false
    @State private var browserInfoAsset: PHAsset? = nil
    @State private var showBrowserInfoSheet = false

    private var isCameraActive: Bool {
        showCamera || launchCameraActive
    }

    var body: some View {
        ZStack {
            GrainBackground()

            NavigationStack {
                VStack(spacing: 0) {
                    PhotoLibraryHome(library: photoLibrary, isSelecting: $isLibrarySelecting) { asset, assets in
                        browsingAssetList = assets
                        withAnimation(.easeInOut(duration: 0.2)) {
                            browsingAsset = asset
                        }
                    }

                    if !isLibrarySelecting {
                        MinimalTopBar(
                            hasPhoto: false,
                            onCamera: showCameraButton ? {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    showCamera = true
                                }
                            } : nil,
                            onFiles: showFileImportButton ? { showDocumentPicker = true } : nil,
                            onCollage: showCollageButton ? { showHomeCollage = true } : nil,
                            onInfo: { showInfoSheet = true },
                            onSettings: { showSettings = true },
                            histogramVisible: showHistogram,
                            onToggleHistogram: nil,
                            onExport: {},
                            onDelete: nil
                        )
                    }
                }
                .background(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar(.hidden, for: .navigationBar)
                .ignoresSafeArea(.container, edges: .bottom)
                .navigationDestination(isPresented: editorPresented) {
                    VStack(spacing: 0) {
                        MinimalTopBar(
                            hasPhoto: true,
                            onCancel: {
                                cancelPendingLibraryImport()
                                editor.returnHome()
                                Task { await photoLibrary.refresh() }
                            },
                            onCamera: nil,
                            onFiles: showFileImportButton ? { showDocumentPicker = true } : nil,
                            onCollage: nil,
                            onInfo: { showInfoSheet = true },
                            onSettings: { showSettings = true },
                            histogramVisible: showHistogram,
                            onToggleHistogram: nil,
                            onExport: {
                                editor.exportResult = nil
                                editor.exportShareURL = nil
                                showExportSheet = true
                            },
                            onDelete: { showDeleteConfirmation = true }
                        )

                        EditorWorkspace(
                            showHistogram: showHistogram,
                            onBackToLibrary: {
                                cancelPendingLibraryImport()
                                editor.returnHome()
                                Task { await photoLibrary.refresh() }
                            },
                            onSwitchPhoto: { offset in
                                switchLibraryPhoto(offset)
                            }
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear.ignoresSafeArea())
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
            .environment(\.colorScheme, appearanceMode.resolvedColorScheme(systemScheme: systemColorScheme))

            photoBrowserOverlay

            if isCameraActive {
                CameraView(
                    initialMode: targetCameraMode,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showCamera = false
                            launchCameraActive = false
                        }
                    },
                    onOpenCapture: { identifier in
                        pendingCapturedAssetID = identifier
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showCamera = false
                            launchCameraActive = false
                        }
                    }
                )
                .environment(\.colorScheme, cameraAppearanceMode.resolvedColorScheme(systemScheme: systemColorScheme))
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .preferredColorScheme(isCameraActive ? cameraAppearanceMode.colorScheme : appearanceMode.colorScheme)
        .sheet(isPresented: $showDocumentPicker) {
            DocumentRawImporter { url in
                showDocumentPicker = false
                editor.sourceAssetIdentifier = nil
                editor.importPhoto(from: url)
            } onCancel: {
                showDocumentPicker = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSettingsSheet()
                .environmentObject(editor)
                .presentationDetents([.height(600)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showInfoSheet) {
            ImageInfoSheet()
                .environmentObject(editor)
        }
        .sheet(isPresented: $showBrowserShareSheet, onDismiss: {
            if let url = browserShareURL {
                try? FileManager.default.removeItem(at: url)
            }
            browserShareURL = nil
        }) {
            if let url = browserShareURL {
                GrainShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showBrowserInfoSheet) {
            if let asset = browserInfoAsset {
                ImageInfoSheet(asset: asset)
                    .environmentObject(editor)
            }
        }
        .sheet(isPresented: $showSettings) {
            AppSettingsView()
                .presentationDetents([.height(700)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showHomeCollage) {
            CollageEditorView(assets: [])
        }
        .fullScreenCover(isPresented: Binding<Bool>(
            get: { editingVideoAsset != nil },
            set: { isPresent in
                if !isPresent {
                    editingVideoAsset = nil
                }
            }
        )) {
            if let asset = editingVideoAsset {
                VideoEditorView(
                    asset: asset,
                    onClose: {
                        editingVideoAsset = nil
                        Task { await photoLibrary.refresh() }
                    },
                    onSwitchVideo: { offset in
                        switchLibraryVideo(offset)
                    }
                )
            }
        }
        .onChange(of: isCameraActive) { _, active in
            handleCameraDismiss(presented: active)
        }
        .confirmationDialog(
            editor.sourceAssetIdentifier == nil ? "关闭当前照片？" : "删除这张照片？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                editor.sourceAssetIdentifier == nil ? "关闭" : "删除照片",
                role: .destructive
            ) {
                deleteCurrentPhoto()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                editor.sourceAssetIdentifier == nil
                    ? "这张照片来自文件导入，只会关闭编辑，不会删除原文件。"
                    : "照片会从系统图库中删除，此操作无法撤销。"
            )
        }
        .alert(
            "无法打开照片",
            isPresented: Binding(
                get: { editor.errorMessage != nil },
                set: { if !$0 { editor.errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(editor.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let notice = editor.noticeMessage {
                Text(notice)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(GrainTheme.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 360)
                    .background(GrainTheme.paper, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .padding(.top, 62)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if editor.isPreparing && editor.photo == nil {
                VStack(spacing: 10) {
                    ProgressView().tint(GrainTheme.paper)
                    Text("正在读取原始照片")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(.black.opacity(0.78), in: Capsule())
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await photoLibrary.refresh()
                }
            }
        }
        .onOpenURL { url in
            handleWidgetDeepLink(url)
        }
    }

    @ViewBuilder
    private var photoBrowserOverlay: some View {
        if let asset = browsingAsset, editor.photo == nil {
            PhotoDetailBrowserView(
                initialAsset: asset,
                allAssets: browsingAssetList.isEmpty ? photoLibrary.assets : browsingAssetList,
                library: photoLibrary,
                onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        browsingAsset = nil
                    }
                },
                onEdit: handleBrowserEdit,
                onShowInfo: handleBrowserShowInfo,
                onShare: handleBrowserShare,
                onDelete: handleBrowserDelete
            )
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                removal: .opacity.combined(with: .scale(scale: 0.96))
            ))
            .zIndex(2)
        }
    }

    private func handleBrowserEdit(_ targetAsset: PHAsset) {
        if targetAsset.mediaType == .video {
            editingVideoAsset = targetAsset
        } else {
            importLibraryAsset(targetAsset)
        }
    }

    private func handleBrowserShowInfo(_ targetAsset: PHAsset) {
        browserInfoAsset = targetAsset
        showBrowserInfoSheet = true
    }

    private func handleBrowserShare(_ targetAsset: PHAsset) {
        Task { @MainActor in
            if let url = try? await PhotoLibraryAssetLoader.loadOriginal(asset: targetAsset) {
                browserShareURL = url
                showBrowserShareSheet = true
            }
        }
    }

    private func handleBrowserDelete(_ targetAsset: PHAsset) {
        browsingAssetList.removeAll { $0.localIdentifier == targetAsset.localIdentifier }
        Task {
            try? await photoLibrary.deleteAssets(identifiers: [targetAsset.localIdentifier])
            await photoLibrary.refresh()
        }
    }

    /// 响应小组件与外部深度链接跳转（支持拍照模式、录像模式与暗房图库）
    private func handleWidgetDeepLink(_ url: URL) {
        guard url.scheme == "grain" else { return }
        if url.host == "camera" {
            let isVideo = url.query?.contains("mode=video") == true
            targetCameraMode = isVideo ? .video : .photo
            withAnimation(.easeInOut(duration: 0.22)) {
                showCamera = true
            }
        } else if url.host == "library" {
            withAnimation(.easeInOut(duration: 0.22)) {
                showCamera = false
                launchCameraActive = false
            }
            editor.returnHome()
        }
    }

    /// 相机退场后按需打开刚拍的照片（两种进入方式都会走这里）
    private func handleCameraDismiss(presented: Bool) {
        guard !presented, let identifier = pendingCapturedAssetID else { return }
        pendingCapturedAssetID = nil
        Task {
            // 等相机视图退场后再推入编辑页，避免两个转场叠在一起
            try? await Task.sleep(for: .milliseconds(320))
            openCapturedAsset(identifier)
        }
    }

    private var editorPresented: Binding<Bool> {
        Binding(
            get: { editor.photo != nil },
            set: { presented in
                if !presented {
                    cancelPendingLibraryImport()
                    editor.returnHome()
                    Task {
                        await photoLibrary.refresh()
                    }
                }
            }
        )
    }

    private func importLibraryAsset(_ asset: PHAsset) {
        cancelPendingLibraryImport()
        libraryImportGeneration += 1
        let generation = libraryImportGeneration

        libraryImportTask = Task {
            do {
                let url = try await photoLibrary.originalFileURL(for: asset)
                try Task.checkCancellation()
                guard generation == libraryImportGeneration else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                editor.importPhoto(from: url)
                if editor.photo != nil {
                    editor.attachLibraryAssetIdentifier(asset.localIdentifier)
                }
                libraryImportTask = nil
            } catch is CancellationError {
                guard generation == libraryImportGeneration else { return }
                libraryImportTask = nil
            } catch {
                guard generation == libraryImportGeneration else { return }
                editor.errorMessage = error.localizedDescription
                libraryImportTask = nil
            }
        }
    }

    private func cancelPendingLibraryImport() {
        libraryImportGeneration += 1
        libraryImportTask?.cancel()
        libraryImportTask = nil
    }

    /// 编辑页左右滑动切换到图库中的相邻照片（自动跳过视频文件）
    private func switchLibraryPhoto(_ offset: Int) {
        guard let identifier = editor.sourceAssetIdentifier else { return }
        let photos = photoLibrary.assets.filter { $0.mediaType == .image }
        guard let index = photos.firstIndex(where: { $0.localIdentifier == identifier }) else { return }
        let targetIndex = index + offset
        guard photos.indices.contains(targetIndex) else { return }
        importLibraryAsset(photos[targetIndex])
    }

    /// 视频编辑页左右滑动切换到图库中的相邻视频，顺序与照片一致
    private func switchLibraryVideo(_ offset: Int) {
        guard let current = editingVideoAsset else { return }
        let videos = photoLibrary.assets.filter { $0.mediaType == .video }
        guard let index = videos.firstIndex(where: { $0.localIdentifier == current.localIdentifier }) else { return }
        let targetIndex = index + offset
        guard videos.indices.contains(targetIndex) else { return }
        editingVideoAsset = videos[targetIndex]
    }

    /// 打开相机刚写入相册的照片或视频
    private func openCapturedAsset(_ identifier: String) {
        let result = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        )
        guard let asset = result.firstObject else { return }
        if asset.mediaType == .video {
            editingVideoAsset = asset
        } else {
            importLibraryAsset(asset)
        }
    }

    /// 删除当前编辑的照片：来自图库的会一并从系统相册删除，
    /// 文件导入的只关闭编辑。
    private func deleteCurrentPhoto() {
        guard let identifier = editor.sourceAssetIdentifier else {
            editor.returnHome()
            Task { await photoLibrary.refresh() }
            return
        }
        Task {
            do {
                try await photoLibrary.deleteAssets(identifiers: [identifier])
                editor.returnHome(discardingRecipe: true)
            } catch {
                editor.errorMessage = error.localizedDescription
            }
        }
    }
}

private enum HomeTool: String, CaseIterable, Identifiable {
    case camera
    case files
    case collage
    case settings

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .files: "folder"
        case .collage: "slider.horizontal.2.square.on.square"
        case .settings: "gearshape"
        }
    }

    var label: String {
        switch self {
        case .camera: "打开相机"
        case .files: "从文件导入"
        case .collage: "编辑工作台"
        case .settings: "打开设置"
        }
    }
}

private struct MinimalTopBar: View {
    let hasPhoto: Bool
    var onCancel: (() -> Void)? = nil
    let onCamera: (() -> Void)?
    let onFiles: (() -> Void)?
    let onCollage: (() -> Void)?
    let onInfo: () -> Void
    let onSettings: () -> Void
    let histogramVisible: Bool
    let onToggleHistogram: (() -> Void)?
    let onExport: () -> Void
    let onDelete: (() -> Void)?

    @AppStorage("homeToolOrder") private var homeToolOrder = "camera,files,collage,settings"
    @State private var draggingHomeTool: HomeTool?
    @State private var homeToolDrag: CGFloat = 0
    @State private var suppressHomeToolTap = false

    var body: some View {
        HStack(spacing: 12) {
            if hasPhoto {
                if let onCancel {
                    Button(action: onCancel) {
                        Text("取消")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .liquidGlassCapsule()
                    }
                    .buttonStyle(LiquidGlassButtonStyle())
                    .accessibilityLabel("取消并返回主页")
                }

                Spacer()

                if let onToggleHistogram {
                    Button(action: onToggleHistogram) {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(histogramVisible ? GrainTheme.accent : GrainTheme.muted)
                            .liquidGlassCircle(size: 38, isAccent: histogramVisible)
                    }
                    .buttonStyle(LiquidGlassButtonStyle())
                    .accessibilityLabel(histogramVisible ? "隐藏直方图" : "显示直方图")
                }

                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(GrainTheme.danger)
                            .liquidGlassCircle(size: 38)
                    }
                    .buttonStyle(LiquidGlassButtonStyle())
                    .accessibilityLabel("删除当前照片")
                }

                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(GrainTheme.paper)
                        .liquidGlassCircle(size: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .accessibilityLabel("查看图片信息")

                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(GrainTheme.paper)
                        .liquidGlassCircle(size: 38)
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .accessibilityLabel("导出或分享")
            } else {
                // 主页底部：去掉“GRAIN”文字，所有功能图标集中居中显示，长按可左右拖动调整顺序
                Spacer()

                HStack(spacing: 14) {
                    ForEach(visibleHomeTools) { tool in
                        homeToolButton(tool)
                    }
                }

                Spacer()
            }
        }
        .foregroundStyle(GrainTheme.paper)
        .padding(.horizontal, 18)
        .frame(height: hasPhoto ? 54 : 44)
        .padding(.bottom, hasPhoto ? 0 : 22)
    }

    // MARK: 主页入口的顺序

    private var orderedHomeToolIDs: [String] {
        let valid = HomeTool.allCases.map(\.rawValue)
        let stored = homeToolOrder.split(separator: ",").map(String.init)
        var ids = stored.filter { valid.contains($0) }
        for id in valid where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }

    private var visibleHomeTools: [HomeTool] {
        orderedHomeToolIDs.compactMap { id in
            guard let tool = HomeTool(rawValue: id) else { return nil }
            switch tool {
            case .camera: return onCamera == nil ? nil : tool
            case .files: return onFiles == nil ? nil : tool
            case .collage: return onCollage == nil ? nil : tool
            case .settings: return tool
            }
        }
    }

    private func homeToolButton(_ tool: HomeTool) -> some View {
        Button {
            guard !suppressHomeToolTap else { return }
            switch tool {
            case .camera: onCamera?()
            case .files: onFiles?()
            case .collage: onCollage?()
            case .settings: onSettings()
            }
        } label: {
            Group {
                if tool == .settings {
                    AnimatedEditorMark(size: 26)
                } else {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .foregroundStyle(GrainTheme.paper)
            .liquidGlassCircle(size: 38)
            .scaleEffect(draggingHomeTool == tool ? 1.15 : 1)
            .offset(x: draggingHomeTool == tool ? homeToolDrag : 0)
            .zIndex(draggingHomeTool == tool ? 1 : 0)
            .animation(.snappy(duration: 0.18), value: draggingHomeTool)
        }
        .buttonStyle(LiquidGlassButtonStyle())
        .accessibilityLabel(tool.label)
        .simultaneousGesture(homeToolReorderGesture(tool))
    }

    /// 长按后左右拖动，松手按位移换位
    private func homeToolReorderGesture(_ tool: HomeTool) -> some Gesture {
        LongPressGesture(minimumDuration: 0.34)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if draggingHomeTool == nil {
                        draggingHomeTool = tool
                        suppressHomeToolTap = true
                        GrainHaptics.mediumImpact(enabled: true)
                    }
                    if let drag {
                        homeToolDrag = drag.translation.width
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                guard let dragging = draggingHomeTool else {
                    suppressHomeToolTap = false
                    return
                }
                commitHomeToolOrder(dragging, translation: homeToolDrag)
                withAnimation(.snappy(duration: 0.2)) {
                    draggingHomeTool = nil
                    homeToolDrag = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    suppressHomeToolTap = false
                }
            }
    }

    private func commitHomeToolOrder(_ tool: HomeTool, translation: CGFloat) {
        var visible = visibleHomeTools.map(\.id)
        guard let index = visible.firstIndex(of: tool.id) else { return }
        // 每个按钮宽 38 + 间距 14
        let steps = Int((translation / 52).rounded())
        let target = min(max(index + steps, 0), visible.count - 1)
        guard target != index else { return }
        visible.remove(at: index)
        visible.insert(tool.id, at: target)
        let hidden = orderedHomeToolIDs.filter { !visible.contains($0) }
        withAnimation(.snappy(duration: 0.22)) {
            homeToolOrder = (visible + hidden).joined(separator: ",")
        }
        GrainHaptics.selection(enabled: true)
    }
}

private struct EditorWorkspace: View {
    @EnvironmentObject private var editor: EditorViewModel
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    let showHistogram: Bool
    let onBackToLibrary: () -> Void
    let onSwitchPhoto: (Int) -> Void
    @State private var showCropEditor = false
    @State private var editingTextID: UUID?
    @State private var selectedTextID: UUID?
    @State private var showTextEditor = false
    @State private var showMosaicEditor = false
    @State private var didSwipeBack = false
    @State private var editorToolPage: EditorToolPage = .adjust
    @State private var showAdvancedGrade = false
    @State private var isPickingWhiteBalance = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PhotoEditorCanvas(
                    showHistogram: showHistogram,
                    selectedTextID: $selectedTextID,
                    isPickingWhiteBalance: $isPickingWhiteBalance,
                    onSwitchPhoto: onSwitchPhoto,
                    onEditText: { id in
                        editingTextID = id
                        selectedTextID = id
                        showTextEditor = true
                    },
                    focusOverlap: showAdvancedGrade ? advancedOverlap : 0
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                EditorToolsPager(
                    page: $editorToolPage,
                    onCrop: { showCropEditor = true },
                    onMosaic: { showMosaicEditor = true },
                    onAdvanced: {
                        withAnimation(.snappy(duration: 0.28)) {
                            showAdvancedGrade = true
                        }
                    },
                    onAddText: {
                        let id = editor.addTextOverlay()
                        editingTextID = id
                        selectedTextID = id
                        showTextEditor = true
                    }
                )
                .frame(height: 150)
                .padding(.bottom, 14)
            }

            if showAdvancedGrade {
                AdvancedGradePanel(
                    onClose: {
                        withAnimation(.snappy(duration: 0.26)) {
                            showAdvancedGrade = false
                        }
                    },
                    onStartPickingWhiteBalance: {
                        showAdvancedGrade = false
                        isPickingWhiteBalance = true
                    }
                )
                .environmentObject(editor)
                .frame(height: 412)
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
        }
        .fullScreenCover(isPresented: $showCropEditor) {
            CropEditorView()
                .environmentObject(editor)
        }
        .fullScreenCover(isPresented: $showMosaicEditor) {
            MosaicEditorView()
                .environmentObject(editor)
        }
        .sheet(isPresented: $showTextEditor, onDismiss: { editingTextID = nil }) {
            if let editingTextID {
                TextOverlayEditorView(overlayID: editingTextID)
                    .environmentObject(editor)
                    .presentationDetents([.height(455)])
                    .presentationDragIndicator(.visible)
            }
        }
        .simultaneousGesture(edgeSwipeGesture)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// 进阶抽屉盖住画布的高度 = 抽屉高度（412）− 底部工具栏（150 + 14）
    private var advancedOverlap: CGFloat { 412 - 164 }

    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !didSwipeBack,
                      value.startLocation.x <= 34,
                      value.translation.width > 64,
                      value.translation.width > abs(value.translation.height) * 1.35
                else { return }

                didSwipeBack = true
                GrainHaptics.mediumImpact(enabled: hapticsEnabled)
                onBackToLibrary()
            }
            .onEnded { _ in
                didSwipeBack = false
            }
    }
}

private enum EditorToolPage: Int {
    case adjust
    case film
}

private struct EditorToolsPager: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Binding var page: EditorToolPage
    let onCrop: () -> Void
    let onMosaic: () -> Void
    let onAdvanced: () -> Void
    let onAddText: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // 照片编辑（只保留图标）
                Button {
                    withAnimation(.snappy(duration: 0.24)) {
                        page = .adjust
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(page == .adjust ? GrainTheme.accent : GrainTheme.muted)
                        .frame(width: 32, height: 25)
                        .background {
                            if page == .adjust {
                                Capsule().fill(.ultraThinMaterial)
                                    .overlay(Capsule().strokeBorder(GrainTheme.accent.opacity(0.45), lineWidth: 0.8))
                            }
                        }
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .accessibilityLabel("照片编辑")

                // 胶片模拟（只保留图标）
                Button {
                    withAnimation(.snappy(duration: 0.24)) {
                        page = .film
                    }
                } label: {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(page == .film ? GrainTheme.accent : GrainTheme.muted)
                        .frame(width: 32, height: 25)
                        .background {
                            if page == .film {
                                Capsule().fill(.ultraThinMaterial)
                                    .overlay(Capsule().strokeBorder(GrainTheme.accent.opacity(0.45), lineWidth: 0.8))
                            }
                        }
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .accessibilityLabel("胶片模拟")

                // AI 调色（图标 + "AI"）
                Button {
                    editor.applyAiColorGrading()
                } label: {
                    HStack(spacing: 2.5) {
                        if editor.isAiGrading {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(GrainTheme.accent)
                        } else {
                            Image(systemName: editor.isAiGradingApplied ? "sparkles" : "sparkle")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text("AI")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(editor.isAiGradingApplied ? GrainTheme.accent : Color(hex: 0x8E8E93))
                    .padding(.horizontal, 8)
                    .frame(height: 25)
                    .background(Color.white, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                editor.isAiGradingApplied ? GrainTheme.accent.opacity(0.40) : Color.black.opacity(0.08),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1.5)
                    .scaleEffect(editor.isAiGradingApplied ? 1.02 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: editor.isAiGradingApplied)
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .disabled(editor.isAiGrading)
                .accessibilityLabel(editor.isAiGradingApplied ? "关闭 AI 调色" : "开启 AI 调色")

                Spacer()

                Button {
                    editor.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(editor.canUndo ? GrainTheme.paper : GrainTheme.muted.opacity(0.35))
                        .liquidGlassCircle(size: 26)
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .disabled(!editor.canUndo)
                .accessibilityLabel("撤销上一步")

                Button {
                    if page == .film {
                        editor.recommendLook()
                    } else {
                        editor.recommendAdjustmentsOnly()
                    }
                } label: {
                    Group {
                        if editor.isRecommending {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        recommendationActive ? GrainTheme.accent : GrainTheme.muted
                    )
                    .liquidGlassCircle(size: 26, isAccent: recommendationActive)
                }
                .buttonStyle(LiquidGlassButtonStyle())
                .disabled(editor.isRecommending)
                .accessibilityLabel(page == .film ? "推荐胶片" : "推荐照片参数")

                Menu {
                    Button("复制调色预设", systemImage: "doc.on.doc") {
                        editor.copyPreset()
                    }
                    Button("粘贴调色预设", systemImage: "doc.on.clipboard") {
                        editor.pastePreset()
                    }
                    Divider()
                    Button("重置全部调整", systemImage: "arrow.counterclockwise", role: .destructive) {
                        editor.resetAllAdjustments()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GrainTheme.muted)
                        .liquidGlassCircle(size: 26)
                }
                .buttonStyle(LiquidGlassButtonStyle())
            }
            .padding(.horizontal, 18)
            .frame(height: 32)
            .contentShape(Rectangle())
            .gesture(pageSwipeGesture)

            ZStack {
                if page == .adjust {
                    AdjustPanel(
                        onCrop: onCrop,
                        onMosaic: onMosaic,
                        onAdvanced: onAdvanced,
                        onAddText: onAddText
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    FilmPresetBar()
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(GrainTheme.surface.opacity(0.68))
                LinearGradient(
                    colors: [Color.white.opacity(0.12), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.28), location: 0.0),
                    .init(color: Color.white.opacity(0.06), location: 0.5),
                    .init(color: Color.white.opacity(0.20), location: 1.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.8)
        }
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > 46, abs(horizontal) > vertical * 1.2 else { return }
                withAnimation(.snappy(duration: 0.24)) {
                    page = horizontal < 0 ? .film : .adjust
                }
            }
    }

    private var recommendationActive: Bool {
        page == .film
            ? editor.isRecommendationApplied
            : editor.isAdjustmentRecommendationApplied
    }
}

private struct PhotoEditorCanvas: View {
    @EnvironmentObject private var editor: EditorViewModel
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    let showHistogram: Bool
    @Binding var selectedTextID: UUID?
    @Binding var isPickingWhiteBalance: Bool
    let onSwitchPhoto: (Int) -> Void
    let onEditText: (UUID) -> Void
    /// 进阶抽屉遮挡画布的高度；0 表示没有抽屉
    let focusOverlap: CGFloat
    @State private var showOriginal = false
    @State private var compareFraction: CGFloat?
    @State private var showLivePhoto = false
    @AppStorage("focusPeakingColor") private var peakingColorRaw = "red"
    @State private var showFocusPeaking = false
    @State private var peakingMask: CGImage?
    /// 双指放大查看照片；双击复位
    @State private var zoomScale: CGFloat = 1
    @State private var pinchBaseScale: CGFloat = 1
    @State private var isPinching = false
    @State private var isPanning = false
    @State private var panOffset: CGSize = .zero
    @State private var panBase: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let imageSize = displayImageSize(in: proxy.size)
            let shownPan = displayedPan(viewport: proxy.size, imageSize: imageSize)

            ZStack {
                GrainTheme.black

                // 只有照片层（含文字与对比线）随进阶抽屉上移，
                // 直方图、格式标签、底部按钮等 HUD 保持原地不动。
                photoLayer(viewport: proxy.size, imageSize: imageSize)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(
                        photoScale(viewport: proxy.size, imageSize: imageSize)
                            * zoomScale,
                        anchor: .center
                    )
                    .offset(
                        x: shownPan.width,
                        y: photoOffset(viewport: proxy.size, imageSize: imageSize)
                            + shownPan.height
                    )
                    .animation(.snappy(duration: 0.3), value: focusOverlap)

                if isPickingWhiteBalance {
                    whiteBalancePicker(viewport: proxy.size, imageSize: imageSize)
                }

                VStack {
                    HStack(alignment: .top, spacing: 12) {
                        Label(editor.photo?.sourceKindLabel ?? "RAW", systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundStyle(GrainTheme.paper)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(GrainTheme.surface.opacity(0.88), in: Capsule())
                            .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                            .shadow(color: Color.black.opacity(0.10), radius: 3, y: 1)

                        Spacer()

                        if showHistogram, let histogram = editor.histogram {
                            HistogramView(data: histogram)
                                .frame(width: 82, height: 46)
                                .offset(x: 5, y: -6)
                        }

                        if editor.isPreparing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(GrainTheme.paper)
                                .padding(8)
                                .background(GrainTheme.surface.opacity(0.88), in: Circle())
                                .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
                                .shadow(color: Color.black.opacity(0.10), radius: 3, y: 1)
                        }
                    }

                    Spacer()

                    HStack(alignment: .bottom) {
                        Text(showOriginal ? "原片" : editor.selectedProfile.name)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                            .padding(.horizontal, 10)
                            .frame(height: 27)
                            .background(GrainTheme.surface.opacity(0.88), in: Capsule())
                            .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                            .shadow(color: Color.black.opacity(0.10), radius: 3, y: 1)

                        Spacer()

                        if editor.hasLivePhoto {
                            Button {
                                showLivePhoto = true
                            } label: {
                                Image(systemName: "livephoto.play")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(GrainTheme.paper)
                                    .frame(width: 30, height: 29)
                                    .background(GrainTheme.surface.opacity(0.88), in: Capsule())
                                    .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                                    .shadow(color: Color.black.opacity(0.10), radius: 3, y: 1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("播放实况照片")
                        }

                        Button {
                            showFocusPeaking.toggle()
                            GrainHaptics.lightImpact(enabled: hapticsEnabled)
                        } label: {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(
                                    showFocusPeaking ? GrainTheme.accent : GrainTheme.paper
                                )
                                .frame(width: 30, height: 29)
                                .background(GrainTheme.surface.opacity(0.88), in: Capsule())
                                .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                                .shadow(color: Color.black.opacity(0.10), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showFocusPeaking ? "关闭峰值对焦" : "显示峰值对焦")

                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                compareFraction = compareFraction == nil ? 0.5 : nil
                            }
                        } label: {
                            Image(systemName: "rectangle.lefthalf.inset.filled")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(
                                    compareFraction == nil ? GrainTheme.paper : GrainTheme.accent
                                )
                                .frame(width: 30, height: 29)
                                .background(GrainTheme.surface.opacity(0.88), in: Capsule())
                                .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                                .shadow(color: Color.black.opacity(0.10), radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(compareFraction == nil ? "开启前后对比" : "关闭前后对比")

                        Text(compareFraction == nil ? "按住看原片" : "拖动分割线对比")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                            .padding(.horizontal, 11)
                            .frame(height: 29)
                            .background(GrainTheme.surface.opacity(0.88), in: Capsule())
                            .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                            .shadow(color: Color.black.opacity(0.10), radius: 3, y: 1)
                            .contentShape(Capsule())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        withAnimation(.easeOut(duration: 0.12)) {
                                            showOriginal = true
                                        }
                                    }
                                    .onEnded { _ in
                                        withAnimation(.easeOut(duration: 0.16)) {
                                            showOriginal = false
                                        }
                                    }
                            )
                    }
                }
                .padding(13)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .simultaneousGesture(switchPhotoGesture)
            .simultaneousGesture(pinchZoomGesture(viewport: proxy.size, imageSize: imageSize))
            .simultaneousGesture(zoomPanGesture(viewport: proxy.size, imageSize: imageSize))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .fullScreenCover(isPresented: $showLivePhoto) {
            if let asset = editor.currentPHAsset {
                LivePhotoViewer(asset: asset)
            }
        }
        .task(id: peakingTaskID) {
            if showFocusPeaking {
                await buildPeakingMask()
            } else {
                peakingMask = nil
            }
        }
        .onChange(of: zoomScale) { oldValue, newValue in
            let wasZoomed = oldValue > 1.01
            let isZoomed = newValue > 1.01
            if isZoomed && !wasZoomed {
                editor.prepareZoomPreview()
            } else if !isZoomed && wasZoomed {
                editor.releaseZoomPreview()
            }
        }
    }

    private var peakingTaskID: String {
        "\(editor.photo?.displayName ?? "-")-\(editor.editedPreview?.width ?? 0)-\(showFocusPeaking)"
    }

    private func buildPeakingMask() async {
        guard let image = editor.editedPreview ?? editor.originalPreview else {
            peakingMask = nil
            return
        }
        let mask = await Task.detached(priority: .userInitiated) {
            FocusPeakingRenderer.mask(from: image)
        }.value
        guard !Task.isCancelled, showFocusPeaking else { return }
        peakingMask = mask
    }

    // MARK: - 照片层（进阶抽屉打开时单独上移）

    /// 抽屉上方仍然可见的画布高度
    private func visibleHeight(for viewport: CGSize) -> CGFloat {
        max(viewport.height - focusOverlap, 120)
    }

    /// 只有照片本身缩小到可见区域内；HUD 不受影响
    private func photoScale(viewport: CGSize, imageSize: CGSize) -> CGFloat {
        guard focusOverlap > 0.5, imageSize.height > 0 else { return 1 }
        let available = max(visibleHeight(for: viewport) - 12, 80)
        return min(1, available / imageSize.height)
    }

    /// 把缩小后的照片中心对齐到可见区域中心
    private func photoOffset(viewport: CGSize, imageSize: CGSize) -> CGFloat {
        guard focusOverlap > 0.5 else { return 0 }
        return visibleHeight(for: viewport) / 2 - viewport.height / 2
    }

    @ViewBuilder
    private func photoLayer(viewport: CGSize, imageSize: CGSize) -> some View {
        ZStack {
            let activeImage: CGImage? = {
                if showOriginal {
                    return (zoomScale > 1.01 ? (editor.zoomOriginalPreview ?? editor.originalPreview) : editor.originalPreview)
                }
                if zoomScale > 1.01, let zoom = editor.zoomPreview {
                    return zoom
                }
                return editor.editedPreview ?? editor.originalPreview
            }()

            if let activeImage {
                imageLayer(activeImage, imageSize: imageSize, viewport: viewport)
            } else {
                ProgressView()
                    .tint(GrainTheme.paper)
            }

            if zoomScale <= 1.01,
               let fraction = compareFraction,
               let original = editor.originalPreview,
               let edited = editor.editedPreview {
                imageLayer(edited, imageSize: imageSize, viewport: viewport)
                imageLayer(original, imageSize: imageSize, viewport: viewport)
                    .mask(
                        HStack(spacing: 0) {
                            Rectangle()
                                .frame(width: max(imageSize.width * fraction, 1))
                            Spacer(minLength: 0)
                        }
                        .frame(width: imageSize.width, height: imageSize.height)
                    )
            }

            // 峰值对焦：静态预览上标出合焦边缘
            if showFocusPeaking, let mask = peakingMask {
                Image(decorative: mask, scale: 1)
                    .resizable()
                    .colorMultiply(FocusPeakingColor.resolved(peakingColorRaw).color)
                    .frame(width: imageSize.width, height: imageSize.height)
                    .position(x: viewport.width / 2, y: viewport.height / 2)
                    .opacity(0.94)
                    .allowsHitTesting(false)
            }

            TextOverlayInteractionView(
                overlays: editor.textOverlays,
                selectedID: selectedTextID,
                canvasSize: imageSize,
                hapticsEnabled: hapticsEnabled,
                onSelect: { selectedTextID = $0 },
                onEdit: onEditText,
                onDelete: { id in
                    editor.deleteTextOverlay(id: id)
                    selectedTextID = nil
                },
                onMoveStart: editor.recordUndoSnapshot,
                onMove: { id, normalizedCenter in
                    editor.moveTextOverlay(
                        id: id,
                        x: normalizedCenter.x,
                        y: normalizedCenter.y
                    )
                },
                onTapEmpty: {
                    // 编辑页不再点图进全屏，单击只取消文字选中
                    guard zoomScale <= 1.01 else { return }
                    selectedTextID = nil
                },
                onDoubleTap: { point in
                    handleDoubleTap(at: point, viewport: viewport, imageSize: imageSize)
                }
            )
            .frame(width: imageSize.width, height: imageSize.height)
            .position(x: viewport.width / 2, y: viewport.height / 2)

            if let fraction = compareFraction {
                compareHandle(
                    fraction: fraction,
                    viewport: viewport,
                    imageSize: imageSize
                )
            }
        }
        .frame(width: viewport.width, height: viewport.height)
    }

    private func imageLayer(
        _ image: CGImage,
        imageSize: CGSize,
        viewport: CGSize
    ) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: imageSize.width, height: imageSize.height)
            .position(x: viewport.width / 2, y: viewport.height / 2)
    }

    /// 双指放大查看；直接跟手无跳变，松手后由双击复位
    private func pinchZoomGesture(viewport: CGSize, imageSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    pinchBaseScale = zoomScale
                    editor.prepareZoomPreview()
                }
                let targetScale = min(max(pinchBaseScale * value, 1.0), 6.0)
                zoomScale = targetScale
            }
            .onEnded { value in
                isPinching = false
                let finalScale = min(max(pinchBaseScale * value, 1.0), 6.0)
                if finalScale <= 1.05 {
                    withAnimation(.easeOut(duration: 0.24)) {
                        zoomScale = 1.0
                        panOffset = .zero
                    }
                    editor.releaseZoomPreview()
                } else {
                    zoomScale = finalScale
                    withAnimation(.easeOut(duration: 0.16)) {
                        panOffset = clampedPan(
                            panOffset,
                            viewport: viewport,
                            imageSize: imageSize,
                            scale: finalScale
                        )
                    }
                }
            }
    }

    private func resetZoom() {
        guard zoomScale > 1.01 else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            zoomScale = 1.0
            panOffset = .zero
        }
        editor.releaseZoomPreview()
        GrainHaptics.lightImpact(enabled: hapticsEnabled)
    }

    /// 双击：未放大时平滑放大到双击的位置，已放大时缩回原始大小（一步到位，绝不二次跳跃）
    private func handleDoubleTap(at point: CGPoint, viewport: CGSize, imageSize: CGSize) {
        if zoomScale > 1.05 {
            resetZoom()
            return
        }

        editor.prepareZoomPreview()
        let target: CGFloat = 2.5
        // point 是照片画布坐标，换算到画布中心为原点的相对坐标系
        let canvasCenter = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let dx = point.x - canvasCenter.x
        let dy = point.y - canvasCenter.y
        let proposed = CGSize(width: -dx * (target - 1), height: -dy * (target - 1))

        withAnimation(.easeOut(duration: 0.28)) {
            zoomScale = target
            panOffset = clampedPan(
                proposed,
                viewport: viewport,
                imageSize: imageSize,
                scale: target
            )
        }
        GrainHaptics.lightImpact(enabled: hapticsEnabled)
    }

    /// 放大后左右/上下拖动查看照片其余部分
    private func zoomPanGesture(viewport: CGSize, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard zoomScale > 1.01 else { return }
                if !isPanning {
                    isPanning = true
                    panBase = panOffset
                }
                let proposed = CGSize(
                    width: panBase.width + value.translation.width,
                    height: panBase.height + value.translation.height
                )
                panOffset = clampedPan(
                    proposed,
                    viewport: viewport,
                    imageSize: imageSize,
                    scale: zoomScale
                )
            }
            .onEnded { _ in
                isPanning = false
                panBase = panOffset
                withAnimation(.easeOut(duration: 0.20)) {
                    panOffset = clampedPan(
                        panOffset,
                        viewport: viewport,
                        imageSize: imageSize,
                        scale: zoomScale
                    )
                }
            }
    }

    private func displayedPan(viewport: CGSize, imageSize: CGSize) -> CGSize {
        guard zoomScale > 1.001 else { return .zero }
        return panOffset
    }

    private func clampedPan(
        _ proposed: CGSize,
        viewport: CGSize,
        imageSize: CGSize,
        scale overrideScale: CGFloat? = nil
    ) -> CGSize {
        let scale = max(overrideScale ?? zoomScale, 1)
            * photoScale(viewport: viewport, imageSize: imageSize)
        let drawWidth = imageSize.width * scale
        let drawHeight = imageSize.height * scale
        let maxX = max((drawWidth - viewport.width) / 2, 0)
        let maxY = max((drawHeight - viewport.height) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    /// 在照片上左右滑动切换图库里的相邻照片；左侧边缘右滑仍留给返回手势
    private var switchPhotoGesture: some Gesture {
        DragGesture(minimumDistance: 26)
            .onEnded { value in
                guard selectedTextID == nil,
                      compareFraction == nil,
                      zoomScale <= 1.01,
                      !isPinching,
                      !isPanning
                else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 68,
                      abs(horizontal) > abs(vertical) * 1.5
                else { return }
                if horizontal > 0, value.startLocation.x <= 40 { return }
                GrainHaptics.selection(enabled: hapticsEnabled)
                // 右滑回到时间线上的上一张，左滑前往下一张
                onSwitchPhoto(horizontal > 0 ? -1 : 1)
            }
    }

    private func compareHandle(
        fraction: CGFloat,
        viewport: CGSize,
        imageSize: CGSize
    ) -> some View {
        let leftEdge = (viewport.width - imageSize.width) / 2
        return ZStack {
            Color.clear
            Rectangle()
                .fill(GrainTheme.paper.opacity(0.9))
                .frame(width: 1.5)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(GrainTheme.black)
                .frame(width: 30, height: 22)
                .background(GrainTheme.paper, in: Capsule())
        }
        .frame(width: 44, height: imageSize.height)
        .contentShape(Rectangle())
        .position(
            x: leftEdge + imageSize.width * fraction,
            y: viewport.height / 2
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let raw = (value.location.x - leftEdge) / max(imageSize.width, 1)
                    compareFraction = min(max(raw, 0.02), 0.98)
                }
        )
    }

    private func whiteBalancePicker(viewport: CGSize, imageSize: CGSize) -> some View {
        let leftEdge = (viewport.width - imageSize.width) / 2
        let topEdge = (viewport.height - imageSize.height) / 2
        return ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let x = (value.location.x - leftEdge) / max(imageSize.width, 1)
                            let y = (value.location.y - topEdge) / max(imageSize.height, 1)
                            guard (0...1).contains(x), (0...1).contains(y) else { return }
                            editor.pickWhiteBalance(
                                atNormalizedPoint: CGPoint(x: x, y: y)
                            )
                            isPickingWhiteBalance = false
                        }
                )

            HStack(spacing: 7) {
                Image(systemName: "eyedropper.halffull")
                Text("点击画面取样白平衡")
                Button {
                    isPickingWhiteBalance = false
                } label: {
                    Text("取消")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(GrainTheme.black)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(GrainTheme.paper, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(GrainTheme.paper)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(.black.opacity(0.64), in: Capsule())
            .padding(.top, 44)
        }
        .frame(width: viewport.width, height: viewport.height)
    }

    private var imageAspect: CGFloat {
        if let image = editor.editedPreview ?? editor.originalPreview,
           image.height > 0 {
            return CGFloat(image.width) / CGFloat(image.height)
        }
        guard let photo = editor.photo, photo.pixelWidth > 0, photo.pixelHeight > 0 else {
            return 3 / 2
        }
        if [5, 6, 7, 8].contains(photo.orientation) {
            return CGFloat(photo.pixelHeight) / CGFloat(photo.pixelWidth)
        }
        return CGFloat(photo.pixelWidth) / CGFloat(photo.pixelHeight)
    }

    private func displayImageSize(in viewport: CGSize) -> CGSize {
        let viewportRatio = viewport.width / max(viewport.height, 1)
        if imageAspect > viewportRatio {
            return CGSize(
                width: viewport.width,
                height: viewport.width / max(imageAspect, 0.01)
            )
        }
        return CGSize(
            width: viewport.height * imageAspect,
            height: viewport.height
        )
    }
}

struct HistogramView: View {
    let data: RGBHistogram

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 4
            let width = max(size.width - inset * 2, 1)
            let height = max(size.height - inset * 2, 1)

            var fill = Path()
            fill.move(to: CGPoint(x: inset, y: inset + height))
            for (index, value) in data.luminance.enumerated() {
                let x = inset + CGFloat(index) / CGFloat(max(data.luminance.count - 1, 1)) * width
                let y = inset + height - CGFloat(value) * height
                fill.addLine(to: CGPoint(x: x, y: y))
            }
            fill.addLine(to: CGPoint(x: inset + width, y: inset + height))
            fill.closeSubpath()
            context.fill(fill, with: .color(GrainTheme.paper.opacity(0.18)))

            draw(channel: data.red, color: Color.red.opacity(0.72), in: context, size: size, inset: inset)
            draw(channel: data.green, color: Color.green.opacity(0.62), in: context, size: size, inset: inset)
            draw(channel: data.blue, color: Color.cyan.opacity(0.72), in: context, size: size, inset: inset)
        }
        .padding(4)
        .background(GrainTheme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(GrainTheme.line, lineWidth: 0.7)
        }
        .accessibilityLabel("图像直方图")
    }

    private func draw(
        channel: [Double],
        color: Color,
        in context: GraphicsContext,
        size: CGSize,
        inset: CGFloat
    ) {
        let width = max(size.width - inset * 2, 1)
        let height = max(size.height - inset * 2, 1)
        var path = Path()
        for (index, value) in channel.enumerated() {
            let x = inset + CGFloat(index) / CGFloat(max(channel.count - 1, 1)) * width
            let y = inset + height - CGFloat(value) * height
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 0.8)
    }
}

private struct FullscreenPhotoView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @State private var fullResolutionImage: CGImage?
    @State private var isLoadingFullResolution = false
    @State private var fullResolutionError: String?
    @State private var didSwipeBack = false

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()

            if let image = fullResolutionImage ?? editor.editedPreview {
                GeometryReader { proxy in
                    let rect = fittedRect(for: image, in: proxy.size)
                    ZStack {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: rect.width, height: rect.height)

                        ForEach(editor.textOverlays) { overlay in
                            Text(overlay.text)
                                .font(
                                    overlay.font.swiftUIFont(
                                        size: max(10, min(rect.width, rect.height) * overlay.fontSize)
                                    )
                                )
                                .foregroundStyle(
                                    Color(
                                        red: overlay.red,
                                        green: overlay.green,
                                        blue: overlay.blue,
                                        opacity: overlay.alpha
                                    )
                                )
                                .multilineTextAlignment(.center)
                                .position(
                                    x: overlay.x * rect.width,
                                    y: overlay.y * rect.height
                                )
                        }
                    }
                    .frame(width: rect.width, height: rect.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .position(x: rect.midX, y: rect.midY)
                    .gesture(magnificationGesture)
                    .simultaneousGesture(dragGesture)
                    .onTapGesture(count: 2, perform: toggleZoom)
                    .animation(.easeOut(duration: 0.16), value: scale)
                    .animation(.easeOut(duration: 0.16), value: offset)
                }
            } else {
                ProgressView()
                    .tint(GrainTheme.paper)
            }

            VStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 86)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                    }

                Spacer()

                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 82)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismiss()
                    }
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(GrainTheme.paper)
                            .frame(width: 40, height: 40)
                            .background(GrainTheme.surface.opacity(0.85), in: Circle())
                            .overlay(Circle().stroke(GrainTheme.line, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(editor.selectedProfile.name)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.paper)
                        .padding(.horizontal, 11)
                        .frame(height: 29)
                        .background(GrainTheme.surface.opacity(0.85), in: Capsule())
                        .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                }
                .padding(.horizontal, 16)

                Spacer()

                Text("点上方或下方空白返回 · 双指缩放")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(GrainTheme.paper.opacity(0.72))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(GrainTheme.surface.opacity(0.85), in: Capsule())
                    .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                    .onTapGesture {
                        dismiss()
                    }
                    .padding(.bottom, 28)
            }

            if isLoadingFullResolution || fullResolutionError != nil {
                VStack {
                    HStack(spacing: 7) {
                        if isLoadingFullResolution {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(GrainTheme.paper)
                        }
                        Text(fullResolutionError == nil ? "正在载入全尺寸原图" : "无法载入全尺寸原图")
                    }
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(GrainTheme.paper)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(GrainTheme.surface.opacity(0.85), in: Capsule())
                    .overlay(Capsule().stroke(GrainTheme.line, lineWidth: 0.6))
                    .padding(.top, 62)

                    Spacer()
                }
            }
        }
        .statusBarHidden()
        .task {
            await loadFullResolutionImage()
        }
        .simultaneousGesture(fullscreenEdgeSwipeGesture)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 6)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 {
                    resetTransform()
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard scale > 1.01 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if scale > 1.05 {
                resetTransform()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func resetTransform() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
    }

    private func fittedRect(for image: CGImage, in size: CGSize) -> CGRect {
        let imageRatio = CGFloat(image.width) / CGFloat(image.height)
        let sizeRatio = size.width / max(size.height, 1)
        let fitted: CGSize
        if imageRatio > sizeRatio {
            fitted = CGSize(width: size.width, height: size.width / imageRatio)
        } else {
            fitted = CGSize(width: size.height * imageRatio, height: size.height)
        }
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func loadFullResolutionImage() async {
        guard fullResolutionImage == nil, !isLoadingFullResolution else { return }
        isLoadingFullResolution = true
        fullResolutionError = nil
        defer { isLoadingFullResolution = false }

        do {
            let image = try await editor.renderFullResolutionDisplay()
            guard !Task.isCancelled else { return }
            fullResolutionImage = image
        } catch {
            guard !Task.isCancelled else { return }
            fullResolutionError = error.localizedDescription
        }
    }

    private var fullscreenEdgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                guard !didSwipeBack,
                      value.startLocation.x <= 36,
                      value.translation.width > 68,
                      value.translation.width > abs(value.translation.height) * 1.35
                else { return }
                didSwipeBack = true
                GrainHaptics.mediumImpact(enabled: true)
                dismiss()
            }
            .onEnded { _ in
                didSwipeBack = false
            }
    }
}

private struct FilmPresetBar: View {
    @EnvironmentObject private var editor: EditorViewModel
    @AppStorage("filmOrder") private var filmOrder = ""
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var showFilmOrderEditor = false
    @State private var lastIntensityHaptic = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Text(editor.selectedProfile.shortName)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(GrainTheme.muted)
                    .lineLimit(1)
                    .frame(width: 62, alignment: .leading)

                ResetValueSlider(
                    value: intensityBinding,
                    range: 0...200,
                    onEditStart: {
                        editor.recordUndoSnapshot()
                        lastIntensityHaptic = editor.intensity * 100
                        GrainHaptics.prepare()
                    },
                    onReset: resetIntensity
                )
                .disabled(editor.selectedProfile == .neutral)

                Menu {
                    ForEach([50, 82, 100, 125, 150, 175, 200], id: \.self) { preset in
                        Button {
                            editor.recordUndoSnapshot()
                            editor.intensity = Double(preset) / 100
                            editor.markManualAdjustment()
                            lastIntensityHaptic = Double(preset)
                            GrainHaptics.selection(enabled: hapticsEnabled)
                            editor.schedulePreview()
                        } label: {
                            if Int((editor.intensity * 100).rounded()) == preset {
                                Label("\(preset)%", systemImage: "checkmark")
                            } else {
                                Text("\(preset)%")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("\(Int((editor.intensity * 100).rounded()))%")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 6, weight: .bold))
                    }
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 44, alignment: .trailing)
                }
                .disabled(editor.selectedProfile == .neutral)
                .accessibilityLabel("胶片浓度")
                .accessibilityHint("可快速选择 100%、150% 或 200%")
            }
            .padding(.horizontal, 18)
            .opacity(editor.selectedProfile == .neutral ? 0.38 : 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(orderedProfiles) { profile in
                        Button {
                            if profile != .neutral,
                               editor.selectedProfile == profile {
                                editor.selectProfile(.neutral)
                            } else {
                                editor.selectProfile(profile)
                            }
                        } label: {
                            FilmPresetChip(
                                profile: profile,
                                selected: editor.selectedProfile == profile
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        showFilmOrderEditor = true
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(GrainTheme.paper)
                                .frame(width: 82, height: 42)
                                .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 9))

                            Text("编辑排序")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(GrainTheme.paper)
                                .frame(width: 86, height: 21)
                        }
                        .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("编辑胶片排序")
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 6)
        .sheet(isPresented: $showFilmOrderEditor) {
            FilmOrderEditorView()
                .presentationDetents([.height(520)])
                .presentationDragIndicator(.visible)
        }
    }

    private var intensityBinding: Binding<Double> {
        Binding(
            get: { editor.intensity * 100 },
            set: { value in
                editor.intensity = value / 100
                editor.markManualAdjustment()
                if abs(value - lastIntensityHaptic) >= 2 {
                    lastIntensityHaptic = value
                    GrainHaptics.selection(enabled: hapticsEnabled)
                }
                editor.schedulePreview()
            }
        )
    }

    /// 双击白色旋钮恢复胶片默认浓度（82%）
    private func resetIntensity() {
        guard editor.selectedProfile != .neutral else { return }
        let defaultValue = 82.0
        guard abs(editor.intensity * 100 - defaultValue) > 0.5 else { return }
        editor.recordUndoSnapshot()
        editor.intensity = defaultValue / 100
        editor.markManualAdjustment()
        lastIntensityHaptic = defaultValue
        GrainHaptics.mediumImpact(enabled: hapticsEnabled)
        editor.schedulePreview()
    }

    private var orderedProfiles: [FilmProfile] {
        FilmProfile.resolvedDisplayOrder(from: filmOrder)
    }
}

private enum AdjustCategory: String, CaseIterable, Identifiable {
    case light
    case color
    case effects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "光线"
        case .color: "颜色"
        case .effects: "效果"
        }
    }
}

private enum AdjustTool: String, CaseIterable, Identifiable {
    case intensity
    case exposure
    case contrast
    case highlights
    case shadows
    case whites
    case blacks
    case temperature
    case tint
    case vibrance
    case saturation
    case clarity
    case sharpness
    case fade
    case grain
    case vignette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intensity: "强度"
        case .exposure: "曝光"
        case .contrast: "对比"
        case .highlights: "高光"
        case .shadows: "阴影"
        case .whites: "白色"
        case .blacks: "黑色"
        case .temperature: "色温"
        case .tint: "色调"
        case .vibrance: "自然饱和"
        case .saturation: "饱和"
        case .clarity: "清晰度"
        case .sharpness: "锐化"
        case .fade: "褪色"
        case .grain: "颗粒"
        case .vignette: "暗角"
        }
    }

    var category: AdjustCategory {
        switch self {
        case .exposure, .contrast, .highlights, .shadows, .whites, .blacks:
            .light
        case .temperature, .tint, .vibrance, .saturation:
            .color
        case .intensity, .clarity, .sharpness, .fade, .grain, .vignette:
            .effects
        }
    }
}

private struct AdjustPanel: View {
    @EnvironmentObject private var editor: EditorViewModel
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    let onCrop: () -> Void
    let onMosaic: () -> Void
    let onAdvanced: () -> Void
    let onAddText: () -> Void
    @State private var selectedCategory: AdjustCategory = .light
    @State private var selectedTool: AdjustTool = .exposure
    @State private var lastHapticValue = Double.nan

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 22) {
                ForEach(AdjustCategory.allCases) { category in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            selectedCategory = category
                            selectedTool = tools(for: category).first ?? .exposure
                            lastHapticValue = value(for: selectedTool)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(category.title)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(
                                    selectedCategory == category ? GrainTheme.paper : GrainTheme.muted
                                )
                            Capsule()
                                .fill(selectedCategory == category ? GrainTheme.accent : .clear)
                                .frame(width: 18, height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()

                Button(action: onAdvanced) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            editor.settings.hasAdvancedGrade
                                ? GrainTheme.accent
                                : GrainTheme.paper
                        )
                        .frame(width: 30, height: 27)
                        .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("曲线、HSL 与白平衡")

                Button(action: onCrop) {
                    Image(systemName: "crop.rotate")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GrainTheme.paper)
                        .frame(width: 30, height: 27)
                        .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("裁剪与构图")

                Button(action: onMosaic) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GrainTheme.paper)
                        .frame(width: 30, height: 27)
                        .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加马赛克")

                Button(action: onAddText) {
                    Image(systemName: "textformat")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GrainTheme.paper)
                        .frame(width: 30, height: 27)
                        .background(GrainTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加文字")
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(tools(for: selectedCategory)) { tool in
                        Button {
                            selectedTool = tool
                            lastHapticValue = value(for: tool)
                        } label: {
                            Text(tool.title)
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(
                                    selectedTool == tool ? GrainTheme.black : GrainTheme.muted
                                )
                                .padding(.horizontal, 13)
                                .frame(height: 28)
                                .background(
                                    selectedTool == tool ? GrainTheme.paper : GrainTheme.raised,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 12) {
                ResetValueSlider(
                    value: activeBinding,
                    range: activeRange,
                    onEditStart: {
                        editor.recordUndoSnapshot()
                        lastHapticValue = value(for: selectedTool)
                        GrainHaptics.prepare()
                    },
                    onReset: {
                        resetSelectedToolToDefault()
                    }
                )

                Text(activeValueText)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GrainTheme.paper)
                    .frame(width: 52, alignment: .trailing)
            }
            .frame(height: 31)
        }
        .padding(.horizontal, 18)
        .padding(.top, 5)
        .padding(.bottom, 8)
        .background(GrainTheme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(GrainTheme.line).frame(height: 1)
        }
    }

    private var activeRange: ClosedRange<Double> {
        switch selectedTool {
        case .intensity: 0...200
        case .exposure: -2...2
        case .temperature: 3500...9000
        case .grain, .vignette, .fade, .sharpness: 0...100
        default: -100...100
        }
    }

    private var activeBinding: Binding<Double> {
        Binding(
            get: { value(for: selectedTool) },
            set: {
                setValue($0, for: selectedTool)
                editor.markManualAdjustment()
                editor.schedulePreview()
            }
        )
    }

    private var activeValueText: String {
        switch selectedTool {
        case .intensity:
            "\(Int(editor.intensity * 100))"
        case .exposure:
            String(format: "%+.1f", editor.settings.exposure)
        case .temperature:
            "\(Int(editor.settings.temperature))K"
        default:
            String(format: "%+.0f", value(for: selectedTool))
        }
    }

    private func tools(for category: AdjustCategory) -> [AdjustTool] {
        AdjustTool.allCases.filter { $0.category == category }
    }

    private func value(for tool: AdjustTool) -> Double {
        switch tool {
        case .intensity: editor.intensity * 100
        case .exposure: editor.settings.exposure
        case .contrast: editor.settings.contrast
        case .highlights: editor.settings.highlights
        case .shadows: editor.settings.shadows
        case .whites: editor.settings.whites
        case .blacks: editor.settings.blacks
        case .temperature: editor.settings.temperature
        case .tint: editor.settings.tint
        case .vibrance: editor.settings.vibrance
        case .saturation: editor.settings.saturation
        case .clarity: editor.settings.clarity
        case .sharpness: editor.settings.sharpness
        case .fade: editor.settings.fade
        case .grain: editor.settings.grain
        case .vignette: editor.settings.vignette
        }
    }

    private func setValue(_ value: Double, for tool: AdjustTool) {
        switch tool {
        case .intensity: editor.intensity = value / 100
        case .exposure: editor.settings.exposure = value
        case .contrast: editor.settings.contrast = value
        case .highlights: editor.settings.highlights = value
        case .shadows: editor.settings.shadows = value
        case .whites: editor.settings.whites = value
        case .blacks: editor.settings.blacks = value
        case .temperature: editor.settings.temperature = value
        case .tint: editor.settings.tint = value
        case .vibrance: editor.settings.vibrance = value
        case .saturation: editor.settings.saturation = value
        case .clarity: editor.settings.clarity = value
        case .sharpness: editor.settings.sharpness = value
        case .fade: editor.settings.fade = value
        case .grain: editor.settings.grain = value
        case .vignette: editor.settings.vignette = value
        }
    }

    private func emitSliderHaptic(for value: Double) {
        let step: Double
        switch selectedTool {
        case .exposure: step = 0.05
        case .temperature: step = 50
        case .intensity, .fade, .grain, .vignette, .sharpness: step = 2
        default: step = 5
        }
        guard !lastHapticValue.isNaN, abs(value - lastHapticValue) >= step else { return }
        lastHapticValue = value
        GrainHaptics.selection(enabled: hapticsEnabled)
    }

    private func resetSelectedToolToDefault() {
        let defaultValue = defaultValue(for: selectedTool)
        guard abs(value(for: selectedTool) - defaultValue) > 0.0001 else { return }
        editor.recordUndoSnapshot()
        setValue(defaultValue, for: selectedTool)
        editor.markManualAdjustment()
        lastHapticValue = defaultValue
        GrainHaptics.mediumImpact(enabled: hapticsEnabled)
        editor.schedulePreview()
    }

    private func defaultValue(for tool: AdjustTool) -> Double {
        if tool == .intensity {
            return editor.selectedProfile == .neutral ? 100 : 82
        }
        let defaults = editor.selectedProfile.factorySettings
        switch tool {
        case .intensity: return 0
        case .exposure: return defaults.exposure
        case .contrast: return defaults.contrast
        case .highlights: return defaults.highlights
        case .shadows: return defaults.shadows
        case .whites: return defaults.whites
        case .blacks: return defaults.blacks
        case .temperature: return defaults.temperature
        case .tint: return defaults.tint
        case .vibrance: return defaults.vibrance
        case .saturation: return defaults.saturation
        case .clarity: return defaults.clarity
        case .sharpness: return defaults.sharpness
        case .fade: return defaults.fade
        case .grain: return defaults.grain
        case .vignette: return defaults.vignette
        }
    }
}

/// 可双击白色旋钮恢复默认值的滑杆（编辑页与设置页共用，经极致优化，杜绝卡顿掉帧）
struct ResetValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditStart: () -> Void
    let onReset: () -> Void
    @State private var isEditing = false
    @State private var lastHapticStep: Int = 0
    @State private var dragKnobX: CGFloat? = nil
    @State private var lastTapTime: TimeInterval = 0
    @State private var startLocation: CGPoint = .zero

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let inset: CGFloat = 10
            let usableWidth = max(width - inset * 2, 1)
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let progress = min(max((value - range.lowerBound) / span, 0), 1)
            let defaultKnobX = inset + usableWidth * CGFloat(progress)
            let activeKnobX = dragKnobX ?? defaultKnobX

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(GrainTheme.track)
                    .frame(height: 4)

                Capsule()
                    .fill(GrainTheme.accent)
                    .frame(width: max(activeKnobX, 0), height: 4)

                Circle()
                    .fill(GrainTheme.knob)
                    .frame(width: 19, height: 19)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: activeKnobX - 9.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { gesture in
                        if !isEditing {
                            isEditing = true
                            startLocation = gesture.startLocation
                            GrainHaptics.prepare()
                            onEditStart()
                            lastHapticStep = Int(((value - range.lowerBound) / span * 50).rounded())
                        }
                        let position = min(max(gesture.location.x - inset, 0), usableWidth)
                        dragKnobX = inset + position
                        let newValue = range.lowerBound + Double(position / usableWidth) * span
                        let newStep = Int(((newValue - range.lowerBound) / span * 50).rounded())
                        if newStep != lastHapticStep {
                            lastHapticStep = newStep
                            if abs(newValue) < (span / 80) {
                                GrainHaptics.mediumImpact()
                            } else {
                                GrainHaptics.selection()
                            }
                        }
                        value = newValue
                    }
                    .onEnded { gesture in
                        isEditing = false
                        dragKnobX = nil
                        let dist = hypot(gesture.location.x - startLocation.x, gesture.location.y - startLocation.y)
                        if dist < 6 {
                            let now = Date().timeIntervalSince1970
                            if now - lastTapTime < 0.35 {
                                GrainHaptics.mediumImpact()
                                AudioServicesPlaySystemSound(1519)
                                onReset()
                                lastTapTime = 0
                            } else {
                                lastTapTime = now
                            }
                        }
                    }
            )
        }
        .frame(height: 31)
        .accessibilityElement()
        .accessibilityLabel("调整滑杆")
        .accessibilityHint("双击白色旋钮恢复当前参数默认值")
    }
}

private struct ExportSettingsSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    /// 表单实际高度：让 sheet 刚好包住内容，不再留出一条黑色空隙
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        Group {
            if let result = editor.exportResult {
                ExportResultSheet(result: result, savedToPhotos: editor.exportSavedToAlbum)
            } else {
                exportForm
            }
        }
        .presentationDetents([.height(contentHeight > 0 ? contentHeight + 46 : 600)])
        .presentationDragIndicator(.visible)
        .sheet(
            isPresented: sharingBinding,
            onDismiss: { editor.finishFileExportSharing() }
        ) {
            if let url = editor.exportShareURL {
                GrainShareSheet(items: [url])
                    .ignoresSafeArea()
            }
        }
    }

    private var sharingBinding: Binding<Bool> {
        Binding(
            get: { editor.exportShareURL != nil },
            set: { if !$0 { editor.exportShareURL = nil } }
        )
    }

    private var exportForm: some View {
            ZStack {
                GrainTheme.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("导出")
                            .font(.system(size: 25, weight: .bold, design: .serif))
                            .foregroundStyle(GrainTheme.paper)
                        Text("原始尺寸 · 最高质量")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(GrainTheme.raised, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GrainTheme.paper)
                }

                HStack(spacing: 0) {
                    ExportFact(value: editor.photo?.dimensionsLabel ?? "—", label: "像素")
                    Divider().overlay(GrainTheme.line).frame(height: 30)
                    ExportFact(value: editor.selectedProfile.shortName, label: "胶片")
                    Divider().overlay(GrainTheme.line).frame(height: 30)
                    ExportFact(value: editor.exportOptions.format.title, label: "格式")
                }
                .padding(.vertical, 12)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 9) {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            editor.exportOptions.format = format
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(format.title)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                Text(format.subtitle)
                                    .font(.system(size: 8.5, design: .rounded))
                                    .foregroundStyle(GrainTheme.muted)
                            }
                            .foregroundStyle(GrainTheme.paper)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(
                                        editor.exportOptions.format == format
                                            ? GrainTheme.accent
                                            : GrainTheme.line,
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("边框与标记")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(GrainTheme.muted)

                    HStack(spacing: 7) {
                        ForEach(ExportFrame.allCases) { frame in
                            Button {
                                editor.exportOptions.frame = frame
                            } label: {
                                VStack(spacing: 2) {
                                    Text(frame.title)
                                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                    Text(frame.subtitle)
                                        .font(.system(size: 7.5, design: .rounded))
                                        .foregroundStyle(GrainTheme.muted)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .foregroundStyle(GrainTheme.paper)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 11)
                                        .stroke(
                                            editor.exportOptions.frame == frame
                                                ? GrainTheme.accent
                                                : GrainTheme.line,
                                            lineWidth: 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(spacing: 9) {
                    Toggle(isOn: $editor.exportOptions.includeDateStamp) {
                        Text("在照片上写入拍摄日期")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    }
                    .tint(GrainTheme.accent)

                    HStack(spacing: 8) {
                        Image(systemName: "signature")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(GrainTheme.muted)
                        TextField("水印文字（留空则不添加）", text: $editor.exportOptions.watermark)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(GrainTheme.paper)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(GrainTheme.surface, in: RoundedRectangle(cornerRadius: 14))

                Toggle(isOn: $editor.exportOptions.keepLocation) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("保留地址信息")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text(editor.photo?.hasLocation == true ? "GPS 将写入导出文件" : "源文件未检测到 GPS")
                            .font(.system(size: 8.5, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                }
                .tint(GrainTheme.accent)
                .disabled(editor.photo?.hasLocation != true)

                Toggle(isOn: $editor.exportOptions.keepCameraMetadata) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("保留相机信息")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text("机身、镜头、快门与拍摄时间")
                            .font(.system(size: 8.5, design: .rounded))
                            .foregroundStyle(GrainTheme.muted)
                    }
                }
                .tint(GrainTheme.accent)

                if let message = editor.errorMessage {
                    Text(message)
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(GrainTheme.danger)
                        .lineLimit(2)
                }

                // 左：保存到文件；右：保存到相册（默认主操作）
                HStack(spacing: 10) {
                    ExportActionButton(
                        title: "保存到文件",
                        symbol: "folder",
                        isPrimary: false,
                        isLoading: editor.isExporting && editor.exportDestination == .files,
                        isEnabled: editor.canExport
                    ) {
                        editor.export(to: .files)
                    }

                    ExportActionButton(
                        title: "保存到相册",
                        symbol: "photo.badge.arrow.down",
                        isPrimary: true,
                        isLoading: editor.isExporting && editor.exportDestination == .photos,
                        isEnabled: editor.canExport
                    ) {
                        editor.export(to: .photos)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: ExportFormHeightKey.self,
                            value: proxy.size.height
                        )
                }
            }
            .onPreferenceChange(ExportFormHeightKey.self) { height in
                // 忽略布局过程中的临时小值，避免 sheet 高度来回跳
                guard height > 300, abs(height - contentHeight) > 0.5 else { return }
                contentHeight = height
            }
            }
    }
}

private struct ExportFormHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ExportActionButton: View {
    let title: String
    let symbol: String
    let isPrimary: Bool
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .tint(isPrimary ? GrainTheme.black : GrainTheme.paper)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(isLoading ? "处理中…" : title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isPrimary ? GrainTheme.black : GrainTheme.paper)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                isPrimary ? GrainTheme.paper : GrainTheme.raised,
                in: RoundedRectangle(cornerRadius: 15)
            )
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(GrainTheme.line, lineWidth: 0.9)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

private struct ExportFact: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(GrainTheme.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label)
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(GrainTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ExportResultSheet: View {
    let result: ExportResult
    let savedToPhotos: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GrainTheme.black.ignoresSafeArea()
            VStack(spacing: 17) {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(GrainTheme.accent)
                    .frame(width: 62, height: 62)
                    .background(GrainTheme.accent.opacity(0.12), in: Circle())

                VStack(spacing: 4) {
                    Text(savedToPhotos ? "已保存到相册" : "已导出文件")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                    Text("\(result.dimensions) · \(result.format.title) · 100%")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(GrainTheme.muted)
                }

                ShareLink(item: result.url) {
                    HStack {
                        Image(systemName: savedToPhotos ? "square.and.arrow.up" : "folder")
                        Text(savedToPhotos ? "再次存储或分享" : "存储到文件")
                        Spacer()
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(GrainTheme.black)
                    .padding(.horizontal, 17)
                    .frame(height: 50)
                    .background(GrainTheme.paper, in: RoundedRectangle(cornerRadius: 15))
                }

                Button("返回编辑") { dismiss() }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(GrainTheme.muted)
            }
            .padding(22)
        }
    }
}

struct IdentifiableVideoAsset: Identifiable {
    let id: String
    let asset: PHAsset

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
    }
}
