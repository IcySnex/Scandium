// FullPlayerView.swift — Now Playing, presented as a native sheet
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct FullPlayerView: View {
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var library: LibraryManager
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var auth = SoundCloudAuthManager.shared

    @State private var waveformSamples: [Float] = []
    @State private var showQueueSheet: Bool = false

    private let playbackRates: [Float] = [0.8, 1.0, 1.25, 1.5, 2.0]

    init() {}

    var body: some View {
        GeometryReader { geometry in
            let artSize = max(1, min(geometry.size.width - 48, geometry.size.height * 0.42))

            VStack(spacing: 0) {
                // Grabber, like the Music app: swipe down anywhere to close
                Capsule()
                    .fill(Color(UIColor.tertiaryLabel))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)

                Spacer(minLength: 12)

                CachedAsyncImage(
                    url: player.currentTrack?.highResArtworkURL,
                    width: artSize,
                    height: artSize,
                    cornerRadius: 10
                )

                Spacer(minLength: 16)

                trackInfoSection
                Spacer(minLength: 12)
                PlayerScrubberSection(
                    clock: player.clock,
                    samples: settings.showWaveform ? waveformSamples : []
                )
                Spacer(minLength: 8)
                controlsSection
                Spacer(minLength: 8)
                volumeSection
                Spacer(minLength: 12)
                bottomBarSection
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(ScandiumTheme.bgPrimary.ignoresSafeArea())
        .accentColor(settings.accentColor.color)
        .preferredColorScheme(settings.themeMode.colorScheme)
        .onAppear { loadWaveform() }
        .onChange(of: player.currentTrack?.id) { _ in loadWaveform() }
        .onChange(of: settings.showWaveform) { _ in loadWaveform() }
        .sheet(isPresented: $showQueueSheet) {
            QueueSheetView()
                .environmentObject(player)
                .environmentObject(library)
        }
    }

    // MARK: - Title, Artist & Like

    private var trackInfoSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.currentTrack?.title ?? "Not Playing")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(player.currentTrack?.user?.username ?? " ")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let track = player.currentTrack {
                let isLiked = library.isLiked(track: track)
                Button(action: { library.toggleLike(track: track) }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundColor(isLiked ? .accentColor : .secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PlainButtonStyle())
                // Likes need an account they can be saved to
                .disabled(!auth.canSyncLikes)
                .opacity(auth.canSyncLikes ? 1 : 0.4)
            }
        }
    }

    // MARK: - Transport Controls

    private var controlsSection: some View {
        HStack(spacing: 0) {
            controlButton("shuffle", size: 19, isOn: player.isShuffleEnabled) { player.toggleShuffle() }
            Spacer()
            controlButton("backward.fill", size: 30) { player.previousTrack() }
            Spacer()
            controlButton(player.playbackState.isPlaying ? "pause.fill" : "play.fill", size: 42) {
                player.togglePlayPause()
            }
            .frame(width: 64)
            Spacer()
            controlButton("forward.fill", size: 30) { player.nextTrack() }
            Spacer()
            controlButton(player.repeatMode == .one ? "repeat.1" : "repeat", size: 19,
                          isOn: player.repeatMode != .off) { player.cycleRepeatMode() }
                .accessibilityLabel(player.repeatMode == .one ? "Repeat One" : player.repeatMode == .all ? "Repeat All" : "Repeat Off")
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, isOn: Bool? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundColor(isOn.map { $0 ? .accentColor : .secondary } ?? .primary)
                .frame(minWidth: 44, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Volume

    private var volumeSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            PlayerVolumeSlider(
                value: Binding(
                    get: { Double(player.playbackVolume) },
                    set: { player.setPlaybackVolume(Float($0)) }
                )
            )
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Speed & Queue

    private var bottomBarSection: some View {
        HStack {
            // Fixed width, so "1.25x" doesn't shift anything
            Button(action: cyclePlaybackRate) {
                Text(formatSpeed(player.playbackRate))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(player.playbackRate == 1.0 ? .secondary : .accentColor)
                    .frame(width: 56, height: 30)
                    .background(Color(UIColor.tertiarySystemFill))
                    .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Playback speed")

            Spacer()

            Button(action: { showQueueSheet = true }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18))
                    .foregroundColor(player.queue.isEmpty ? Color(UIColor.tertiaryLabel) : .secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(player.queue.isEmpty)
            .accessibilityLabel("Queue")
        }
    }

    private func cyclePlaybackRate() {
        let current = player.playbackRate
        if let idx = playbackRates.firstIndex(where: { abs($0 - current) < 0.05 }) {
            player.setPlaybackRate(playbackRates[(idx + 1) % playbackRates.count])
        } else {
            player.setPlaybackRate(1.0)
        }
    }

    private func formatSpeed(_ rate: Float) -> String {
        rate == Float(Int(rate)) ? String(format: "%.0fx", rate) : String(format: "%.2gx", rate)
    }

    // MARK: - Waveform Loading

    private func loadWaveform() {
        guard settings.showWaveform, let track = player.currentTrack else {
            waveformSamples = []
            return
        }
        Task {
            let samples = (try? await api.getWaveformData(for: track)) ?? []
            await MainActor.run {
                // Ignore a waveform that arrives after the track changed
                if player.currentTrack?.id == track.id { waveformSamples = samples }
            }
        }
    }
}

// MARK: - Volume Slider (App Playback Volume)

struct PlayerVolumeSlider: View {
    @Binding var value: Double

    var body: some View {
        Slider(value: $value, in: 0...1)
            .accentColor(.secondary)
    }
}

// MARK: - Queue Sheet View

struct QueueSheetView: View {
    @EnvironmentObject var player: AudioPlayerEngine
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject private var settings = AppSettings.shared

    init() {}

    var body: some View {
        NavigationView {
            Group {
                if player.queue.isEmpty {
                    Text("Queue is empty")
                        .font(.subheadline)
                        .foregroundColor(ScandiumTheme.subtext)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(Array(player.queue.enumerated()), id: \.offset) { index, track in
                                GlassTrackRow(
                                    track: track,
                                    isCurrentlyPlaying: index == player.currentIndex,
                                    onTap: { player.play(at: index) }
                                )
                                .id(index)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            }
                        }
                        .listStyle(PlainListStyle())
                        .onAppear { proxy.scrollTo(player.currentIndex, anchor: .top) }
                    }
                }
            }
            .background(ScandiumTheme.bgPrimary.ignoresSafeArea())
            .navigationTitle(player.isShuffleEnabled ? "Queue · Shuffled" : "Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        // Sheets don't inherit the app's accent on iOS 15
        .accentColor(settings.accentColor.color)
        .preferredColorScheme(settings.themeMode.colorScheme)
    }
}

// MARK: - Scrubber (the only part of the player that redraws while playing)

private struct PlayerScrubberSection: View {
    @EnvironmentObject var player: AudioPlayerEngine
    @ObservedObject var clock: PlaybackClock
    let samples: [Float]

    @State private var dragProgress: Double? = nil

    private var duration: TimeInterval { player.duration }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(clock.currentTime / duration, 1)
    }

    private var bufferProgress: Double {
        guard duration > 0 else { return 0 }
        return min(clock.bufferedTime / duration, 1)
    }

    var body: some View {
        let binding = Binding(
            get: { dragProgress ?? progress },
            set: { dragProgress = $0 }
        )
        let seek: (Double) -> Void = { fraction in
            dragProgress = nil
            player.seekToFraction(fraction)
        }

        VStack(spacing: 6) {
            Group {
                if !samples.isEmpty {
                    WaveformScrubber(samples: samples, progress: binding, bufferedProgress: bufferProgress, onSeek: seek)
                } else {
                    SimpleProgressScrubber(progress: binding, onSeek: seek)
                }
            }
            .frame(height: 36)

            HStack {
                Text(Track.formatDuration(clock.currentTime))
                Spacer()
                Text("-" + Track.formatDuration(max(0, duration - clock.currentTime)))
            }
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundColor(ScandiumTheme.subtext)
        }
    }
}
