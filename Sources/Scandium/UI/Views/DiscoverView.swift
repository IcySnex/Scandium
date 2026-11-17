// DiscoverView.swift — Home screen built from SoundCloud's personalized sections
// Project: Scandium | Author: MeoHunter | License: GPL-3.0
//
// Mirrors soundcloud.com's home: the sections come from /mixed-selections
// ("Made for you", "Recently Played", "More of what you like", mixes,
// stations, ...). The feed loads once per launch; it only reloads when the
// reload button is tapped or the page is pulled down.

import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var scraper: ClientIDScraper

    let onNavigateToSearch: () -> Void
    let onNavigateToLibrary: () -> Void

    @ObservedObject private var store = DiscoverDataStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var showClientIDSheet: Bool = false
    @State private var openedItem: HomeItem?

    private static let cardSize: CGFloat = 148

    init(
        onNavigateToSearch: @escaping () -> Void = {},
        onNavigateToLibrary: @escaping () -> Void = {}
    ) {
        self.onNavigateToSearch = onNavigateToSearch
        self.onNavigateToLibrary = onNavigateToLibrary
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                headerView
                    .padding(.top, 8)

                likedSongsCard

                if let error = store.error {
                    homeErrorBanner(error)
                }

                if store.selections.isEmpty && store.isLoading {
                    ForEach(0..<3, id: \.self) { _ in shimmerSection }
                } else {
                    ForEach(store.selections) { selection in
                        selectionSection(selection)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 130) // Keep content clear of the mini player & tab bar
        }
        .refreshable {
            await store.reload(api: api)
        }
        .sheet(isPresented: $showClientIDSheet) {
            ClientIDConfigModal(scraper: scraper)
        }
        .sheet(item: $openedItem) { item in
            HomeItemDetailSheet(item: item)
                .environmentObject(api)
                .environmentObject(player)
                .environmentObject(library)
        }
        .task {
            await store.loadIfNeeded(api: api)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center) {
            Text(settings.loc("Trang chủ", "Home"))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(ScandiumTheme.textPrimary)

            Spacer()

            HStack(spacing: 10) {
                // Reload: refetches the home feed and re-syncs likes & playlists
                Button(action: {
                    Task { await store.reload(api: api) }
                }) {
                    Group {
                        if store.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: ScandiumTheme.textPrimary))
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundColor(ScandiumTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(ScandiumTheme.surfaceElevated)
                    .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(store.isLoading)

                Button(action: onNavigateToSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(ScandiumTheme.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { showClientIDSheet = true }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(scraper.lastError == nil ? ScandiumTheme.spotifyGreen : Color.orange)
                            .frame(width: 7, height: 7)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ScandiumTheme.textPrimary.opacity(0.85))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(ScandiumTheme.surfaceElevated)
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Liked Songs

    private var likedSongsCard: some View {
        Button(action: onNavigateToLibrary) {
            HStack(spacing: 12) {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.33, blue: 0.0), Color(red: 1.0, green: 0.55, blue: 0.2)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.loc("Bài hát đã thích", "Liked Songs"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ScandiumTheme.textPrimary)
                    Text("\(library.likedTracks.count) \(settings.loc("bài hát", "tracks"))")
                        .font(.system(size: 12))
                        .foregroundColor(ScandiumTheme.subtext)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ScandiumTheme.subtext)
                    .padding(.trailing, 12)
            }
            .background(ScandiumTheme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusSmall, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Sections

    private func selectionSection(_ selection: HomeSelection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                if let description = selection.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(ScandiumTheme.subtext)
                        .lineLimit(2)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(selection.items) { item in
                        Button(action: { openedItem = item }) {
                            switch item {
                            case .playlist(let playlist): playlistCard(playlist)
                            case .user(let user): userCard(user)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }

    private func playlistCard(_ playlist: HomePlaylist) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(
                url: playlist.highResArtworkURL,
                width: Self.cardSize,
                height: Self.cardSize,
                cornerRadius: 8
            )
            Text(playlist.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ScandiumTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !playlist.isSystemPlaylist, let username = playlist.user?.username {
                Text(username)
                    .font(.system(size: 12))
                    .foregroundColor(ScandiumTheme.subtext)
                    .lineLimit(1)
            }
        }
        .frame(width: Self.cardSize, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func userCard(_ user: SoundCloudUser) -> some View {
        VStack(spacing: 6) {
            CachedAsyncImage(
                url: user.avatarURL.flatMap { URL(string: Track.upgradeArtwork(urlString: $0, to: .t500x500)) },
                width: Self.cardSize,
                height: Self.cardSize,
                cornerRadius: Self.cardSize / 2
            )
            Text(user.username)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ScandiumTheme.textPrimary)
                .lineLimit(1)
            if let followers = user.followersCount {
                Text("\(followers) \(settings.loc("người theo dõi", "followers"))")
                    .font(.system(size: 12))
                    .foregroundColor(ScandiumTheme.subtext)
                    .lineLimit(1)
            }
        }
        .frame(width: Self.cardSize)
        .contentShape(Rectangle())
    }

    private var shimmerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.08))
                .frame(width: 160, height: 18)
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    ShimmerView()
                        .frame(width: Self.cardSize, height: Self.cardSize)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func homeErrorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(ScandiumTheme.subtext)
                .lineLimit(nil)

            Button(action: {
                Task { await store.reload(api: api) }
            }) {
                Text(settings.loc("Thử tải lại", "Retry"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ScandiumTheme.spotifyGreen)
                    .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScandiumTheme.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Playlist / Artist Detail Sheet

/// Shows the tracks behind a home card: every track of a playlist or mix, or
/// an artist's uploads.
struct HomeItemDetailSheet: View {
    let item: HomeItem

    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var library: LibraryManager
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private var title: String {
        switch item {
        case .playlist(let playlist): return playlist.title
        case .user(let user): return user.username
        }
    }

    private var subtitle: String? {
        switch item {
        case .playlist(let playlist):
            return playlist.isSystemPlaylist ? playlist.description : playlist.user?.username
        case .user(let user):
            return user.fullName
        }
    }

    private var artworkURL: URL? {
        switch item {
        case .playlist(let playlist): return playlist.highResArtworkURL
        case .user(let user): return user.avatarURL.flatMap { URL(string: Track.upgradeArtwork(urlString: $0, to: .t500x500)) }
        }
    }

    private var isUser: Bool {
        if case .user = item { return true }
        return false
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 16) {
                            CachedAsyncImage(url: artworkURL, width: 110, height: 110, cornerRadius: isUser ? 55 : 10)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(title)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                    .lineLimit(2)
                                if let subtitle = subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.system(size: 13))
                                        .foregroundColor(ScandiumTheme.subtext)
                                        .lineLimit(3)
                                }
                                if !isLoading {
                                    Text("\(tracks.count) \(settings.loc("bài hát", "tracks"))")
                                        .font(.system(size: 13))
                                        .foregroundColor(ScandiumTheme.subtext)
                                }
                            }
                        }
                        .padding(.top, 10)

                        if !tracks.isEmpty {
                            HStack(spacing: 12) {
                                actionButton(icon: "play.fill", title: settings.loc("Phát tất cả", "Play All"), primary: true) {
                                    player.playQueue(tracks, startingAt: 0)
                                    presentationMode.wrappedValue.dismiss()
                                }
                                actionButton(icon: "shuffle", title: settings.loc("Trộn bài", "Shuffle"), primary: false) {
                                    player.playQueue(tracks.shuffled(), startingAt: 0)
                                    presentationMode.wrappedValue.dismiss()
                                }
                            }
                        }

                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: ScandiumTheme.spotifyGreen))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 30)
                        } else if let loadError = loadError {
                            Text(loadError)
                                .font(.system(size: 13))
                                .foregroundColor(ScandiumTheme.subtext)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 30)
                        } else {
                            LazyVStack(spacing: 4) {
                                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                                    GlassTrackRow(
                                        track: track,
                                        isCurrentlyPlaying: player.currentTrack?.id == track.id,
                                        onTap: { player.playQueue(tracks, startingAt: index) }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.loc("Đóng", "Close")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(ScandiumTheme.spotifyGreen)
                }
            }
        }
        .task { await load() }
    }

    private func actionButton(icon: String, title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(primary ? .white : ScandiumTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(primary ? ScandiumTheme.spotifyGreen : ScandiumTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }

    @MainActor
    private func load() async {
        guard isLoading else { return }
        let token = SoundCloudAuthManager.shared.oauthToken
        do {
            switch item {
            case .playlist(let playlist):
                // Show the embedded first tracks right away, then the full list
                if !playlist.tracks.isEmpty { tracks = playlist.tracks }
                tracks = try await api.getPlaylistTracks(playlist, oauthToken: token)
            case .user(let user):
                tracks = try await api.getUserTracks(userID: user.id, oauthToken: token)
            }
        } catch {
            if tracks.isEmpty {
                loadError = settings.loc("Không tải được bài hát.", "Couldn't load tracks.")
            }
        }
        isLoading = false
    }
}

// MARK: - Discover Data Store (persists across tab switches)

final class DiscoverDataStore: ObservableObject {
    static let shared = DiscoverDataStore()

    @Published private(set) var selections: [HomeSelection] = []
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    /// The feed is fetched once per launch; afterwards only `reload` refetches.
    private var didLoadThisLaunch = false

    private static var cacheFile: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("scandium_home_mixed_selections.json")
    }

    private init() {
        // Old search-based feed cache, no longer used
        UserDefaults.standard.removeObject(forKey: "scandium_discover_cached_payload_v1")

        if let file = Self.cacheFile,
           let data = try? Data(contentsOf: file),
           let cached = try? SoundCloudAPI.decodeSelections(data) {
            selections = cached
        }
    }

    @MainActor
    func loadIfNeeded(api: SoundCloudAPI) async {
        guard !didLoadThisLaunch else { return }
        didLoadThisLaunch = true
        await fetchFeed(api: api)
    }

    /// Refetches the home feed and re-syncs the library (likes & playlists).
    @MainActor
    func reload(api: SoundCloudAPI) async {
        guard !isLoading else { return }
        didLoadThisLaunch = true
        async let feed: Void = fetchFeed(api: api)
        async let library: Void = SoundCloudAuthManager.shared.syncLibrary()
        _ = await (feed, library)
    }

    @MainActor
    private func fetchFeed(api: SoundCloudAPI) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let data = try await api.getMixedSelectionsData(oauthToken: SoundCloudAuthManager.shared.oauthToken)
            let fresh = try SoundCloudAPI.decodeSelections(data)
            guard !fresh.isEmpty else { throw APIError.invalidResponse }
            selections = fresh
            if let file = Self.cacheFile {
                try? data.write(to: file, options: .atomic)
            }
        } catch {
            if selections.isEmpty {
                self.error = AppSettings.shared.loc(
                    "Không tải được trang chủ. Hãy đăng nhập SoundCloud hoặc thử lại.",
                    "Couldn't load your home feed. Sign in to SoundCloud or try again."
                )
            }
        }
    }
}

// MARK: - Client ID Config Modal

struct ClientIDConfigModal: View {
    @ObservedObject var scraper: ClientIDScraper
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var inputID: String = ""
    @State private var isRefreshing: Bool = false
    @State private var showGuideSheet: Bool = false
    @State private var statusToast: String?

    init(scraper: ClientIDScraper) {
        self.scraper = scraper
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScandiumTheme.bgPrimary.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Status Card
                        HStack(spacing: 12) {
                            Circle()
                                .fill(scraper.lastError == nil ? ScandiumTheme.spotifyGreen : Color.orange)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(settings.loc("Trạng thái Token dịch vụ (Client ID)", "Service Token / Client ID Status"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                Text(scraper.statusDescription)
                                    .font(.system(size: 12))
                                    .foregroundColor(ScandiumTheme.subtext)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(ScandiumTheme.surfaceDark)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        // Current ID info
                        if let current = scraper.currentClientID {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(settings.loc("Token hiện hành:", "Current Token:"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(ScandiumTheme.subtext)
                                Text(current)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ScandiumTheme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }

                        // Auto scrape button
                        Button(action: {
                            guard !isRefreshing else { return }
                            isRefreshing = true
                            Task {
                                do {
                                    try await scraper.refreshClientID()
                                    await MainActor.run {
                                        isRefreshing = false
                                        statusToast = settings.loc("Làm mới Token thành công!", "Refreshed Token successfully!")
                                    }
                                } catch {
                                    await MainActor.run {
                                        isRefreshing = false
                                        statusToast = "\(settings.loc("Lỗi", "Error")): \(error.localizedDescription)"
                                    }
                                }
                            }
                        }) {
                            HStack {
                                if isRefreshing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: ScandiumTheme.textPrimary))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(settings.loc("Tự động làm mới Client ID", "Auto-Refresh Client ID"))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(ScandiumTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(ScandiumTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        HairlineDivider()

                        // Manual Entry
                        VStack(alignment: .leading, spacing: 8) {
                            Text(settings.loc("Cấu hình Client ID thủ công", "Manual Client ID Config"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(ScandiumTheme.textPrimary)

                            TextField(settings.loc("Dán chuỗi 32 ký tự...", "Paste 32-character key..."), text: $inputID)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(ScandiumTheme.textPrimary)
                                .padding(12)
                                .background(ScandiumTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            HStack(spacing: 10) {
                                Button(action: {
                                    scraper.setManualClientID(inputID)
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    Text(settings.loc("Lưu Client ID", "Save Client ID"))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
                                        .background(ScandiumTheme.spotifyGreen)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                if scraper.manualClientID != nil {
                                    Button(action: {
                                        scraper.setManualClientID(nil)
                                        inputID = ""
                                        presentationMode.wrappedValue.dismiss()
                                    }) {
                                        Text(settings.loc("Khôi phục", "Reset"))
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(ScandiumTheme.textPrimary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 40)
                                            .background(ScandiumTheme.surfaceElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }

                        // Guide button
                        Button(action: {
                            showGuideSheet = true
                        }) {
                            HStack {
                                Image(systemName: "questionmark.circle")
                                Text(settings.loc("Xem hướng dẫn lấy Client ID trên máy tính", "How to extract Client ID from PC"))
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(ScandiumTheme.subtext)
                        }
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(settings.loc("Cấu hình dịch vụ", "Service Configuration"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.loc("Đóng", "Close")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(ScandiumTheme.textPrimary)
                }
            }
            .sheet(isPresented: $showGuideSheet) {
                ClientIDGuideSheet()
            }
            .onAppear {
                if let manual = scraper.manualClientID {
                    inputID = manual
                }
            }
        }
        .preferredColorScheme(settings.themeMode.colorScheme)
    }
}
