import Photos
import SwiftUI

// MARK: - 相册目录视频浏览视图

public struct PhotoLibraryView: View {
    @ObservedObject var libraryService = PhotoLibraryService.shared
    public var onSelectVideo: (VideoItem) -> Void
    public var onShowInfo: (VideoItem) -> Void

    @State private var sortOption: SortOption = .dateDesc
    @State private var searchText = ""

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    public init(onSelectVideo: @escaping (VideoItem) -> Void, onShowInfo: @escaping (VideoItem) -> Void) {
        self.onSelectVideo = onSelectVideo
        self.onShowInfo = onShowInfo
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 权限未授权引导
            if libraryService.authorizationStatus != .authorized && libraryService.authorizationStatus != .limited {
                permissionPromptView
            } else {
                // 相册横滑分类选择栏
                albumCategoryBar

                // 视频网格与内容
                ScrollView {
                    VStack(spacing: 16) {
                        // 筛选与排序条
                        filterAndCountBar

                        if filteredVideos.isEmpty {
                            emptyStateView
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(filteredVideos) { video in
                                    PhotoVideoCard(
                                        video: video,
                                        onTap: { onSelectVideo(video) },
                                        onInfo: { onShowInfo(video) },
                                        onDelete: {
                                            Task {
                                                try? await libraryService.deleteVideo(item: video)
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 30)
                        }
                    }
                    .padding(.top, 10)
                }
                .refreshable {
                    await libraryService.reloadAlbumsAndVideos()
                }
            }
        }
        .task {
            if libraryService.authorizationStatus == .authorized || libraryService.authorizationStatus == .limited {
                await libraryService.reloadAlbumsAndVideos()
            }
        }
    }

    // MARK: - 相册分类横滑条

    private var albumCategoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(libraryService.albums) { album in
                    let isSelected = libraryService.selectedAlbumId == album.id
                    Button(action: {
                        Task {
                            await libraryService.selectAlbum(id: album.id)
                        }
                        GrainHaptics.selection()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: album.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(album.title)
                                .font(.system(size: 13, weight: .medium))
                            Text("\(album.count)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(isSelected ? GrainTheme.accent : GrainTheme.muted)
                        }
                        .foregroundColor(isSelected ? GrainTheme.paper : GrainTheme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isSelected ? GrainTheme.raised : GrainTheme.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? GrainTheme.accent.opacity(0.8) : GrainTheme.line, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(GrainTheme.surface.opacity(0.5))
    }

    // MARK: - 筛选与排序栏

    private var filterAndCountBar: some View {
        HStack {
            Text("共 \(filteredVideos.count) 个视频")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(GrainTheme.muted)

            Spacer()

            Menu {
                ForEach(SortOption.allCases) { opt in
                    Button(action: {
                        sortOption = opt
                        GrainHaptics.selection()
                    }) {
                        HStack {
                            Text(opt.rawValue)
                            if sortOption == opt {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOption.rawValue)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(GrainTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(GrainTheme.surface)
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
    }

    private var filteredVideos: [VideoItem] {
        var result = libraryService.currentAlbumVideos
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortOption {
        case .dateDesc:
            return result.sorted(by: { $0.metadata.creationDate > $1.metadata.creationDate })
        case .dateAsc:
            return result.sorted(by: { $0.metadata.creationDate < $1.metadata.creationDate })
        case .sizeDesc:
            return result.sorted(by: { $0.metadata.fileSize > $1.metadata.fileSize })
        case .durationDesc:
            return result.sorted(by: { $0.metadata.duration > $1.metadata.duration })
        case .nameAsc:
            return result.sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
        }
    }

    // MARK: - 空状态与权限引导

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 42))
                .foregroundColor(GrainTheme.muted.opacity(0.6))
            Text("当前相册暂无视频")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(GrainTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var permissionPromptView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 50))
                .foregroundColor(GrainTheme.accent)

            Text("需要访问您的照片图库")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(GrainTheme.paper)

            Text("GRAIN Player 需要相册读取权限以浏览并播放所有相册视频，包括隐藏相册。")
                .font(.system(size: 14))
                .foregroundColor(GrainTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: {
                Task {
                    _ = await libraryService.requestAuthorization()
                }
            }) {
                Text("授权访问照片")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(GrainTheme.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(GrainTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 48)
            .padding(.top, 8)

            Spacer()
        }
    }
}

// MARK: - 相册视频卡片

struct PhotoVideoCard: View {
    let video: VideoItem
    var onTap: () -> Void
    var onInfo: () -> Void
    var onDelete: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // 缩略图区域
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                        } else {
                            Rectangle()
                                .fill(GrainTheme.surface)
                                .aspectRatio(16/9, contentMode: .fit)
                                .overlay(
                                    Image(systemName: "play.circle")
                                        .font(.system(size: 26))
                                        .foregroundColor(GrainTheme.muted.opacity(0.5))
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(10)

                    // 底部时长与规格徽标
                    HStack(spacing: 4) {
                        Text(video.durationFormatted)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(4)

                        if !video.metadata.resolutionPill.isEmpty {
                            Text(video.metadata.resolutionPill)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(GrainTheme.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.75))
                                .cornerRadius(3)
                        }

                        Spacer()
                    }
                    .padding(6)
                }

                // 标题与日期
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(GrainTheme.paper)
                        .lineLimit(1)

                    Text(FormatUtils.formatDate(video.metadata.creationDate))
                        .font(.system(size: 11))
                        .foregroundColor(GrainTheme.muted)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            .grainCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onTap) {
                Label("立即播放", systemImage: "play.fill")
            }
            Button(action: onInfo) {
                Label("视频详细参数", systemImage: "info.circle")
            }
            Button(role: .destructive, action: onDelete) {
                Label("从相册删除", systemImage: "trash")
            }
        }
        .task {
            PhotoLibraryService.shared.requestThumbnail(for: video) { img in
                self.thumbnail = img
            }
        }
    }
}
