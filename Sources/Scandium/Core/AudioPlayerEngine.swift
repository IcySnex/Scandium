// AudioPlayerEngine.swift — AVPlayer wrapper with background audio & system media integration
// Project: Scandium | Author: MeoHunter | License: GPL-3.0
//
// Manages a single persistent AVPlayer instance for streaming playback,
// background audio session, MPNowPlayingInfoCenter updates, and MPRemoteCommandCenter handlers.

import Foundation
import UIKit
import AVFoundation
import MediaPlayer
import Combine

final class AudioPlayerEngine: ObservableObject {

    // MARK: - Playback State Enum

    enum PlaybackState: Equatable {
        case idle
        case loading
        case playing
        case paused
        case failed(String)

        var isPlaying: Bool {
            self == .playing
        }
    }

    // MARK: - Published Properties

    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var currentTrack: Track?
    @Published private(set) var duration: TimeInterval = 0

    /// Position and buffer. These change twice a second while playing, so
    /// they are published through `clock` instead of the engine: otherwise
    /// every screen observing the engine would redraw on each tick.
    let clock = PlaybackClock()
    private(set) var currentTime: TimeInterval = 0 {
        didSet { publishClock() }
    }
    private(set) var bufferedTime: TimeInterval = 0 {
        didSet { publishClock() }
    }
    /// No clock updates while the app is in the background (nothing shows them;
    /// the lock screen keeps time from the elapsed time and rate we hand it).
    private var isInForeground = true
    /// Set while a seek is in progress
    private var seekTarget: TimeInterval?
    @Published private(set) var playbackVolume: Float = 1.0
    @Published var playbackRate: Float = 1.0

    // MARK: - Queue & Playback Modes

    /// Tracks in play order. When shuffle is on this is a shuffled copy of
    /// `sourceQueue` with the current track first.
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var isShuffleEnabled: Bool = false
    /// Tracks in the order they were given (the playlist/likes order).
    private var sourceQueue: [Track] = []
    /// Off, the whole queue, or the current track; saved between launches
    @Published private(set) var repeatMode: RepeatMode =
        RepeatMode(rawValue: UserDefaults.standard.integer(forKey: "scandium_repeat_mode")) ?? .off
    private(set) var sleepTimerRemainingSeconds: Int = 0

    // MARK: - Private Properties

    /// Single persistent AVPlayer instance across the entire app lifecycle
    private let player = AVPlayer()
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var sleepTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var artworkImage: UIImage?

    /// Guards against running heavy setup more than once
    private var isSetup: Bool = false

    // MARK: - Dependencies

    private let api: SoundCloudAPI

    // MARK: - Init / Deinit

    init(api: SoundCloudAPI) {
        self.api = api
        self.player.volume = playbackVolume

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.isInForeground = false }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.isInForeground = true
                self?.publishClock()
            }
            .store(in: &cancellables)
        // Heavy setup is deliberately deferred to setupIfNeeded().
        // AVAudioSession.setActive() and MPRemoteCommandCenter must NOT be called
        // before the window is ready (i.e. before the first play() invocation).
    }

    deinit {
        sleepTimer?.invalidate()
        sleepTimer = nil
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        cancellables.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Lazy One-Time Setup

    /// Called once at the start of the first play(track:) invocation.
    /// Activating AVAudioSession and registering MPRemoteCommandCenter targets
    /// before UIWindowScene is ready causes a crash on iOS 15.
    private func setupIfNeeded() {
        guard !isSetup else { return }
        isSetup = true
        configureAudioSession()
        setupPersistentTimeObserver()
        setupRemoteCommandCenter()
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("[Scandium] Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistent Time Observer (Registered Once)

    private func setupPersistentTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite && seconds >= 0 && self.seekTarget == nil {
                self.currentTime = seconds
            }
            self.updateBufferedTime()
        }
    }

    // MARK: - Play Track

    /// Plays a track by resolving its stream URL and replacing the player's current item.
    private func play(track: Track) {
        setupIfNeeded()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentTrack = track
            self.playbackState = .loading
            self.seekTarget = nil
            self.currentTime = 0
            self.duration = track.durationInSeconds
            self.bufferedTime = 0
            self.artworkImage = nil
        }

        LibraryManager.shared.addToRecentlyPlayed(track: track)

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let streamURL = try await self.api.resolveStreamURL(for: track)
                await MainActor.run {
                    self.startPlayback(url: streamURL, track: track)
                }
            } catch {
                await MainActor.run {
                    self.failCurrentTrack(error.localizedDescription)
                }
            }
        }

        fetchArtworkForNowPlaying(track: track)
    }

    /// Plays a track from the queue at a specific index.
    func play(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        currentIndex = index
        play(track: queue[index])
    }

    /// Replaces the queue with `tracks` and starts playback.
    ///
    /// - Parameters:
    ///   - index: The track to start with. `nil` starts at the top, or at a
    ///     random track when shuffling.
    ///   - shuffle: `true` turns shuffle on ("Shuffle" buttons), `false` turns
    ///     it off ("Play All"), `nil` keeps the current mode (tapping a track).
    ///     With shuffle on, the starting track plays first and the rest follow
    ///     in random order.
    func playQueue(_ allTracks: [Track], startingAt index: Int? = nil, shuffle: Bool? = nil) {
        // Tracks that can't be played (DRM-only) never enter the queue. The
        // start index refers to `allTracks`; map it to the first playable
        // track at or after it.
        let tracks = allTracks.filter(\.isPlayable)
        guard !tracks.isEmpty else { return }
        if let shuffle = shuffle {
            isShuffleEnabled = shuffle
        }
        sourceQueue = tracks

        let start: Int? = index.map { requested in
            let clamped = max(0, min(requested, allTracks.count - 1))
            let next = allTracks[clamped...].first(where: \.isPlayable)
            return next.flatMap { track in tracks.firstIndex { $0.id == track.id } } ?? 0
        }
        if isShuffleEnabled {
            let first = start ?? Int.random(in: 0..<tracks.count)
            queue = Self.shuffled(tracks, keepingFirst: first)
            currentIndex = 0
        } else {
            queue = tracks
            currentIndex = start ?? 0
        }
        play(track: queue[currentIndex])
    }

    /// `tracks[first]` followed by the remaining tracks in random order.
    private static func shuffled(_ tracks: [Track], keepingFirst first: Int) -> [Track] {
        var rest = tracks
        let head = rest.remove(at: first)
        return [head] + rest.shuffled()
    }

    // MARK: - Internal Playback Setup

    private func startPlayback(url: URL, track: Track) {
        cancellables.removeAll()

        let newItem = AVPlayerItem(url: url)
        self.playerItem = newItem

        setupItemObservers(item: newItem)

        player.replaceCurrentItem(with: newItem)
        player.play()
        if playbackRate != 1.0 {
            player.rate = playbackRate
        }
        playbackState = .playing

        updateNowPlayingInfo(track: track)
    }

    // MARK: - Item Observers (KVO via Combine)

    private func setupItemObservers(item: AVPlayerItem) {
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay:
                    let itemDuration = CMTimeGetSeconds(item.duration)
                    if itemDuration.isFinite && itemDuration > 0 {
                        self.duration = itemDuration
                    }
                case .failed:
                    self.failCurrentTrack(item.error?.localizedDescription ?? "Playback failed")
                default:
                    break
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePlaybackFinished()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handlePlaybackFailed(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleAudioInterruption(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleAudioRouteChange(notification)
            }
            .store(in: &cancellables)
    }

    // MARK: - Playback Controls

    func resume() {
        player.play()
        if playbackRate != 1.0 {
            player.rate = playbackRate
        }
        playbackState = .playing
        updateNowPlayingElapsedTime()
    }

    func pause() {
        player.pause()
        playbackState = .paused
        updateNowPlayingElapsedTime()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if playbackState == .playing {
            player.rate = rate
        }
        updateNowPlayingElapsedTime()
    }

    func togglePlayPause() {
        switch playbackState {
        case .playing:
            pause()
        case .paused:
            resume()
        case .idle:
            if let track = currentTrack {
                play(track: track)
            } else if !queue.isEmpty {
                play(at: currentIndex)
            }
        default:
            break
        }
    }

    func setPlaybackVolume(_ volume: Float) {
        let clamped = min(max(volume, 0), 1)
        player.volume = clamped
        playbackVolume = clamped
    }
    /// Seeks to a specific time in seconds.
    func seek(to time: TimeInterval) {
        // Show the target position right away, and ignore the player's old
        // position until the seek is done, so a scrubber doesn't jump back.
        seekTarget = time
        currentTime = time
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.seekTarget == time else { return } // a newer seek is running
                self.seekTarget = nil
                self.currentTime = time
                self.updateNowPlayingElapsedTime()
            }
        }
    }

    /// Seeks to a normalized position (0.0 – 1.0).
    func seekToFraction(_ fraction: Double) {
        let targetTime = duration * max(0, min(1, fraction))
        seek(to: targetTime)
    }

    // MARK: - Queue Navigation

    /// Turning shuffle on keeps the current track playing and shuffles the
    /// rest of the queue after it; turning it off restores the original order
    /// and continues from the current track's position in it.
    func toggleShuffle() {
        isShuffleEnabled.toggle()
        guard !queue.isEmpty else { return }
        let current = queue.indices.contains(currentIndex) ? queue[currentIndex] : nil

        if isShuffleEnabled {
            let first = current.flatMap { track in sourceQueue.firstIndex(where: { $0.id == track.id }) } ?? 0
            queue = Self.shuffled(sourceQueue, keepingFirst: first)
            currentIndex = 0
        } else {
            queue = sourceQueue
            currentIndex = current.flatMap { track in sourceQueue.firstIndex(where: { $0.id == track.id }) } ?? 0
        }
    }

    /// Off → repeat the queue → repeat the current track → off
    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "scandium_repeat_mode")
    }

    /// The next track in the queue. At the end it starts over only with
    /// Repeat on; otherwise it continues with similar tracks (Autoplay) or
    /// stops on the last track.
    func nextTrack() {
        guard !queue.isEmpty else { return }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            play(track: queue[currentIndex])
        } else if repeatMode != .off {
            currentIndex = 0
            play(track: queue[0])
        } else if AppSettings.shared.autoPlayRelated, let current = currentTrack {
            continueWithSimilarTracks(after: current)
        } else {
            stopAtEndOfQueue()
        }
    }

    /// Restarts the track when it has played for a few seconds, otherwise
    /// goes back one track. On the first track it restarts it, unless the
    /// queue repeats.
    func previousTrack() {
        guard !queue.isEmpty else { return }
        if currentTime > 3.0 {
            seek(to: 0)
        } else if currentIndex > 0 {
            currentIndex -= 1
            play(track: queue[currentIndex])
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
            play(track: queue[currentIndex])
        } else {
            seek(to: 0)
        }
    }

    /// The queue ran out: pause on the last track, back at its start.
    private func stopAtEndOfQueue() {
        pause()
        seek(to: 0)
    }

    /// Autoplay: appends similar tracks (or tracks by the same artist or
    /// genre) and plays the first of them.
    private func continueWithSimilarTracks(after current: Track) {
        Task {
            let existingIDs = Set(self.queue.map { $0.id })
            var newTracks: [Track] = []
            if let related = try? await api.getRelatedTracks(trackID: current.id, limit: 10) {
                newTracks = related.filter { !existingIDs.contains($0.id) && $0.isPlayable }
            }
            if newTracks.isEmpty {
                let query = current.genre ?? current.user?.username ?? "Chill Hits"
                if let results = try? await api.searchTracks(query: query, limit: 10, offset: 0) {
                    newTracks = results.collection.filter { !existingIDs.contains($0.id) && $0.isPlayable }
                }
            }
            let found = newTracks
            await MainActor.run {
                guard self.currentTrack?.id == current.id else { return } // the user moved on
                if found.isEmpty {
                    self.stopAtEndOfQueue()
                } else {
                    found.forEach(self.enqueue)
                    self.nextTrack()
                }
            }
        }
    }

    /// Appends a track to the end of the queue.
    func enqueue(_ track: Track) {
        guard track.isPlayable else { return }
        queue.append(track)
        sourceQueue.append(track)
    }

    // MARK: - Clock

    private func publishClock() {
        guard isInForeground else { return }
        if clock.currentTime != currentTime { clock.currentTime = currentTime }
        if clock.bufferedTime != bufferedTime { clock.bufferedTime = bufferedTime }
    }

    // MARK: - Buffered Time

    private func updateBufferedTime() {
        guard let item = playerItem else { return }
        if let range = item.loadedTimeRanges.first?.timeRangeValue {
            let buffered = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
            if buffered.isFinite {
                bufferedTime = buffered
            }
        }
    }

    // MARK: - Playback Finished & Failed Handlers

    private func handlePlaybackFinished() {
        // Sleep Timer: Stop at end of current track
        if AppSettings.shared.sleepTimerOption == .endOfTrack {
            AppSettings.shared.sleepTimerOption = .off
            pause()
            currentTime = duration
            updateNowPlayingElapsedTime()
            return
        }

        if repeatMode == .one {
            seek(to: 0)
            resume()
            return
        }
        nextTrack()
    }

    private func handlePlaybackFailed(_ notification: Notification) {
        var message = "Playback failed"
        if let userInfo = notification.userInfo {
            for (_, value) in userInfo {
                if let err = value as? Error {
                    message = err.localizedDescription
                    break
                }
            }
        }
        failCurrentTrack(message)
    }

    /// Marks the current track as failed and, with "Skip Tracks That Fail to
    /// Play" on, moves to the next one, for every kind of failure: the stream
    /// couldn't be resolved, couldn't be loaded, or stopped mid-way.
    private func failCurrentTrack(_ message: String) {
        playbackState = .failed(message)
        guard AppSettings.shared.autoSkipOnError,
              currentIndex + 1 < queue.count || repeatMode == .all else { return }
        let failedID = currentTrack?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self, case .failed = self.playbackState,
                  self.currentTrack?.id == failedID else { return }
            self.nextTrack()
        }
    }

    // MARK: - Audio Interruption & Route Change (Headphone Unplug)

    private func handleAudioRouteChange(_ notification: Notification) {
        guard AppSettings.shared.pauseOnHeadphoneDisconnect,
              let dict = notification.userInfo,
              let reasonValue = dict[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        // When headphones/AirPods disconnect, automatically pause to prevent blasting speakers
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let dict = notification.userInfo else { return }

        var typeRaw: UInt?
        var optionsRaw: UInt?

        for (key, val) in dict {
            let keyStr = String(describing: key)
            if keyStr.contains("InterruptionType") {
                if let num = val as? NSNumber {
                    typeRaw = num.uintValue
                } else if let u = val as? UInt {
                    typeRaw = u
                }
            } else if keyStr.contains("InterruptionOption") {
                if let num = val as? NSNumber {
                    optionsRaw = num.uintValue
                } else if let u = val as? UInt {
                    optionsRaw = u
                }
            }
        }

        guard let raw = typeRaw, let type = AVAudioSession.InterruptionType(rawValue: raw) else {
            return
        }

        switch type {
        case .began:
            pause()
        case .ended:
            if let opt = optionsRaw {
                let options = AVAudioSession.InterruptionOptions(rawValue: opt)
                if options.contains(.shouldResume) {
                    resume()
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Sleep Timer Engine

    func setSleepTimer(_ option: SleepTimerOption) {
        AppSettings.shared.sleepTimerOption = option
        sleepTimer?.invalidate()
        sleepTimer = nil

        switch option {
        case .off, .endOfTrack:
            sleepTimerRemainingSeconds = 0
        case .min15, .min30, .min45, .min60:
            let totalSeconds = option.rawValue * 60
            sleepTimerRemainingSeconds = totalSeconds
            sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                if self.sleepTimerRemainingSeconds > 1 {
                    self.sleepTimerRemainingSeconds -= 1
                } else {
                    self.sleepTimerRemainingSeconds = 0
                    timer.invalidate()
                    self.sleepTimer = nil
                    AppSettings.shared.sleepTimerOption = .off
                    self.pause()
                }
            }
        }
    }

    // MARK: - Now Playing Info (Lock Screen & Control Center)

    private func updateNowPlayingInfo(track: Track) {
        var info = [String: Any]()

        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyArtist] = track.user?.username ?? "Unknown Artist"
        info[MPMediaItemPropertyPlaybackDuration] = track.durationInSeconds
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

        if let albumTitle = track.publisherMetadata?.albumTitle {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }

        if let artwork = artworkImage {
            let mediaArtwork = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
            info[MPMediaItemPropertyArtwork] = mediaArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsedTime() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackState.isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    // MARK: - Artwork Fetching for Now Playing

    private func fetchArtworkForNowPlaying(track: Track) {
        guard let artworkURL = track.highResArtworkURL else { return }

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: artworkURL)
                guard let image = UIImage(data: data) else { return }
                await MainActor.run {
                    self.artworkImage = image
                    if self.currentTrack?.id == track.id {
                        self.updateNowPlayingInfo(track: track)
                    }
                }
            } catch {
                print("[Scandium] Failed to fetch artwork for Now Playing: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if !self.queue.isEmpty {
                self.nextTrack()
                return .success
            }
            return .noActionableNowPlayingItem
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.previousTrack()
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
    }

    // MARK: - Computed Helpers

    /// Normalized progress (0.0 – 1.0).
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    /// Normalized buffer progress (0.0 – 1.0).
    var bufferProgress: Double {
        guard duration > 0 else { return 0 }
        return min(bufferedTime / duration, 1.0)
    }

    /// Formatted total duration string.
    var formattedDuration: String {
        Track.formatDuration(duration)
    }
}

// MARK: - Shared Engine Reference

/// Lets code outside the view hierarchy (e.g. the sleep timer picker) reach the engine.
enum AudioPlayerEngineWrapper {
    static weak var sharedEngine: AudioPlayerEngine?
}

// MARK: - Playback Clock

/// The playing position, observed only by the views that show it.
final class PlaybackClock: ObservableObject {
    @Published fileprivate(set) var currentTime: TimeInterval = 0
    @Published fileprivate(set) var bufferedTime: TimeInterval = 0
}

// MARK: - Repeat Mode

enum RepeatMode: Int {
    case off, all, one
}
