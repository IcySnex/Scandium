// SoundCloudAuthManager.swift — SoundCloud user authentication & sync manager
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import Foundation
import Combine
import WebKit

final class SoundCloudAuthManager: ObservableObject {
    static let shared = SoundCloudAuthManager()

    // MARK: - Published State

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentUser: SoundCloudUser?
    @Published private(set) var oauthToken: String?
    @Published private(set) var userPlaylists: [SoundCloudPlaylist] = []
    @Published private(set) var userAlbums: [SoundCloudPlaylist] = []
    @Published private(set) var userFollowings: [SoundCloudUser] = []
    @Published private(set) var userLikedTracks: [Track] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?
    /// SoundCloud no longer accepts the saved sign-in; the user has to sign in again
    @Published private(set) var sessionExpired: Bool = false

    // MARK: - Storage Keys

    private let legacyTokenKey = "scandium_soundcloud_oauth_token"
    private let scOAuthTokenKey = "sc_oauth_token"
    private let scRefreshTokenKey = "sc_oauth_refresh_token"
    private let userKey = "scandium_soundcloud_current_user"
    private let playlistsKey = "scandium_soundcloud_user_playlists"
    private let followingsKey = "scandium_soundcloud_user_followings"
    private let userLikesKey = "scandium_soundcloud_user_likes"

    private var api: SoundCloudAPI?

    private init() {
        loadPersistedState()
    }

    func setAPI(_ api: SoundCloudAPI) {
        self.api = api
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        let storedToken = KeychainHelper.loadString(key: scOAuthTokenKey) ??
                          UserDefaults.standard.string(forKey: scOAuthTokenKey) ??
                          UserDefaults.standard.string(forKey: legacyTokenKey)

        if let token = storedToken, !token.isEmpty {
            self.oauthToken = token
            self.isLoggedIn = true
            self.isAuthenticated = true

            // Migrate plaintext token to Keychain and purge from UserDefaults
            _ = KeychainHelper.saveString(key: scOAuthTokenKey, value: token)
            UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        }

        if let userData = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(SoundCloudUser.self, from: userData) {
            self.currentUser = user
            self.isLoggedIn = true
            self.isAuthenticated = true
        }

        if let plData = UserDefaults.standard.data(forKey: playlistsKey),
           let playlists = try? JSONDecoder().decode([SoundCloudPlaylist].self, from: plData) {
            self.userPlaylists = playlists
            self.userAlbums = playlists.filter { ($0.trackCount ?? 0) >= 5 || ($0.title.lowercased().contains("album") || $0.title.lowercased().contains("ep")) }
        }

        if let folData = UserDefaults.standard.data(forKey: followingsKey),
           let followings = try? JSONDecoder().decode([SoundCloudUser].self, from: folData) {
            self.userFollowings = followings
        }

        if let likesData = UserDefaults.standard.data(forKey: userLikesKey),
           let likes = try? JSONDecoder().decode([Track].self, from: likesData) {
            self.userLikedTracks = likes
        }
    }

    private func savePersistedState() {
        if let token = oauthToken {
            KeychainHelper.saveString(key: scOAuthTokenKey, value: token)
            UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        } else {
            KeychainHelper.delete(key: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        }

        if let user = currentUser, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userKey)
        }

        if let plData = try? JSONEncoder().encode(userPlaylists) {
            UserDefaults.standard.set(plData, forKey: playlistsKey)
        }

        if let folData = try? JSONEncoder().encode(userFollowings) {
            UserDefaults.standard.set(folData, forKey: followingsKey)
        }

        if let likesData = try? JSONEncoder().encode(userLikedTracks) {
            UserDefaults.standard.set(likesData, forKey: userLikesKey)
        }
    }

    // MARK: - Save OAuth Token

    /// - Parameter refreshToken: the `oauth_refresh_token` cookie from the
    ///   sign-in page, used to renew the short-lived access token. A token
    ///   pasted by hand has none and stops working when it expires.
    @MainActor
    func saveToken(_ token: String, refreshToken: String? = nil) {
        var cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanToken.hasPrefix("OAuth ") { cleanToken.removeFirst("OAuth ".count) }
        guard !cleanToken.isEmpty else { return }

        if let refresh = refreshToken, !refresh.isEmpty {
            KeychainHelper.saveString(key: scRefreshTokenKey, value: refresh)
        } else {
            KeychainHelper.delete(key: scRefreshTokenKey)
        }
        sessionExpired = false
        KeychainHelper.saveString(key: scOAuthTokenKey, value: cleanToken)
        UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)

        self.oauthToken = cleanToken
        self.isLoggedIn = true
        self.isAuthenticated = true
        self.isLoading = true
        self.errorMessage = nil

        Task {
            await self.fetchUserProfileAndSync(token: cleanToken)
        }
    }

    @MainActor
    func handleOAuthToken(_ token: String) async {
        saveToken(token)
    }

    // MARK: - Fetch User Profile & Auto-Sync Library

    @MainActor
    private func fetchUserProfileAndSync(token: String) async {
        guard let api = api else {
            self.isLoading = false
            self.savePersistedState()
            return
        }

        do {
            // Gọi endpoint /me để lấy ID (urn/id), username, avatar_url
            let me = try await api.getMe(oauthToken: token)
            self.currentUser = me
            self.isLoggedIn = true
            self.isAuthenticated = true
            self.savePersistedState()

            // Tự động đồng bộ likes và playlists
            await syncLibraryInternal(token: token, user: me)
        } catch {
            print("[ScandiumAuth] /me request failed: \(error.localizedDescription)")
            self.errorMessage = "Unable to fetch profile: \(error.localizedDescription)"
            self.isLoggedIn = true
            self.isAuthenticated = true
            self.savePersistedState()
        }

        self.isLoading = false
    }

    // MARK: - Sign In: Resolve Profile URL

    @MainActor
    func handleProfileURL(_ urlString: String) async {
        let clean = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        self.isLoading = true
        self.errorMessage = nil

        guard let api = api else {
            self.isLoading = false
            return
        }

        do {
            let resolvedUser = try await api.resolveURL(url: clean)
            self.currentUser = resolvedUser
            self.isLoggedIn = true
            self.isAuthenticated = true
            self.savePersistedState()
            await syncLibrary()
        } catch {
            self.errorMessage = "Account not found: \(error.localizedDescription)"
        }

        self.isLoading = false
    }

    // MARK: - Synchronize Library (Likes & Playlists)

    private var didSyncThisLaunch = false

    /// Pulls the library from SoundCloud once per app launch. Later changes
    /// made in the app are pushed immediately (see `setRemoteLike`).
    @MainActor
    func syncOnLaunchIfNeeded() async {
        guard !didSyncThisLaunch, currentUser != nil else { return }
        didSyncThisLaunch = true
        await syncLibrary()
    }

    @MainActor
    func syncLibrary() async {
        guard let user = currentUser else { return }
        self.isLoading = true
        await syncLibraryInternal(token: oauthToken, user: user)
        self.isLoading = false
    }

    // MARK: - Write-through Likes

    /// True when likes made in the app can be sent to the SoundCloud account.
    var canSyncLikes: Bool {
        currentUser != nil && !(oauthToken ?? "").isEmpty && !sessionExpired
    }

    /// Likes or unlikes a track on the SoundCloud account.
    @MainActor
    func setRemoteLike(_ liked: Bool, track: Track) async throws {
        guard let api = api, let user = currentUser, let token = oauthToken, !token.isEmpty else {
            throw APIError.invalidResponse
        }
        try await api.setTrackLiked(liked, trackID: track.id, userID: user.id, oauthToken: token)

        if liked {
            if !userLikedTracks.contains(where: { $0.id == track.id }) {
                userLikedTracks.insert(track, at: 0)
            }
        } else {
            userLikedTracks.removeAll { $0.id == track.id }
        }
        savePersistedState()
    }

    @MainActor
    private func syncLibraryInternal(token: String?, user: SoundCloudUser) async {
        guard let api = api else { return }

        // nil means the fetch failed: keep the previously synced data instead of
        // wiping it with an empty list.
        let fetchStartedAt = Date()
        var likes: [Track]?
        if let token = token, !token.isEmpty {
            if let trackLikes = try? await api.getUserTrackLikes(userID: user.id, oauthToken: token) {
                likes = trackLikes
            } else if let meLikes = try? await api.getMeLikesTracks(oauthToken: token) {
                likes = meLikes
            } else {
                likes = try? await api.getUserLikes(userID: user.id, oauthToken: token)
            }
        } else {
            likes = try? await api.getUserLikes(userID: user.id, oauthToken: nil)
        }

        var playlists: [SoundCloudPlaylist]?
        if let token = token, !token.isEmpty {
            do {
                playlists = try await api.getMePlaylists(oauthToken: token)
            } catch {
                playlists = try? await api.getUserPlaylists(userID: user.id, oauthToken: token)
            }
        } else {
            playlists = try? await api.getUserPlaylists(userID: user.id, oauthToken: nil)
        }

        let followings = (try? await api.getUserFollowings(userID: user.id, oauthToken: token, limit: 30)) ?? []

        if let likes = likes {
            let uniqueLikes = deduplicateTracks(likes)
            self.userLikedTracks = uniqueLikes
            LibraryManager.shared.syncLikedTracks(uniqueLikes, fetchStartedAt: fetchStartedAt)
        }
        if let playlists = playlists {
            self.userPlaylists = playlists
            self.userAlbums = playlists.filter { ($0.trackCount ?? 0) >= 5 || ($0.title.lowercased().contains("album") || $0.title.lowercased().contains("ep")) }
            LibraryManager.shared.syncUserPlaylists(playlists)
        }
        self.userFollowings = followings

        self.savePersistedState()
    }

    private func deduplicateTracks(_ tracks: [Track]) -> [Track] {
        var seen = Set<Int>()
        var result: [Track] = []
        result.reserveCapacity(tracks.count)
        for track in tracks {
            if seen.insert(track.id).inserted {
                result.append(track)
            }
        }
        return result
    }

    // MARK: - Sign Out

    @MainActor
    func logout() {
        self.isLoggedIn = false
        self.isAuthenticated = false
        self.currentUser = nil
        self.oauthToken = nil
        self.userPlaylists = []
        self.userAlbums = []
        self.userFollowings = []
        self.userLikedTracks = []
        self.errorMessage = nil

        self.sessionExpired = false
        KeychainHelper.delete(key: scOAuthTokenKey)
        KeychainHelper.delete(key: scRefreshTokenKey)
        UserDefaults.standard.removeObject(forKey: scOAuthTokenKey)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        UserDefaults.standard.removeObject(forKey: playlistsKey)
        UserDefaults.standard.removeObject(forKey: followingsKey)
        UserDefaults.standard.removeObject(forKey: userLikesKey)

        LibraryManager.shared.syncUserPlaylists([])
    }

    // MARK: - Session Refresh
    //
    // soundcloud.com signs in with a short-lived access token (a JWT that
    // lasts about a day) plus a single-use refresh token. The access token
    // is renewed shortly before it expires, or after a request is rejected.

    private var renewal: Task<String?, Never>?

    /// Seconds before expiry at which the token is renewed ahead of time
    private static let renewalMargin: TimeInterval = 5 * 60

    /// The access token to send, renewed first if it expires soon.
    @MainActor
    func validAccessToken() async -> String? {
        guard let token = oauthToken, !token.isEmpty else { return nil }
        if let expiry = Self.claims(of: token)?["exp"] as? Double,
           Date(timeIntervalSince1970: expiry).timeIntervalSinceNow < Self.renewalMargin {
            return await renewAccessToken(replacing: token) ?? token
        }
        return token
    }

    /// Renews the access token after `failedToken` was rejected. Returns the
    /// new token, or nil when it can't be renewed. Concurrent callers share
    /// one renewal, and a token that was already replaced isn't renewed again.
    @MainActor
    func renewAccessToken(replacing failedToken: String) async -> String? {
        if let current = oauthToken, current != failedToken { return current }
        if let running = renewal { return await running.value }
        let task = Task { @MainActor in await self.performRenewal() }
        renewal = task
        let result = await task.value
        renewal = nil
        return result
    }

    @MainActor
    private func performRenewal() async -> String? {
        guard let api = api, let token = oauthToken else { return nil }
        // Saved at sign-in; sign-ins from before this existed still have it
        // in the sign-in page's cookies
        var refreshToken = KeychainHelper.loadString(key: scRefreshTokenKey)
        // Only if the page's session is the one this token came from (not
        // after a token was pasted by hand)
        if refreshToken == nil, await Self.webCookie(named: "oauth_token")?.value == token {
            refreshToken = await Self.webCookie(named: "oauth_refresh_token")?.value
        }
        guard let refresh = refreshToken, !refresh.isEmpty else {
            markSessionExpired()
            return nil
        }

        // The web player renews with the client the token was issued to
        let clientID = Self.claims(of: token)?["client_id"] as? String
        do {
            let renewed = try await api.refreshAccessToken(refreshToken: refresh, clientID: clientID)
            // Single use: store the next refresh token before anything else
            if let next = renewed.refreshToken, !next.isEmpty {
                KeychainHelper.saveString(key: scRefreshTokenKey, value: next)
            }
            KeychainHelper.saveString(key: scOAuthTokenKey, value: renewed.accessToken)
            oauthToken = renewed.accessToken
            sessionExpired = false
            await Self.updateWebCookies(accessToken: renewed.accessToken, refreshToken: renewed.refreshToken)
            return renewed.accessToken
        } catch SoundCloudAPI.TokenRefreshError.rejected {
            KeychainHelper.delete(key: scRefreshTokenKey)
            markSessionExpired()
            return nil
        } catch {
            // Offline or a server hiccup: keep the session and try again later
            return nil
        }
    }

    @MainActor
    private func markSessionExpired() {
        sessionExpired = true
        errorMessage = "Your SoundCloud sign-in expired. Sign in again in Profile."
    }

    /// The payload of a JWT access token (`exp`, `client_id`, ...), or nil
    /// for tokens that aren't JWTs.
    private static func claims(of token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: Sign-in page cookies

    @MainActor
    private static func webCookie(named name: String) async -> HTTPCookie? {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let match = cookies.first { $0.name == name && $0.domain.contains("soundcloud") && !$0.value.isEmpty }
                continuation.resume(returning: match)
            }
        }
    }

    /// Writes the renewed tokens back into the sign-in page's cookies, so the
    /// page never sends an already-used refresh token (which can make
    /// SoundCloud end the whole session).
    @MainActor
    private static func updateWebCookies(accessToken: String, refreshToken: String?) async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        for (name, value) in [("oauth_token", accessToken), ("oauth_refresh_token", refreshToken)] {
            guard let value = value, let old = await webCookie(named: name),
                  var properties = old.properties else { continue }
            properties[.value] = value
            if let renewed = HTTPCookie(properties: properties) {
                await withCheckedContinuation { continuation in
                    store.setCookie(renewed) { continuation.resume() }
                }
            }
        }
    }
}
