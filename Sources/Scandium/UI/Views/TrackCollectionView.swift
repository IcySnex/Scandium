// TrackCollectionView.swift — Pushed page listing the tracks of a playlist,
// mix, station or artist, with Play All / Shuffle.
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct TrackCollectionView: View {
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let roundArtwork: Bool
    let initialTracks: [Track]
    let load: (SoundCloudAPI) async throws -> [Track]

    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerEngine

    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    init(
        title: String,
        subtitle: String?,
        artworkURL: URL?,
        roundArtwork: Bool = false,
        initialTracks: [Track] = [],
        load: @escaping (SoundCloudAPI) async throws -> [Track]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.roundArtwork = roundArtwork
        self.initialTracks = initialTracks
        self.load = load
        _tracks = State(initialValue: initialTracks)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !tracks.isEmpty {
                    PlayShuffleButtons(tracks: tracks)
                }

                if isLoading && tracks.isEmpty {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: ScandiumTheme.accent))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                } else if loadFailed && tracks.isEmpty {
                    Text("Couldn't load tracks.")
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
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .background(ScandiumTheme.bgPrimary.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadTracks() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            CachedAsyncImage(url: artworkURL, width: 110, height: 110, cornerRadius: roundArtwork ? 55 : 10)
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
                if !isLoading || !tracks.isEmpty {
                    Text("\(tracks.count) tracks")
                        .font(.system(size: 13))
                        .foregroundColor(ScandiumTheme.subtext)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @MainActor
    private func loadTracks() async {
        guard isLoading else { return }
        do {
            tracks = try await load(api)
        } catch {
            loadFailed = true
        }
        isLoading = false
    }
}

// MARK: - Convenience Initializers

extension TrackCollectionView {
    /// A playlist, mix, station or artist from the Home feed.
    init(homeItem: HomeItem) {
        switch homeItem {
        case .playlist(let playlist):
            self.init(
                title: playlist.title,
                subtitle: playlist.isSystemPlaylist ? playlist.description : playlist.user?.username,
                artworkURL: playlist.highResArtworkURL,
                initialTracks: playlist.tracks,
                load: { api in
                    try await api.getPlaylistTracks(playlist, oauthToken: SoundCloudAuthManager.shared.oauthToken)
                }
            )
        case .user(let user):
            self.init(user: user)
        }
    }

    /// One of the user's own playlists or albums.
    init(playlist: SoundCloudPlaylist) {
        let embedded = playlist.tracks ?? []
        let isComplete = playlist.trackCount.map { embedded.count >= $0 } ?? false
        self.init(
            title: playlist.title,
            subtitle: playlist.user?.username,
            artworkURL: playlist.highResArtworkURL,
            initialTracks: embedded,
            load: { api in
                if isComplete { return embedded }
                return try await api.getPlaylistTracks(playlistID: playlist.id, oauthToken: SoundCloudAuthManager.shared.oauthToken)
            }
        )
    }

    /// An artist's uploads.
    init(user: SoundCloudUser) {
        self.init(
            title: user.username,
            subtitle: user.fullName,
            artworkURL: user.avatarURL.flatMap { URL(string: Track.upgradeArtwork(urlString: $0, to: .t500x500)) },
            roundArtwork: true,
            load: { api in
                try await api.getUserTracks(userID: user.id, oauthToken: SoundCloudAuthManager.shared.oauthToken)
            }
        )
    }
}

// MARK: - Play All / Shuffle

/// "Play All" starts in order with shuffle off; "Shuffle" turns shuffle on.
struct PlayShuffleButtons: View {
    let tracks: [Track]
    @EnvironmentObject var player: AudioPlayerEngine

    var body: some View {
        HStack(spacing: 12) {
            button(icon: "play.fill", title: "Play All", primary: true) {
                player.playQueue(tracks, shuffle: false)
            }
            button(icon: "shuffle", title: "Shuffle", primary: false) {
                player.playQueue(tracks, shuffle: true)
            }
        }
    }

    private func button(icon: String, title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(primary ? .white : ScandiumTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(primary ? ScandiumTheme.accent : ScandiumTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }
}
