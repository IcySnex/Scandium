// FloatingMiniPlayer.swift — Spotify/Threads-style sleek floating mini-player
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct FloatingMiniPlayer: View {
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var library: LibraryManager
    let onTap: () -> Void

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    var body: some View {
        if let track = player.currentTrack {
            ZStack(alignment: .bottom) {
                // Main Container Button (tapping anywhere opens Full Player)
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        // Left: 40x40 Square Artwork, 6pt corner radius, clipped
                        CachedAsyncImage(
                            url: track.artworkURL(size: .t120x120) ?? track.artworkImageURL,
                            width: 40,
                            height: 40,
                            cornerRadius: 6
                        )

                        // Middle: Track Title (bold white) + Artist (subtext)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ScandiumTheme.textPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(track.user?.username ?? "Unknown Artist")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(ScandiumTheme.subtext)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Right Controls: Heart + Play/Pause
                        HStack(spacing: 16) {
                            // Minimal Heart
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    library.toggleLike(track: track)
                                }
                            }) {
                                let isLiked = library.isLiked(track: track)
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(isLiked ? ScandiumTheme.spotifyGreen : ScandiumTheme.subtext)
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Minimal Play / Pause
                            Button(action: {
                                player.togglePlayPause()
                            }) {
                                Image(systemName: player.playbackState.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                // Bottom 2pt progress line: the only part that redraws while playing
                MiniPlayerProgressLine(clock: player.clock, duration: player.duration)
            }
            // Solid fill: a live blur behind it would be re-rendered on
            // every scroll frame
            .background(ScandiumTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(ScandiumTheme.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct MiniPlayerProgressLine: View {
    @ObservedObject var clock: PlaybackClock
    let duration: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let fraction = duration > 0 ? min(max(clock.currentTime / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(ScandiumTheme.hairline)
                Rectangle()
                    .fill(ScandiumTheme.accent)
                    .frame(width: geo.size.width * CGFloat(fraction))
            }
        }
        .frame(height: 2)
    }
}
