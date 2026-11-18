// GlassTrackRow.swift — Spotify/Threads clean track row
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct GlassTrackRow: View {
    let track: Track
    let isCurrentlyPlaying: Bool
    var showLikeButton: Bool = true
    let onTap: () -> Void

    @EnvironmentObject var library: LibraryManager
    @ObservedObject private var auth = SoundCloudAuthManager.shared

    /// Same width for the duration and the now-playing icon, so the hearts
    /// line up on every row.
    private static let trailingWidth: CGFloat = 44

    init(
        track: Track,
        isCurrentlyPlaying: Bool,
        showLikeButton: Bool = true,
        onTap: @escaping () -> Void
    ) {
        self.track = track
        self.isCurrentlyPlaying = isCurrentlyPlaying
        self.showLikeButton = showLikeButton
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 48x48 Artwork, 6pt radius, clipped
                CachedAsyncImage(
                    url: track.artworkURL(size: .t120x120) ?? track.artworkImageURL,
                    width: 48,
                    height: 48,
                    cornerRadius: 6
                )

                // Track title + Artist
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isCurrentlyPlaying ? ScandiumTheme.spotifyGreen : ScandiumTheme.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Text(track.user?.username ?? "Unknown")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(ScandiumTheme.subtext)
                            .lineLimit(1)

                        if let plays = track.formattedPlaybackCount {
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(ScandiumTheme.subtext.opacity(0.6))
                            Text(plays)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(ScandiumTheme.subtext.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Like Button
                if showLikeButton {
                    let isLiked = library.isLiked(track: track)
                    Button(action: { library.toggleLike(track: track) }) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(isLiked ? ScandiumTheme.spotifyGreen : ScandiumTheme.subtext.opacity(0.5))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(PlainButtonStyle())
                    // Likes need an account they can be saved to
                    .disabled(!auth.canSyncLikes)
                    .opacity(auth.canSyncLikes ? 1 : 0.4)
                }

                Group {
                    if isCurrentlyPlaying {
                        nowPlayingIndicator
                    } else {
                        Text(track.formattedDuration)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(ScandiumTheme.subtext)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(width: Self.trailingWidth, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Now Playing Indicator

    private var nowPlayingIndicator: some View {
        Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 13))
            .foregroundColor(ScandiumTheme.accent)
    }
}
