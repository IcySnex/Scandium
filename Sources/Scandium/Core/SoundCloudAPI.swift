// SoundCloudAPI.swift — API v2 networking layer for SoundCloud
// Project: Scandium | Author: MeoHunter | License: GPL-3.0
//
// Provides search, stream URL resolution, and waveform data fetching
// against the SoundCloud API v2 endpoint.

import Foundation

final class SoundCloudAPI: ObservableObject {

    // MARK: - Constants

    private static let baseURL = "https://api-v2.soundcloud.com"
    private static let defaultLimit = 25
    private static let maxRetries = 2

    // MARK: - Dependencies

    private let scraper: ClientIDScraper
    private let session: URLSession

    // MARK: - Published State

    @Published private(set) var isSearching: Bool = false
    @Published private(set) var lastError: String?

    // MARK: - Init

    init(scraper: ClientIDScraper, session: URLSession = .shared) {
        self.scraper = scraper
        self.session = session
    }

    // MARK: - Search Tracks

    /// Searches SoundCloud for tracks matching the given query.
    /// Automatically retries with a refreshed client_id on 401/403.
    func searchTracks(query: String, limit: Int = defaultLimit, offset: Int = 0) async throws -> SearchResponse {
        let clientID = try await scraper.getClientID()
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query

        let urlString = "\(Self.baseURL)/search/tracks?q=\(encodedQuery)&client_id=\(clientID)&limit=\(limit)&offset=\(offset)&linked_partitioning=1"

        return try await performRequest(
            urlString: urlString,
            decodeAs: SearchResponse.self,
            retryCount: 0
        )
    }

    /// Fetches the next page of search results using the `next_href` from a previous response.
    func searchTracksNextPage(nextHref: String) async throws -> SearchResponse {
        var urlString = nextHref
        if !urlString.contains("client_id=") {
            let clientID = try await scraper.getClientID()
            let separator = urlString.contains("?") ? "&" : "?"
            urlString += "\(separator)client_id=\(clientID)"
        }

        return try await performRequest(
            urlString: urlString,
            decodeAs: SearchResponse.self,
            retryCount: 0
        )
    }

    // MARK: - Resolve Track by ID

    // MARK: - User & Authentication API

    /// Resolves any SoundCloud URL (e.g. soundcloud.com/username or track permalink)
    func resolveURL(url: String) async throws -> SoundCloudUser {
        let clientID = try await scraper.getClientID()
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullURL = cleanURL.hasPrefix("http") ? cleanURL : "https://soundcloud.com/\(cleanURL)"
        let encoded = fullURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fullURL
        let urlString = "\(Self.baseURL)/resolve?url=\(encoded)&client_id=\(clientID)"

        return try await performRequest(
            urlString: urlString,
            decodeAs: SoundCloudUser.self,
            retryCount: 0
        )
    }

    /// Fetches the authenticated user's profile using OAuth token
    func getMe(oauthToken: String) async throws -> SoundCloudUser {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/me?client_id=\(clientID)"

        return try await performRequest(
            urlString: urlString,
            decodeAs: SoundCloudUser.self,
            headers: ["Authorization": "OAuth \(oauthToken)"],
            retryCount: 0
        )
    }

    /// Fetches all of a user's liked tracks via /users/{id}/track_likes (the
    /// endpoint soundcloud.com uses), following `next_href` across pages.
    func getUserTrackLikes(userID: Int, oauthToken: String, maxItems: Int = defaultMaxSyncItems) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/users/\(userID)/track_likes?client_id=\(clientID)&limit=\(Self.syncPageSize)&linked_partitioning=1"
        let items: [LikeItem] = try await fetchAllPages(
            firstURL: urlString,
            headers: ["Authorization": "OAuth \(oauthToken)"],
            maxItems: maxItems
        )
        return items.compactMap { $0.track }
    }

    /// Likes (PUT) or unlikes (DELETE) a single track on the user's account.
    /// Unliking a track that isn't liked (404) counts as success.
    func setTrackLiked(_ liked: Bool, trackID: Int, userID: Int, oauthToken: String) async throws {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/users/\(userID)/track_likes/\(trackID)?client_id=\(clientID)"
        do {
            _ = try await performRawRequest(
                urlString: urlString,
                method: liked ? "PUT" : "DELETE",
                headers: ["Authorization": "OAuth \(oauthToken)"]
            )
        } catch APIError.httpError(statusCode: 404) where !liked {
            return
        }
    }

    /// Fetches all of the authenticated user's liked tracks via /me/likes/tracks,
    /// following `next_href` until every page is loaded (or `maxItems` is reached).
    func getMeLikesTracks(oauthToken: String, maxItems: Int = defaultMaxSyncItems) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/me/likes/tracks?client_id=\(clientID)&limit=\(Self.syncPageSize)&linked_partitioning=1"
        let items: [LikeItem] = try await fetchAllPages(
            firstURL: urlString,
            headers: ["Authorization": "OAuth \(oauthToken)"],
            maxItems: maxItems
        )
        return items.compactMap { $0.track }
    }

    /// Fetches all of the authenticated user's playlists via /me/playlists (paginated).
    func getMePlaylists(oauthToken: String, maxItems: Int = defaultMaxSyncItems) async throws -> [SoundCloudPlaylist] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/me/playlists?client_id=\(clientID)&limit=\(Self.syncPageSize)&linked_partitioning=1"
        return try await fetchAllPages(
            firstURL: urlString,
            headers: ["Authorization": "OAuth \(oauthToken)"],
            maxItems: maxItems
        )
    }

    /// Fetches all of a user's liked tracks (paginated). Liked playlists in the
    /// mixed likes feed are skipped.
    func getUserLikes(userID: Int, oauthToken: String? = nil, maxItems: Int = defaultMaxSyncItems) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/users/\(userID)/likes?client_id=\(clientID)&limit=\(Self.syncPageSize)&linked_partitioning=1"
        let items: [LikeItem] = try await fetchAllPages(
            firstURL: urlString,
            headers: Self.authHeaders(oauthToken),
            maxItems: maxItems
        )
        return items.compactMap { $0.track }
    }

    /// Fetches all of a user's public playlists (paginated).
    func getUserPlaylists(userID: Int, oauthToken: String? = nil, maxItems: Int = defaultMaxSyncItems) async throws -> [SoundCloudPlaylist] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/users/\(userID)/playlists?client_id=\(clientID)&limit=\(Self.syncPageSize)&linked_partitioning=1"
        return try await fetchAllPages(
            firstURL: urlString,
            headers: Self.authHeaders(oauthToken),
            maxItems: maxItems
        )
    }

    // MARK: - Pagination

    /// Page size requested for library sync calls.
    private static let syncPageSize = 50
    /// Safety cap so a huge library can't loop forever.
    static let defaultMaxSyncItems = 5000

    private static func authHeaders(_ oauthToken: String?) -> [String: String]? {
        guard let token = oauthToken, !token.isEmpty else { return nil }
        return ["Authorization": "OAuth \(token)"]
    }

    /// A like entry: either a bare track or a `{ "track": {...} }` wrapper
    /// (liked playlists decode with `track == nil`).
    private struct LikeItem: Decodable {
        let track: Track?

        private enum CodingKeys: String, CodingKey { case track }

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: CodingKeys.self),
               container.contains(.track) {
                track = try? container.decode(Track.self, forKey: .track)
            } else {
                track = try? Track(from: decoder)
            }
        }
    }

    /// Decodes an element if possible, otherwise yields nil, so one malformed
    /// item (e.g. a removed track) doesn't discard the whole page.
    private struct Lossy<Element: Decodable>: Decodable {
        let value: Element?
        init(from decoder: Decoder) throws {
            value = try? Element(from: decoder)
        }
    }

    private struct Page<Element: Decodable>: Decodable {
        let collection: [Lossy<Element>]
        let nextHref: String?

        enum CodingKeys: String, CodingKey {
            case collection
            case nextHref = "next_href"
        }
    }

    /// Fetches `firstURL` and follows `next_href` until there are no more pages
    /// or `maxItems` items have been collected. An error on the first page is
    /// thrown; an error on a later page stops and returns what was loaded.
    private func fetchAllPages<Element: Decodable>(
        firstURL: String,
        headers: [String: String]?,
        maxItems: Int
    ) async throws -> [Element] {
        var results: [Element] = []
        var nextURL: String? = firstURL
        var visited = Set<String>()
        let decoder = JSONDecoder()

        while let urlString = nextURL, results.count < maxItems, visited.insert(urlString).inserted {
            let data: Data
            do {
                data = try await performRawRequest(urlString: urlString, headers: headers)
            } catch {
                if results.isEmpty { throw error }
                print("[SoundCloudAPI] Pagination stopped after \(results.count) items: \(error.localizedDescription)")
                break
            }

            if let page = try? decoder.decode(Page<Element>.self, from: data) {
                let items = page.collection.compactMap { $0.value }
                results.append(contentsOf: items)
                if page.collection.isEmpty {
                    break
                }
                nextURL = try await withClientID(page.nextHref)
            } else if let array = try? decoder.decode([Lossy<Element>].self, from: data) {
                // Non-partitioned response: a bare array with no next page link.
                results.append(contentsOf: array.compactMap { $0.value })
                break
            } else if results.isEmpty {
                throw APIError.decodingFailed(underlying: DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Unrecognized collection response from \(urlString)")
                ))
            } else {
                break
            }
        }

        return Array(results.prefix(maxItems))
    }

    /// `next_href` links usually omit client_id; append the current one if needed.
    private func withClientID(_ href: String?) async throws -> String? {
        guard let href = href, !href.isEmpty else { return nil }
        if href.contains("client_id=") { return href }
        let clientID = try await scraper.getClientID()
        let separator = href.contains("?") ? "&" : "?"
        return "\(href)\(separator)client_id=\(clientID)"
    }

    /// Fetches artists/users followed by the user
    func getUserFollowings(userID: Int, oauthToken: String? = nil, limit: Int = 30) async throws -> [SoundCloudUser] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/users/\(userID)/followings?client_id=\(clientID)&limit=\(limit)"
        var headers: [String: String]? = nil
        if let token = oauthToken, !token.isEmpty {
            headers = ["Authorization": "OAuth \(token)"]
        }

        struct FollowingsResponse: Codable {
            let collection: [SoundCloudUser]
        }

        let data = try await performRawRequest(urlString: urlString, headers: headers)
        if let resp = try? JSONDecoder().decode(FollowingsResponse.self, from: data) {
            return resp.collection
        }
        if let arr = try? JSONDecoder().decode([SoundCloudUser].self, from: data) {
            return arr
        }
        return []
    }

    /// Fetches related / recommended tracks for a given track ID
    func getRelatedTracks(trackID: Int, limit: Int = 15) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/tracks/\(trackID)/related?client_id=\(clientID)&limit=\(limit)"

        let response = try await performRequest(
            urlString: urlString,
            decodeAs: SearchResponse.self,
            retryCount: 0
        )
        return response.collection
    }

    // MARK: - Generic Networking Helper

    private func performRequest<T: Decodable>(
        urlString: String,
        decodeAs type: T.Type,
        headers: [String: String]? = nil,
        retryCount: Int = 0
    ) async throws -> T {
        let data = try await performRawRequest(urlString: urlString, headers: headers, retryCount: retryCount)
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decodingFailed(underlying: error)
        }
    }

    private func performRawRequest(
        urlString: String,
        method: String = "GET",
        headers: [String: String]? = nil,
        retryCount: Int = 0
    ) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Signed-in requests always use the current access token, renewed
        // first if it is about to expire
        var headers = headers ?? [:]
        let sentToken: String?
        if headers["Authorization"] != nil, let token = await SoundCloudAuthManager.shared.validAccessToken() {
            headers["Authorization"] = "OAuth \(token)"
            sentToken = token
        } else {
            sentToken = nil
        }
        for (key, val) in headers {
            request.setValue(val, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // A rejected access token: renew it once and retry
        if httpResponse.statusCode == 401, let sentToken = sentToken, retryCount < Self.maxRetries,
           await SoundCloudAuthManager.shared.renewAccessToken(replacing: sentToken) != nil {
            return try await performRawRequest(
                urlString: urlString,
                method: method,
                headers: headers,
                retryCount: retryCount + 1
            )
        }

        if (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) && retryCount < Self.maxRetries {
            try await scraper.refreshClientID()
            let newClientID = try await scraper.getClientID()
            let refreshedURLString = replaceClientID(in: urlString, with: newClientID)
            return try await performRawRequest(
                urlString: refreshedURLString,
                method: method,
                headers: headers,
                retryCount: retryCount + 1
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
    }

    // MARK: - Session Refresh

    enum TokenRefreshError: Error {
        /// SoundCloud no longer accepts the refresh token: sign in again
        case rejected
        /// Network or server trouble: try again later
        case unavailable
    }

    /// Trades a refresh token for a new access token, the way soundcloud.com
    /// keeps its session alive. The refresh token is single use; the
    /// response carries the next one.
    func refreshAccessToken(refreshToken: String, clientID: String?) async throws -> (accessToken: String, refreshToken: String?) {
        guard let url = URL(string: "https://secure.soundcloud.com/oauth/token") else {
            throw TokenRefreshError.unavailable
        }
        var resolvedClientID = clientID
        if resolvedClientID == nil {
            resolvedClientID = try? await scraper.getClientID()
        }
        guard let clientID = resolvedClientID else { throw TokenRefreshError.unavailable }

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // "+" in a form body means a space, so encode it
        request.httpBody = form.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        request.timeoutInterval = 15

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            throw TokenRefreshError.unavailable
        }
        if [400, 401, 403].contains(http.statusCode) { throw TokenRefreshError.rejected }
        guard (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw TokenRefreshError.unavailable
        }
        return (accessToken, json["refresh_token"] as? String)
    }

    /// Resolves the direct stream URL for a track.
    /// Standard prefers the smallest stream (128 kbps MP3, else 96 kbps AAC);
    /// High prefers 160 kbps AAC; Best tries Go+ 256 kbps first.
    func resolveStreamURL(for track: Track) async throws -> URL {
        guard let transcodings = track.media?.transcodings, !transcodings.isEmpty else {
            throw APIError.noTranscodings
        }
        // Encrypted (DRM) streams can't be played by AVPlayer; tracks that
        // only offer those fail right away instead of trying each one
        let playable = transcodings.filter { $0.isProgressive || $0.isHLS }
        guard !playable.isEmpty else { throw APIError.noStreamURL }

        let quality = AppSettings.shared.audioQuality
        let token = SoundCloudAuthManager.shared.oauthToken
        let sorted = playable.sorted {
            transcodingPriority($0, quality: quality) > transcodingPriority($1, quality: quality)
        }

        var lastError: Error = APIError.noStreamURL
        for transcoding in sorted {
            let isGoPlus = transcoding.quality == "hq"
            // Go+ streams: only for "Best", and they need the track's
            // authorization and a signed-in account
            if isGoPlus && (quality != .best || track.trackAuthorization == nil || token == nil) { continue }
            do {
                return try await fetchStreamURL(
                    from: transcoding,
                    trackAuthorization: track.trackAuthorization,
                    oauthToken: isGoPlus ? token : nil,
                    // A refused Go+ stream must not trigger a client ID re-scrape
                    allowClientIDRefresh: !isGoPlus
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Ranks the stream formats SoundCloud offers for a track. Presets seen:
    /// mp3 (128 kbps, progressive or HLS), aac_96k, aac_160k, abr_sq
    /// (adaptive AAC), Go+ "hq" AAC 256 kbps, and Ogg Opus.
    private func transcodingPriority(_ transcoding: Transcoding, quality: AudioQuality) -> Int {
        let mime = transcoding.format.mimeType
        // AVPlayer can't play Ogg Opus; keep it as a last resort only
        if mime.contains("ogg") || mime.contains("opus") { return 0 }

        let preset = transcoding.preset ?? ""
        // "audio/mpegurl" is a playlist type, not MP3
        let isMP3 = mime.hasPrefix("audio/mpeg") && !mime.contains("mpegurl")
        let isGoPlus = transcoding.quality == "hq"
        var score = 0
        if quality != .standard {
            if isGoPlus { score += 1000 }
            if preset.contains("160") { score += 500 }
            else if preset.hasPrefix("abr") { score += 400 }
            else if isMP3 { score += 300 }
            else if preset.contains("96") { score += 200 }
        } else {
            // Smallest stream first: least data and battery
            if isMP3 { score += 500 }
            else if preset.contains("96") { score += 400 }
            else if preset.hasPrefix("abr") { score += 300 }
            else if preset.contains("160") { score += 200 }
            if isGoPlus { score -= 150 }
        }
        if transcoding.isProgressive {
            score += 100
        } else if transcoding.isHLS {
            score += 50
        }
        return score
    }

    /// Fetches the actual media URL from a transcoding endpoint.
    /// The transcoding URL returns JSON `{ "url": "https://cf-media.sndcdn.com/..." }`.
    private func fetchStreamURL(
        from transcoding: Transcoding,
        trackAuthorization: String?,
        oauthToken: String?,
        allowClientIDRefresh: Bool
    ) async throws -> URL {
        let clientID = try await scraper.getClientID()
        let separator = transcoding.url.contains("?") ? "&" : "?"
        var urlString = "\(transcoding.url)\(separator)client_id=\(clientID)"
        if let auth = trackAuthorization?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&track_authorization=\(auth)"
        }

        let response: StreamURLResponse = try await performRequest(
            urlString: urlString,
            decodeAs: StreamURLResponse.self,
            headers: Self.authHeaders(oauthToken),
            retryCount: allowClientIDRefresh ? 0 : Self.maxRetries
        )

        guard let streamURL = URL(string: response.url) else {
            throw APIError.invalidStreamURL(response.url)
        }

        return streamURL
    }

    // MARK: - Waveform Data

    /// Fetches waveform sample data from the track's waveform URL.
    /// SoundCloud waveform URLs point to JSON with `{ width, height, samples: [Float] }`.
    func fetchWaveform(for track: Track) async throws -> WaveformData {
        guard let waveformURLString = track.waveformURL else {
            throw APIError.noWaveformURL
        }

        let jsonURLString = waveformURLString
            .replacingOccurrences(of: "/w/", with: "/w/json/")
            .replacingOccurrences(of: ".png", with: ".json")

        guard let url = URL(string: jsonURLString) else {
            throw APIError.invalidURL(jsonURLString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.httpError(statusCode: statusCode)
        }

        let decoder = JSONDecoder()
        let waveform = try decoder.decode(WaveformData.self, from: data)
        return waveform
    }

    /// Fetches waveform samples as a float array for UI scrubbers.
    func getWaveformData(for track: Track) async throws -> [Float] {
        let waveform = try await fetchWaveform(for: track)
        return waveform.samples
    }

    /// Replaces the client_id parameter in a URL string with a new value.
    private func replaceClientID(in urlString: String, with newID: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"client_id=[a-zA-Z0-9]+"#, options: []) else {
            return urlString
        }
        let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
        return regex.stringByReplacingMatches(
            in: urlString,
            options: [],
            range: range,
            withTemplate: "client_id=\(newID)"
        )
    }
}

// MARK: - Personalized Home & Playlist Hydration

extension SoundCloudAPI {

    /// Raw `/mixed-selections` response: the personalized sections shown on
    /// soundcloud.com's home page. Returned as Data so it can be cached as-is.
    func getMixedSelectionsData(oauthToken: String?) async throws -> Data {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/mixed-selections?client_id=\(clientID)&limit=10&linked_partitioning=1"
        return try await performRawRequest(urlString: urlString, headers: Self.authHeaders(oauthToken))
    }

    static func decodeSelections(_ data: Data) throws -> [HomeSelection] {
        try JSONDecoder().decode(HomeSelection.Response.self, from: data).selections
    }

    /// All tracks of a home-feed playlist (user or system playlist), in order.
    func getPlaylistTracks(_ playlist: HomePlaylist, oauthToken: String?) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let path: String
        if playlist.isSystemPlaylist, let urn = playlist.urn {
            path = "system-playlists/\(urn)"
        } else {
            path = "playlists/\(playlist.id)"
        }
        let data = try await performRawRequest(
            urlString: "\(Self.baseURL)/\(path)?client_id=\(clientID)",
            headers: Self.authHeaders(oauthToken)
        )
        let full = try JSONDecoder().decode(HomePlaylist.self, from: data)
        return try await hydrate(tracks: full.tracks, orderedIDs: full.trackIDs, oauthToken: oauthToken)
    }

    /// All tracks of a user playlist by numeric ID, in order.
    func getPlaylistTracks(playlistID: Int, oauthToken: String?) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let data = try await performRawRequest(
            urlString: "\(Self.baseURL)/playlists/\(playlistID)?client_id=\(clientID)",
            headers: Self.authHeaders(oauthToken)
        )
        let full = try JSONDecoder().decode(HomePlaylist.self, from: data)
        return try await hydrate(tracks: full.tracks, orderedIDs: full.trackIDs, oauthToken: oauthToken)
    }

    /// A user's own uploads, newest first.
    func getUserTracks(userID: Int, oauthToken: String?, maxItems: Int = 100) async throws -> [Track] {
        let clientID = try await scraper.getClientID()
        let urlString = "\(Self.baseURL)/users/\(userID)/tracks?client_id=\(clientID)&limit=50&linked_partitioning=1"
        return try await fetchAllPages(firstURL: urlString, headers: Self.authHeaders(oauthToken), maxItems: maxItems)
    }

    /// Fetches full track objects by ID (50 per request), keeping input order.
    func getTracks(ids: [Int], oauthToken: String?) async throws -> [Track] {
        guard !ids.isEmpty else { return [] }
        let clientID = try await scraper.getClientID()
        var byID: [Int: Track] = [:]
        for start in stride(from: 0, to: ids.count, by: 50) {
            let chunk = ids[start..<min(start + 50, ids.count)]
            let idList = chunk.map(String.init).joined(separator: ",")
            let data = try await performRawRequest(
                urlString: "\(Self.baseURL)/tracks?ids=\(idList)&client_id=\(clientID)",
                headers: Self.authHeaders(oauthToken)
            )
            let tracks = (try? JSONDecoder().decode([Lossy<Track>].self, from: data))?.compactMap { $0.value } ?? []
            for track in tracks { byID[track.id] = track }
        }
        return ids.compactMap { byID[$0] }
    }

    /// Playlists only embed the first few tracks fully; fetch the rest by ID.
    private func hydrate(tracks: [Track], orderedIDs: [Int], oauthToken: String?) async throws -> [Track] {
        guard !orderedIDs.isEmpty else { return tracks }
        var byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let missing = orderedIDs.filter { byID[$0] == nil }
        if !missing.isEmpty {
            for track in try await getTracks(ids: missing, oauthToken: oauthToken) {
                byID[track.id] = track
            }
        }
        return orderedIDs.compactMap { byID[$0] }
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingFailed(underlying: Error)
    case noTranscodings
    case noStreamURL
    case invalidStreamURL(String)
    case noWaveformURL

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .httpError(let code):
            return "Server returned HTTP \(code)."
        case .decodingFailed(let err):
            return "Failed to decode response: \(err.localizedDescription)"
        case .noTranscodings:
            return "This track has no available stream transcodings."
        case .noStreamURL:
            return "Could not resolve a stream URL for this track."
        case .invalidStreamURL(let url):
            return "Invalid stream URL received: \(url)"
        case .noWaveformURL:
            return "This track has no waveform data URL."
        }
    }
}

// MARK: - Cancellation

extension Error {
    /// A request that was cancelled (its task or view went away), which
    /// isn't a failure worth showing.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return (self as NSError).domain == NSURLErrorDomain && (self as NSError).code == NSURLErrorCancelled
    }
}
