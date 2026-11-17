// HomeFeed.swift — Models for SoundCloud's personalized home (/mixed-selections)
//
// The home page on soundcloud.com is a list of "selections" ("Made for you",
// "Recently Played", "More of what you like", "Your Mixes", stations, ...).
// Each selection holds playlists, system playlists or users.

import Foundation

struct HomeSelection: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let items: [HomeItem]

    private enum CodingKeys: String, CodingKey {
        case id = "urn"
        case title, description, items
    }

    private struct ItemPage: Decodable {
        let collection: [LossyItem]
    }

    private struct LossyItem: Decodable {
        let value: HomeItem?
        init(from decoder: Decoder) throws {
            value = try? HomeItem(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        let page = try? container.decode(ItemPage.self, forKey: .items)
        var seen = Set<String>()
        items = (page?.collection.compactMap { $0.value } ?? []).filter { seen.insert($0.id).inserted }
    }

    struct Response: Decodable {
        let collection: [Lossy]

        struct Lossy: Decodable {
            let value: HomeSelection?
            init(from decoder: Decoder) throws {
                value = try? HomeSelection(from: decoder)
            }
        }

        var selections: [HomeSelection] {
            collection.compactMap { $0.value }.filter { !$0.items.isEmpty && !$0.title.isEmpty }
        }
    }
}

enum HomeItem: Decodable, Identifiable {
    case playlist(HomePlaylist)
    case user(SoundCloudUser)

    var id: String {
        switch self {
        case .playlist(let playlist): return "p:\(playlist.id)"
        case .user(let user): return "u:\(user.id)"
        }
    }

    private enum CodingKeys: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "user":
            self = .user(try SoundCloudUser(from: decoder))
        case "playlist", "system-playlist":
            self = .playlist(try HomePlaylist(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unsupported kind \(kind)")
        }
    }
}

/// A user playlist or a system playlist (Daily Drops, Weekly Wave, mixes,
/// stations). Only the first few tracks come fully populated; the rest are
/// IDs that have to be fetched separately.
struct HomePlaylist: Decodable, Identifiable, Hashable {
    let id: String
    let urn: String?
    let kind: String
    let title: String
    let description: String?
    let artworkURL: String?
    let user: SoundCloudUser?
    let trackCount: Int?
    /// Fully populated tracks (usually a prefix of the playlist).
    let tracks: [Track]
    /// Every track ID in playlist order.
    let trackIDs: [Int]

    var isSystemPlaylist: Bool { kind == "system-playlist" }

    private enum CodingKeys: String, CodingKey {
        case id, urn, kind, title, description, user, tracks
        case artworkURL = "artwork_url"
        case calculatedArtworkURL = "calculated_artwork_url"
        case trackCount = "track_count"
    }

    private struct TrackEntry: Decodable {
        let id: Int?
        let track: Track?

        private enum CodingKeys: String, CodingKey { case id }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decode(Int.self, forKey: .id)
            track = try? Track(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        urn = try? container.decodeIfPresent(String.self, forKey: .urn)
        kind = (try? container.decode(String.self, forKey: .kind)) ?? "playlist"
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        let artwork = try? container.decodeIfPresent(String.self, forKey: .artworkURL)
        let calculated = try? container.decodeIfPresent(String.self, forKey: .calculatedArtworkURL)
        artworkURL = artwork ?? calculated
        user = try? container.decodeIfPresent(SoundCloudUser.self, forKey: .user)
        trackCount = try? container.decodeIfPresent(Int.self, forKey: .trackCount)

        let entries = (try? container.decodeIfPresent([TrackEntry].self, forKey: .tracks)) ?? []
        tracks = entries.compactMap { $0.track }
        trackIDs = entries.compactMap { $0.id ?? $0.track?.id }
    }

    /// Large artwork, falling back to the first track's or the owner's image.
    var highResArtworkURL: URL? {
        let raw = artworkURL ?? tracks.first?.artworkURL ?? user?.avatarURL
        guard let raw = raw else { return nil }
        return URL(string: Track.upgradeArtwork(urlString: raw, to: .t500x500))
    }

    static func == (lhs: HomePlaylist, rhs: HomePlaylist) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
