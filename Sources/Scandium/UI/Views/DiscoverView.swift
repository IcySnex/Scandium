// DiscoverView.swift — Home screen built from SoundCloud's personalized sections
// Project: Scandium | Author: MeoHunter | License: GPL-3.0
//
// Mirrors soundcloud.com's home: the sections come from /mixed-selections
// ("Made for you", "Recently Played", "More of what you like", mixes,
// stations, ...). The feed loads once per launch; it only reloads when the
// page is pulled down.

import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var library: LibraryManager

    let onNavigateToLibrary: () -> Void

    @ObservedObject private var store = DiscoverDataStore.shared

    private static let cardSize: CGFloat = 148

    init(onNavigateToLibrary: @escaping () -> Void = {}) {
        self.onNavigateToLibrary = onNavigateToLibrary
    }

    var body: some View {
        // A List, because on iOS 15 pull-to-refresh only works on lists
        List {
            likedSongsCard
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .homeRow()

            if let error = store.error {
                homeErrorBanner(error)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .homeRow()
            }

            if store.selections.isEmpty && store.isLoading {
                ForEach(0..<3, id: \.self) { _ in
                    shimmerSection
                        .padding(.vertical, 12)
                        .homeRow()
                }
            } else {
                ForEach(store.selections) { selection in
                    selectionSection(selection)
                        .padding(.vertical, 12)
                        .homeRow()
                }
            }

            MiniPlayerSpacerRow()
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Home")
        // Pull down to refetch the feed and re-sync likes & playlists
        .refreshable {
            await store.reload(api: api)
        }
        .task {
            await store.loadIfNeeded(api: api)
        }
        // Retry a failed load when the app comes back to the foreground
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await store.loadIfNeeded(api: api) }
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
                    Text("Liked Songs")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ScandiumTheme.textPrimary)
                    Text("\(library.likedTracks.count) tracks")
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
            .padding(.horizontal, 16)

            // Edge to edge: the row scrolls under the screen edges while its
            // first card lines up with the 16pt content margin.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(selection.items) { item in
                        NavigationLink(destination: TrackCollectionView(homeItem: item)) {
                            switch item {
                            case .playlist(let playlist): playlistCard(playlist)
                            case .user(let user): userCard(user)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
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
                Text("\(followers) followers")
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
                .fill(ScandiumTheme.surfaceElevated)
                .frame(width: 160, height: 18)
                .padding(.horizontal, 16)
            // Scrolls like the real rows so the placeholders never widen the
            // page beyond the screen (3 cards don't fit on a 4" iPhone).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { _ in
                        ShimmerView()
                            .frame(width: Self.cardSize, height: Self.cardSize)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
            }
            .disabled(true)
        }
    }

    private func homeErrorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(ScandiumTheme.subtext)
                .lineLimit(nil)

            Button("Retry") {
                Task { await store.reload(api: api) }
            }
            .buttonStyle(BorderedButtonStyle())
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScandiumTheme.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Discover Data Store (persists across tab switches)

final class DiscoverDataStore: ObservableObject {
    static let shared = DiscoverDataStore()

    @Published private(set) var selections: [HomeSelection] = []
    @Published private(set) var isLoading: Bool = false
    @Published var error: String?

    /// The feed is fetched once per launch (until it succeeds); afterwards
    /// only `reload` refetches.
    private var didLoadThisLaunch = false
    /// The running fetch. The store owns it rather than the view, so the view
    /// disappearing (which cancels its own task) can't cancel the request.
    private var feedTask: Task<Void, Never>?

    private static let cacheName = "scandium_home_mixed_selections.json"

    private static var cacheFile: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheName)
    }

    private init() {
        // Old search-based feed cache, no longer used
        UserDefaults.standard.removeObject(forKey: "scandium_discover_cached_payload_v1")

        // A test build kept the feed in Application Support; it belongs in Caches
        if let stray = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Self.cacheName) {
            try? FileManager.default.removeItem(at: stray)
        }

        if let file = Self.cacheFile,
           let data = try? Data(contentsOf: file),
           let cached = try? SoundCloudAPI.decodeSelections(data) {
            selections = cached
        }
    }

    /// Loads the feed unless it already loaded this launch. Called whenever
    /// Home appears and when the app returns to the foreground, so a failed
    /// load is retried.
    @MainActor
    func loadIfNeeded(api: SoundCloudAPI) async {
        guard !didLoadThisLaunch else { return }
        await loadFeed(api: api)
    }

    /// Refetches the home feed and re-syncs the library (likes & playlists).
    @MainActor
    func reload(api: SoundCloudAPI) async {
        async let feed: Void = loadFeed(api: api)
        async let library: Void = SoundCloudAuthManager.shared.syncLibrary()
        _ = await (feed, library)
    }

    /// Joins the running fetch, or starts one.
    @MainActor
    private func loadFeed(api: SoundCloudAPI) async {
        if feedTask == nil {
            feedTask = Task { @MainActor in
                // A launch can hit a moment where the network isn't ready
                // yet; try once more before showing an error
                if await !self.fetchFeed(api: api, showsError: false) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await self.fetchFeed(api: api, showsError: true)
                }
                self.feedTask = nil
            }
        }
        // Awaiting the value doesn't pass this caller's cancellation on
        let task = feedTask
        await task?.value
    }

    /// Returns whether the feed loaded. Errors are only shown when
    /// `showsError` is set (the last attempt), and never for cancellations.
    @MainActor
    @discardableResult
    private func fetchFeed(api: SoundCloudAPI, showsError: Bool) async -> Bool {
        isLoading = true
        if showsError { error = nil }
        defer { isLoading = false }

        let token = SoundCloudAuthManager.shared.oauthToken
        do {
            let data: Data
            do {
                data = try await api.getMixedSelectionsData(oauthToken: token)
            } catch APIError.httpError(let code) where token != nil && (code == 401 || code == 403) {
                // The sign-in was rejected: show the public feed instead of nothing
                self.error = "SoundCloud rejected your sign-in (HTTP \(code)), so this isn't your personal feed. Sign in again in Profile."
                data = try await api.getMixedSelectionsData(oauthToken: nil)
            }
            let fresh = try SoundCloudAPI.decodeSelections(data)
            guard !fresh.isEmpty else { throw APIError.invalidResponse }
            selections = fresh
            didLoadThisLaunch = true
            error = nil
            if let file = Self.cacheFile {
                try? data.write(to: file, options: .atomic)
            }
            return true
        } catch where error.isCancellation {
            // Not a real failure: the next appearance tries again
            return false
        } catch {
            if showsError && selections.isEmpty {
                self.error = "Couldn't load your home feed: \(error.localizedDescription)"
            }
            return false
        }
    }
}

private extension View {
    /// A full-width Home row without separators or a tap highlight
    func homeRow() -> some View {
        self
            .plainListRow()
            .listRowBackground(Color.clear)
            .buttonStyle(PlainButtonStyle())
    }
}
