import SwiftUI
import UniformTypeIdentifiers

// MARK: - 文件目录视频管理与浏览视图 (含长按多选、批量操作、子文件夹)

public struct FileDirectoryView: View {
    @ObservedObject var fileService = FileManagerService.shared
    public var onSelectVideo: (VideoItem) -> Void
    public var onShowInfo: (VideoItem) -> Void

    @State private var showDocumentPicker = false
    @State private var showCreateFolderAlert = false
    @State private var newFolderName = ""
    @State private var showRenameAlert = false
    @State private var renamingVideo: VideoItem? = nil
    @State private var newVideoTitle = ""
    @State private var moveTargetVideo: VideoItem? = nil
    @State private var showMoveSheet = false
    @State private var sortOption: SortOption = .dateDesc

    // 多选状态
    @State private var isMultiSelecting = false
    @State private var selectedVideoPaths = Set<String>()
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var shareURLs: [URL] = []

    public init(onSelectVideo: @escaping (VideoItem) -> Void, onShowInfo: @escaping (VideoItem) -> Void) {
        self.onSelectVideo = onSelectVideo
        self.onShowInfo = onShowInfo
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部路径面包屑与操作工具条
            directoryHeaderBar

            // 文件列表内容
            ScrollView {
                VStack(spacing: 16) {
                    // 若在根目录且非多选状态，展示文件夹分类
                    if fileService.currentFolder == nil && !fileService.folders.isEmpty && !isMultiSelecting {
                        foldersSection
                    }

                    // 视频文件列表
                    videosSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .refreshable {
                await fileService.reloadAll()
            }
        }
        .overlay(alignment: .bottom) {
            if isMultiSelecting {
                multiSelectBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            if fileService.rootVideos.isEmpty {
                await fileService.reloadAll()
            }
        }
        // 系统文件选择器
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie],
            allowsMultipleSelection: true
        ) { result in
            handleImportResult(result)
        }
        // 新建文件夹弹窗
        .alert("新建文件夹", isPresented: $showCreateFolderAlert) {
            TextField("输入文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) { newFolderName = "" }
            Button("创建") {
                try? fileService.createFolder(named: newFolderName)
                newFolderName = ""
                Task { await fileService.reloadAll() }
            }
        }
        // 重命名视频弹窗
        .alert("重命名视频", isPresented: $showRenameAlert) {
            TextField("输入新名称", text: $newVideoTitle)
            Button("取消", role: .cancel) { renamingVideo = nil }
            Button("确定") {
                if let video = renamingVideo {
                    Task {
                        try? await fileService.renameVideo(item: video, newTitle: newVideoTitle)
                        renamingVideo = nil
                    }
                }
            }
        }
        // 批量删除确认弹窗
        .confirmationDialog(
            "确定要删除所选的 \(selectedVideoPaths.count) 个视频吗？",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除视频", role: .destructive) {
                deleteSelectedVideos()
            }
            Button("取消", role: .cancel) {}
        }
        // 移动到文件夹 Sheet
        .sheet(isPresented: $showMoveSheet) {
            MoveToFolderSheet(video: moveTargetVideo, folders: fileService.folders) { targetFolder in
                if let video = moveTargetVideo {
                    Task {
                        if let folder = targetFolder {
                            let dest = folder.url.appendingPathComponent(URL(fileURLWithPath: video.id).lastPathComponent)
                            try? FileManager.default.moveItem(at: URL(fileURLWithPath: video.id), to: dest)
                        } else {
                            let dest = fileService.videosDirectory.appendingPathComponent(URL(fileURLWithPath: video.id).lastPathComponent)
                            try? FileManager.default.moveItem(at: URL(fileURLWithPath: video.id), to: dest)
                        }
                        await fileService.reloadAll()
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            GrainShareSheet(items: shareURLs)
        }
    }

    // MARK: - 顶部导航与工具栏

    private var directoryHeaderBar: some View {
        HStack {
            // 返回上级或根目录
            if let currentFolder = fileService.currentFolder {
                Button(action: {
                    Task { await fileService.enterFolder(nil) }
                    GrainHaptics.selection()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("根目录 / \(currentFolder.name)")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(GrainTheme.accent)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(GrainTheme.accent)
                    Text("文件目录")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(GrainTheme.paper)
                }
            }

            Spacer()

            // 多选开关按钮
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isMultiSelecting.toggle()
                    if !isMultiSelecting {
                        selectedVideoPaths.removeAll()
                    }
                }
                GrainHaptics.selection()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isMultiSelecting ? "checkmark.circle.fill" : "checklist")
                    Text(isMultiSelecting ? "完成" : "多选")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isMultiSelecting ? GrainTheme.black : GrainTheme.paper)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isMultiSelecting ? GrainTheme.accent : GrainTheme.surface)
                .clipShape(Capsule())
            }

            // 新建文件夹按钮
            if fileService.currentFolder == nil && !isMultiSelecting {
                Button(action: { showCreateFolderAlert = true }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(GrainTheme.paper)
                        .frame(width: 32, height: 32)
                        .background(GrainTheme.surface)
                        .clipShape(Circle())
                }
            }

            // 导入外部文件按钮
            if !isMultiSelecting {
                Button(action: { showDocumentPicker = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(GrainTheme.paper)
                        .frame(width: 32, height: 32)
                        .background(GrainTheme.surface)
                        .clipShape(Circle())
                }
            }

            // 排序菜单
            Menu {
                ForEach(SortOption.allCases) { opt in
                    Button(action: {
                        sortOption = opt
                        GrainHaptics.selection()
                    }) {
                        HStack {
                            Text(opt.rawValue)
                            if sortOption == opt { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(GrainTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(GrainTheme.surface)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(GrainTheme.surface.opacity(0.4))
    }

    // MARK: - 文件夹区域

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文件夹")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(GrainTheme.muted)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(fileService.folders) { folder in
                    Button(action: {
                        Task { await fileService.enterFolder(folder) }
                        GrainHaptics.selection()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 24))
                                .foregroundColor(GrainTheme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(GrainTheme.paper)
                                    .lineLimit(1)
                                Text("\(folder.itemCount) 个视频")
                                    .font(.system(size: 11))
                                    .foregroundColor(GrainTheme.muted)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .grainCard(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive, action: {
                            try? fileService.deleteFolder(folder)
                            Task { await fileService.reloadAll() }
                        }) {
                            Label("删除文件夹", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 视频文件列表

    private var videosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(fileService.currentFolder != nil ? "文件夹内视频" : "视频文件")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(GrainTheme.muted)
                Spacer()
                Text("共 \(sortedVideos.count) 个")
                    .font(.system(size: 12))
                    .foregroundColor(GrainTheme.muted)
            }

            if sortedVideos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 40))
                        .foregroundColor(GrainTheme.muted.opacity(0.5))
                    Text("暂无视频文件")
                        .font(.system(size: 14))
                        .foregroundColor(GrainTheme.muted)
                    Text("可通过电脑 Finder / iTunes 共享直接拷入，或点上方按钮从「文件」App 导入")
                        .font(.system(size: 12))
                        .foregroundColor(GrainTheme.muted.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(sortedVideos) { video in
                    let isSelected = selectedVideoPaths.contains(video.id)
                    FileVideoRow(
                        video: video,
                        isMultiSelecting: isMultiSelecting,
                        isSelected: isSelected,
                        onTap: {
                            if isMultiSelecting {
                                toggleSelection(for: video.id)
                            } else {
                                onSelectVideo(video)
                            }
                        },
                        onLongPress: {
                            if !isMultiSelecting {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    isMultiSelecting = true
                                    selectedVideoPaths.insert(video.id)
                                }
                                GrainHaptics.medium()
                            }
                        },
                        onInfo: { onShowInfo(video) },
                        onRename: {
                            renamingVideo = video
                            newVideoTitle = video.title
                            showRenameAlert = true
                        },
                        onMove: {
                            moveTargetVideo = video
                            showMoveSheet = true
                        },
                        onDelete: {
                            Task {
                                try? await fileService.deleteVideo(item: video)
                            }
                        }
                    )
                }
            }
        }
    }

    private var sortedVideos: [VideoItem] {
        let list = fileService.currentFolderVideos
        switch sortOption {
        case .dateDesc:
            return list.sorted(by: { $0.metadata.creationDate > $1.metadata.creationDate })
        case .dateAsc:
            return list.sorted(by: { $0.metadata.creationDate < $1.metadata.creationDate })
        case .sizeDesc:
            return list.sorted(by: { $0.metadata.fileSize > $1.metadata.fileSize })
        case .durationDesc:
            return list.sorted(by: { $0.metadata.duration > $1.metadata.duration })
        case .nameAsc:
            return list.sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
        }
    }

    private func toggleSelection(for path: String) {
        if selectedVideoPaths.contains(path) {
            selectedVideoPaths.remove(path)
        } else {
            selectedVideoPaths.insert(path)
        }
        GrainHaptics.selection()
    }

    // MARK: - 多选悬浮底栏

    private var multiSelectBottomBar: some View {
        HStack(spacing: 20) {
            Button(action: {
                if selectedVideoPaths.count == sortedVideos.count {
                    selectedVideoPaths.removeAll()
                } else {
                    selectedVideoPaths = Set(sortedVideos.map(\.id))
                }
                GrainHaptics.selection()
            }) {
                Text(selectedVideoPaths.count == sortedVideos.count ? "取消全选" : "全选")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(GrainTheme.paper)
            }

            Spacer()

            Text("已选 \(selectedVideoPaths.count) 个")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(GrainTheme.accent)

            Spacer()

            // 批量分享
            Button(action: {
                let urls = selectedVideoPaths.map { URL(fileURLWithPath: $0) }
                self.shareURLs = urls
                self.showShareSheet = true
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(selectedVideoPaths.isEmpty ? GrainTheme.muted : GrainTheme.paper)
            }
            .disabled(selectedVideoPaths.isEmpty)

            // 批量删除
            Button(action: { showDeleteConfirmation = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(selectedVideoPaths.isEmpty ? GrainTheme.muted : GrainTheme.danger)
            }
            .disabled(selectedVideoPaths.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(GrainTheme.hudBackground)
        .grainGlass(cornerRadius: 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func deleteSelectedVideos() {
        let pathsToDelete = Array(selectedVideoPaths)
        Task {
            for path in pathsToDelete {
                try? FileManager.default.removeItem(atPath: path)
            }
            selectedVideoPaths.removeAll()
            isMultiSelecting = false
            await fileService.reloadAll()
            GrainHaptics.success()
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            Task {
                for url in urls {
                    try? await fileService.importExternalFile(from: url, toFolder: fileService.currentFolder)
                }
            }
        }
    }
}

// MARK: - 文件视频行条目 (支持长按多选)

struct FileVideoRow: View {
    let video: VideoItem
    let isMultiSelecting: Bool
    let isSelected: Bool
    var onTap: () -> Void
    var onLongPress: () -> Void
    var onInfo: () -> Void
    var onRename: () -> Void
    var onMove: () -> Void
    var onDelete: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 多选勾选圆圈
                if isMultiSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(isSelected ? GrainTheme.accent : GrainTheme.muted)
                }

                // 16:9 无畸变固定画幅缩略图
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay(
                            ZStack {
                                GrainTheme.card
                                if let thumbnail {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .clipped()
                                } else {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(GrainTheme.accent)
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(video.durationFormatted)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(3)
                        .padding(3)
                }
                .frame(width: 88, height: 50)

                // 详情
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(GrainTheme.paper)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(video.fileSizeFormatted)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(GrainTheme.muted)

                        if !video.metadata.resolutionPill.isEmpty {
                            Text(video.metadata.resolutionPill)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(GrainTheme.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(GrainTheme.accent.opacity(0.15))
                                .cornerRadius(3)
                        }

                        if video.metadata.isHDR {
                            Text("HDR")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.yellow.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }

                    Text(FormatUtils.formatDate(video.metadata.creationDate))
                        .font(.system(size: 10))
                        .foregroundColor(GrainTheme.muted.opacity(0.8))
                }

                Spacer()

                if !isMultiSelecting {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GrainTheme.muted.opacity(0.4))
                }
            }
            .padding(10)
            .grainCard(cornerRadius: 12, strokeColor: isSelected ? GrainTheme.accent : GrainTheme.line)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    onLongPress()
                }
        )
        .contextMenu {
            if !isMultiSelecting {
                Button(action: onTap) { Label("立即播放", systemImage: "play.fill") }
                Button(action: onInfo) { Label("视频详细参数", systemImage: "info.circle") }
                Button(action: onLongPress) { Label("多选", systemImage: "checklist") }
                Button(action: onMove) { Label("移动到文件夹...", systemImage: "folder") }
                Button(action: onRename) { Label("重命名", systemImage: "pencil") }
                Button(role: .destructive, action: onDelete) { Label("删除视频", systemImage: "trash") }
            }
        }
        .task {
            if case .fileDirectory(let url, _) = video.source {
                self.thumbnail = await FileManagerService.shared.generateThumbnail(for: url)
            }
        }
    }
}

// MARK: - 移动到文件夹选择 Sheet

struct MoveToFolderSheet: View {
    let video: VideoItem?
    let folders: [VideoFolder]
    var onSelectFolder: (VideoFolder?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                GrainTheme.black.ignoresSafeArea()

                List {
                    Button(action: {
                        onSelectFolder(nil)
                        dismiss()
                    }) {
                        Label("根目录 (Videos)", systemImage: "folder")
                            .foregroundColor(GrainTheme.paper)
                    }
                    .listRowBackground(GrainTheme.surface)

                    ForEach(folders) { folder in
                        Button(action: {
                            onSelectFolder(folder)
                            dismiss()
                        }) {
                            Label(folder.name, systemImage: "folder.fill")
                                .foregroundColor(GrainTheme.paper)
                        }
                        .listRowBackground(GrainTheme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("移动到文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") { dismiss() }
                        .foregroundColor(GrainTheme.accent)
                }
            }
        }
    }
}
