// LibraryView.swift — Liked tracks, playlists, albums, followed artists and
// recently played, as a native list with a section menu in the bar
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

enum LibraryTab: Int, CaseIterable, Identifiable {
    case liked, playlists, albums, following, recent

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .liked: return "Liked Songs"
        case .playlists: return "Playlists"
        case .albums: return "Albums"
        case .following: return "Following"
        case .recent: return "Recently Played"
        }
    }

    var icon: String {
        switch self {
        case .liked: return "heart"
        case .playlists: return "music.note.list"
        case .albums: return "square.stack"
        case .following: return "person.2"
        case .recent: return "clock"
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var library: LibraryManager
    @EnvironmentObject var player: AudioPlayerEngine
    @ObservedObject private var auth = SoundCloudAuthManager.shared

    /// Owned by the tab container, so the Home shortcut can pick a section
    @Binding var selectedTab: LibraryTab

    init(selection: Binding<LibraryTab>) {
        _selectedTab = selection
    }

    var body: some View {
        List {
            switch selectedTab {
            case .liked: likedSection
            case .playlists: playlistSection(auth.userPlaylists, empty: "No playlists yet.")
            case .albums: playlistSection(auth.userAlbums, empty: "No albums yet.")
            case .following: followingSection
            case .recent: recentSection
            }
            MiniPlayerSpacerRow()
        }
        .listStyle(PlainListStyle())
        .refreshable {
            if auth.isAuthenticated {
                await auth.syncLibrary()
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { sectionMenu }
        }
    }

    // MARK: - Section Menu

    private func count(_ tab: LibraryTab) -> Int {
        switch tab {
        case .liked: return library.likedTracks.count
        case .playlists: return auth.userPlaylists.count
        case .albums: return auth.userAlbums.count
        case .following: return auth.userFollowings.count
        case .recent: return library.recentlyPlayed.count
        }
    }

    private var sectionMenu: some View {
        Menu {
            Picker("Show", selection: $selectedTab) {
                ForEach(LibraryTab.allCases) { tab in
                    Label("\(tab.name) (\(count(tab)))", systemImage: tab.icon).tag(tab)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedTab.name)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    // MARK: - Liked Songs

    @ViewBuilder
    private var likedSection: some View {
        if library.likedTracks.isEmpty {
            emptyState(auth.canSyncLikes
                       ? "No liked songs yet. Swipe left on a song or tap its heart to like it."
                       : "Sign in to SoundCloud in Profile to see your liked songs.")
        } else {
            PlayShuffleButtons(tracks: library.likedTracks)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .plainListRow()

            ForEach(Array(library.likedTracks.enumerated()), id: \.element.id) { index, track in
                GlassTrackRow(
                    track: track,
                    isCurrentlyPlaying: player.currentTrack?.id == track.id,
                    onTap: { player.playQueue(library.likedTracks, startingAt: index) }
                )
                .plainListRow()
            }
        }
    }

    // MARK: - Playlists & Albums

    @ViewBuilder
    private func playlistSection(_ playlists: [SoundCloudPlaylist], empty: String) -> some View {
        if !auth.isAuthenticated {
            emptyState("Sign in to SoundCloud in Profile to see your playlists and albums.")
        } else if playlists.isEmpty {
            emptyState(empty + " Pull down to sync again.")
        } else {
            ForEach(playlists) { playlist in
                NavigationLink(destination: TrackCollectionView(playlist: playlist)) {
                    HStack(spacing: 12) {
                        CachedAsyncImage(url: playlist.highResArtworkURL, width: 54, height: 54, cornerRadius: 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.title)
                                .font(.body)
                                .lineLimit(1)
                            Text("\(playlist.user?.username ?? "SoundCloud") · \(playlist.trackCount ?? 0) tracks")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    // MARK: - Following

    @ViewBuilder
    private var followingSection: some View {
        if !auth.isAuthenticated {
            emptyState("Sign in to SoundCloud in Profile to see the artists you follow.")
        } else if auth.userFollowings.isEmpty {
            emptyState("You don't follow anyone yet. Pull down to sync again.")
        } else {
            ForEach(auth.userFollowings) { user in
                NavigationLink(destination: TrackCollectionView(user: user)) {
                    HStack(spacing: 12) {
                        CachedAsyncImage(url: URL(string: user.avatarURL ?? ""), width: 50, height: 50, cornerRadius: 25)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(user.username)
                                    .font(.body)
                                    .lineLimit(1)
                                if user.verified == true {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                            if let followers = user.followersCount {
                                Text("\(followers) followers")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowSeparator(.hidden)
            }
        }
    }

    // MARK: - Recently Played

    @ViewBuilder
    private var recentSection: some View {
        if library.recentlyPlayed.isEmpty {
            emptyState("Songs you play will show up here.")
        } else {
            Section(header: HStack {
                Text("\(library.recentlyPlayed.count) songs")
                Spacer()
                Button("Clear") { library.clearRecentlyPlayed() }
                    .font(.subheadline)
            }) {
                ForEach(Array(library.recentlyPlayed.enumerated()), id: \.element.id) { index, track in
                    GlassTrackRow(
                        track: track,
                        isCurrentlyPlaying: player.currentTrack?.id == track.id,
                        onTap: { player.playQueue(library.recentlyPlayed, startingAt: index) }
                    )
                    .plainListRow()
                }
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 60)
            .plainListRow()
    }
}
