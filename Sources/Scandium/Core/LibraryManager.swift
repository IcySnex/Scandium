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

    func like(track: Track) {
        guard !isLiked(track: track) else { return }
        likedTracks.insert(track, at: 0)
        saveLikedTracks()
    }

    func unlike(track: Track) {
        likedTracks.removeAll(where: { $0.id == track.id })
        saveLikedTracks()
    }

    func clearLikedTracks() {
        likedTracks.removeAll()
        saveLikedTracks()
    }

    /// Replaces the synced portion of the liked list with the remote likes, in
    /// SoundCloud's order (newest first). Tracks liked only inside the app stay
    /// on top; tracks that came from an earlier sync but are no longer liked on
    /// SoundCloud are dropped.
    func syncLikedTracks(_ tracks: [Track]) {
        let remoteIDs = Set(tracks.map { $0.id })
        let previouslySynced = Set(UserDefaults.standard.array(forKey: Self.syncedLikeIDsKey) as? [Int] ?? [])

        let localOnly = likedTracks.filter { !remoteIDs.contains($0.id) && !previouslySynced.contains($0.id) }
        let merged = localOnly + tracks

        UserDefaults.standard.set(Array(remoteIDs), forKey: Self.syncedLikeIDsKey)
        likedTracks = merged
        saveLikedTracks()
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
