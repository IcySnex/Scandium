// LibraryManager.swift — Local persistence for Liked Tracks & Recently Played
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import Foundation
import Combine

final class LibraryManager: ObservableObject {

    static let shared = LibraryManager()

    // MARK: - Published State

    @Published private(set) var likedTracks: [Track] = []
    @Published private(set) var recentlyPlayed: [Track] = []
    @Published private(set) var userPlaylists: [SoundCloudPlaylist] = []

    // MARK: - Storage Keys

    private static let likedTracksKey = "scandium_liked_tracks_v1"
    private static let recentlyPlayedKey = "scandium_recently_played_v1"
    private static let userPlaylistsKey = "scandium_user_playlists_v1"
    private static let syncedLikeIDsKey = "scandium_synced_like_ids_v1"
    private static let maxRecentlyPlayed = 50

    // MARK: - Init

    init() {
        loadData()
    }

    // MARK: - Liked Tracks API

    func isLiked(track: Track) -> Bool {
        likedTracks.contains(where: { $0.id == track.id })
    }

    func toggleLike(track: Track) {
        if isLiked(track: track) {
            unlike(track: track)
        } else {
            like(track: track)
        }
    }

    /// Likes a track locally and, when signed in, on the SoundCloud account.
    func like(track: Track) {
        guard !isLiked(track: track) else { return }
        likedTracks.insert(track, at: 0)
        saveLikedTracks()
        recordEdit(track: track, liked: true)
        pushRemoteLike(true, track: track, restoreIndex: 0)
    }

    /// Unlikes a track locally and, when signed in, on the SoundCloud account.
    func unlike(track: Track) {
        guard let index = likedTracks.firstIndex(where: { $0.id == track.id }) else { return }
        likedTracks.remove(at: index)
        saveLikedTracks()
        recordEdit(track: track, liked: false)
        pushRemoteLike(false, track: track, restoreIndex: index)
    }
    /// Replaces the synced portion of the liked list with the remote likes, in
    /// SoundCloud's order (newest first). Tracks liked only inside the app stay
    /// on top; tracks that came from an earlier sync but are no longer liked on
    /// SoundCloud are dropped. Likes/unlikes made in the app after the fetch
    /// started are re-applied so an in-flight sync can't undo them.
    func syncLikedTracks(_ tracks: [Track], fetchStartedAt: Date = .distantPast) {
        let remoteIDs = Set(tracks.map { $0.id })

        let localOnly = likedTracks.filter { !remoteIDs.contains($0.id) && !syncedLikeIDs.contains($0.id) }
        var merged = localOnly + tracks
        var synced = remoteIDs

        let recentEdits = localEdits.filter { $0.value.at >= fetchStartedAt }
        for (id, edit) in recentEdits.sorted(by: { $0.value.at < $1.value.at }) {
            if edit.liked {
                if !merged.contains(where: { $0.id == id }) { merged.insert(edit.track, at: 0) }
                synced.insert(id)
            } else {
                merged.removeAll { $0.id == id }
                synced.remove(id)
            }
        }
        localEdits = recentEdits

        syncedLikeIDs = synced
        likedTracks = merged
        saveLikedTracks()
    }

    /// Set when sending a like/unlike to SoundCloud fails (the local change is
    /// rolled back). The UI shows it and clears it.
    @Published var likeSyncError: String?

    // MARK: - Write-through to SoundCloud

    private struct LocalEdit {
        let liked: Bool
        let track: Track
        let at: Date
    }

    /// Like/unlike taps since the last sync, keyed by track ID.
    private var localEdits: [Int: LocalEdit] = [:]
    /// Serializes remote like/unlike requests so they reach SoundCloud in tap order.
    private var remoteLikeChain: Task<Void, Never>?

    /// IDs of liked tracks that are known to be liked on the SoundCloud account.
    private var syncedLikeIDs: Set<Int> {
        get { Set(UserDefaults.standard.array(forKey: Self.syncedLikeIDsKey) as? [Int] ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.syncedLikeIDsKey) }
    }

    private func recordEdit(track: Track, liked: Bool) {
        localEdits[track.id] = LocalEdit(liked: liked, track: track, at: Date())
    }

    private func pushRemoteLike(_ liked: Bool, track: Track, restoreIndex: Int) {
        let auth = SoundCloudAuthManager.shared
        guard auth.canSyncLikes else { return }

        let previous = remoteLikeChain
        remoteLikeChain = Task { @MainActor [weak self] in
            await previous?.value
            do {
                try await auth.setRemoteLike(liked, track: track)
                guard let self = self else { return }
                if liked { self.syncedLikeIDs.insert(track.id) } else { self.syncedLikeIDs.remove(track.id) }
            } catch {
                self?.rollBack(liked, track: track, restoreIndex: restoreIndex, error: error)
            }
        }
    }

    /// Undoes a local like/unlike whose remote request failed, unless the user
    /// has already toggled the track again since.
    @MainActor
    private func rollBack(_ liked: Bool, track: Track, restoreIndex: Int, error: Error) {
        print("[LibraryManager] Remote \(liked ? "like" : "unlike") failed for \(track.id): \(error.localizedDescription)")
        guard isLiked(track: track) == liked else { return }

        if liked {
            likedTracks.removeAll { $0.id == track.id }
        } else {
            likedTracks.insert(track, at: min(restoreIndex, likedTracks.count))
        }
        localEdits[track.id] = nil
        saveLikedTracks()

        let settings = AppSettings.shared
        likeSyncError = liked
            ? "Couldn't like this track on SoundCloud"
            : "Couldn't unlike this track on SoundCloud"
    }

    /// Synchronizes user playlists from SoundCloud account
    func syncUserPlaylists(_ playlists: [SoundCloudPlaylist]) {
        self.userPlaylists = playlists
        saveUserPlaylists()
    }

    // MARK: - Recently Played API

    func addToRecentlyPlayed(track: Track) {
        // Remove if already in list to move to top
        recentlyPlayed.removeAll(where: { $0.id == track.id })
        recentlyPlayed.insert(track, at: 0)

        // Enforce maximum capacity
        if recentlyPlayed.count > Self.maxRecentlyPlayed {
            recentlyPlayed = Array(recentlyPlayed.prefix(Self.maxRecentlyPlayed))
        }

        saveRecentlyPlayed()
    }

    func clearRecentlyPlayed() {
        recentlyPlayed.removeAll()
        saveRecentlyPlayed()
    }

    func clearAllData() {
        likedTracks.removeAll()
        recentlyPlayed.removeAll()
        userPlaylists.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.likedTracksKey)
        UserDefaults.standard.removeObject(forKey: Self.recentlyPlayedKey)
        UserDefaults.standard.removeObject(forKey: Self.userPlaylistsKey)
        UserDefaults.standard.removeObject(forKey: Self.syncedLikeIDsKey)
    }

    // MARK: - Persistence Helpers

    private func loadData() {
        let decoder = JSONDecoder()

        if let likedData = UserDefaults.standard.data(forKey: Self.likedTracksKey),
           let tracks = try? decoder.decode([Track].self, from: likedData) {
            self.likedTracks = tracks
        }

        if let recentData = UserDefaults.standard.data(forKey: Self.recentlyPlayedKey),
           let tracks = try? decoder.decode([Track].self, from: recentData) {
            self.recentlyPlayed = tracks
        }

        if let plData = UserDefaults.standard.data(forKey: Self.userPlaylistsKey),
           let playlists = try? decoder.decode([SoundCloudPlaylist].self, from: plData) {
            self.userPlaylists = playlists
        }
    }

    private func saveLikedTracks() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(likedTracks) {
            UserDefaults.standard.set(data, forKey: Self.likedTracksKey)
        }
    }

    private func saveRecentlyPlayed() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(recentlyPlayed) {
            UserDefaults.standard.set(data, forKey: Self.recentlyPlayedKey)
        }
    }

    private func saveUserPlaylists() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(userPlaylists) {
            UserDefaults.standard.set(data, forKey: Self.userPlaylistsKey)
        }
    }
}
