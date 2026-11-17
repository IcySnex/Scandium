// LibraryView.swift — Spotify-style user library (Liked tracks, Playlists, Albums, Following & Recently played)
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

enum LibraryTab: Int, CaseIterable, Identifiable {
    case liked = 0
    case playlists = 1
    case albums = 2
    case following = 3
    case recent = 4

    var id: Int { rawValue }

    func title(settings: AppSettings, library: LibraryManager, auth: SoundCloudAuthManager) -> String {
        switch self {
        case .liked:
            let count = library.likedTracks.count
            return "Liked (\(count))"
        case .playlists:
            let count = auth.userPlaylists.count
            return "Playlists (\(count))"
        case .albums:
            let count = auth.userAlbums.count
            return "Albums (\(count))"
        case .following:
            let count = auth.userFollowings.count
            return "Following (\(count))"
        case .recent:
            let count = library.recentlyPlayed.count
            return "Recent (\(count))"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var api: SoundCloudAPI
    @ObservedObject private var auth = SoundCloudAuthManager.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedTab: LibraryTab = .liked

    init() {}

    var body: some View {
        VStack(spacing: 0) {

            horizontalTabsBar
                .padding(.vertical, 10)

            contentView
        }
        .navigationTitle("Library")
    }

    // MARK: - Horizontal Filter Tabs Bar

    private var horizontalTabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    }) {
                        Text(tab.title(settings: settings, library: library, auth: auth))
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundColor(selectedTab == tab ? (ScandiumTheme.isDark ? .black : .white) : ScandiumTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? ScandiumTheme.textPrimary : ScandiumTheme.surfaceElevated)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Content

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                switch selectedTab {
                case .liked:
                    likedTracksSection
                case .playlists:
                    playlistsSection
                case .albums:
                    albumsSection
                case .following:
                    followingsSection
                case .recent:
                    recentlyPlayedSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 130)
        }
        .refreshable {
            if auth.isAuthenticated {
                await auth.syncLibrary()
            }
        }
    }

    // MARK: - Liked Tracks Section

    @ViewBuilder
    private var likedTracksSection: some View {
        if library.likedTracks.isEmpty {
            emptyStateView(
                icon: "heart.slash",
                title: "No liked songs yet",
                message: "Tap the heart icon on any song to save it to your library."
            )
        } else {
            PlayShuffleButtons(tracks: library.likedTracks)
            .padding(.bottom, 6)

            LazyVStack(spacing: 4) {
                ForEach(Array(library.likedTracks.enumerated()), id: \.element.id) { index, track in
                    GlassTrackRow(
                        track: track,
                        isCurrentlyPlaying: player.currentTrack?.id == track.id,
                        onTap: {
                            player.playQueue(library.likedTracks, startingAt: index)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Playlists Section

    @ViewBuilder
    private var playlistsSection: some View {
        if !auth.isAuthenticated {
            emptyStateView(
                icon: "music.note.list",
                title: "Account Not Synchronized",
                message: "Synchronize account in Profile to load your playlists."
            )
        } else if auth.userPlaylists.isEmpty {
            emptyStateView(
                icon: "music.note.list",
                title: "No playlists found",
                message: "Pull down to reload or create new playlists in your account."
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(auth.userPlaylists) { pl in
                    playlistRow(playlist: pl)
                }
            }
        }
    }

    // MARK: - Albums Section

    @ViewBuilder
    private var albumsSection: some View {
        if !auth.isAuthenticated {
            emptyStateView(
                icon: "opticaldisc",
                title: "Account Not Synchronized",
                message: "Synchronize account to browse your albums and EPs."
            )
        } else if auth.userAlbums.isEmpty {
            emptyStateView(
                icon: "opticaldisc",
                title: "No albums found",
                message: "Albums or playlists with 5+ tracks will appear here."
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(auth.userAlbums) { pl in
                    playlistRow(playlist: pl)
                }
            }
        }
    }

    private func playlistRow(playlist: SoundCloudPlaylist) -> some View {
        NavigationLink(destination: TrackCollectionView(playlist: playlist)) {
            HStack(spacing: 12) {
                CachedAsyncImage(
                    url: playlist.highResArtworkURL,
                    width: 54,
                    height: 54,
                    cornerRadius: 8
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(playlist.user?.username ?? "SoundCloud")
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)

                        Text("•")
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)

                        Text("\(playlist.trackCount ?? 0) tracks")
                            .font(.system(size: 12))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                    .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ScandiumTheme.subtext)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ScandiumTheme.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusMedium, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Followings Section

    @ViewBuilder
    private var followingsSection: some View {
        if !auth.isAuthenticated {
            emptyStateView(
                icon: "person.crop.circle.badge.plus",
                title: "Account Not Synchronized",
                message: "Synchronize account to see artists you are following."
            )
        } else if auth.userFollowings.isEmpty {
            emptyStateView(
                icon: "person.2",
                title: "No followed artists",
                message: "Pull down to sync artists you follow."
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(auth.userFollowings) { user in
                    NavigationLink(destination: TrackCollectionView(user: user)) {
                    HStack(spacing: 12) {
                        CachedAsyncImage(
                            url: URL(string: user.avatarURL ?? ""),
                            width: 50,
                            height: 50,
                            cornerRadius: 25
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(user.username)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                    .lineLimit(1)

                                if user.verified == true {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(ScandiumTheme.spotifyGreen)
                                }
                            }

                            if let followers = user.followersCount {
                                Text("\(followers) followers")
                                    .font(.system(size: 12))
                                    .foregroundColor(ScandiumTheme.subtext)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ScandiumTheme.subtext)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ScandiumTheme.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: ScandiumTheme.cornerRadiusMedium, style: .continuous))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Recently Played Section

    @ViewBuilder
    private var recentlyPlayedSection: some View {
        if library.recentlyPlayed.isEmpty {
            emptyStateView(
                icon: "clock.arrow.circlepath",
                title: "No listening history yet",
                message: "Tracks you play will automatically appear here."
            )
        } else {
            HStack {
                Text("\(library.recentlyPlayed.count) recently played tracks")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ScandiumTheme.subtext)
                Spacer()
                Button("Clear History") {
                    library.clearRecentlyPlayed()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ScandiumTheme.subtext)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            LazyVStack(spacing: 4) {
                ForEach(Array(library.recentlyPlayed.enumerated()), id: \.element.id) { index, track in
                    GlassTrackRow(
                        track: track,
                        isCurrentlyPlaying: player.currentTrack?.id == track.id,
                        onTap: {
                            player.playQueue(library.recentlyPlayed, startingAt: index)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Empty State View

    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundColor(ScandiumTheme.subtext.opacity(0.5))
                .padding(.top, 40)

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(ScandiumTheme.textPrimary)

            Text(message)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(ScandiumTheme.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}
