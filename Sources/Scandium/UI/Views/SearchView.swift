// SearchView.swift — Spotify-style clean track & artist search screen
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var library: LibraryManager

    @State private var searchText: String = ""
    @State private var tracks: [Track] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var nextHref: String?
    @State private var isLoadingMore: Bool = false
    @State private var hasSearched: Bool = false
    @State private var searchHistory: [String] = []

    private static let searchHistoryKey = "scandium_search_history_v1"
    private static let maxSearchHistory = 12

    init() {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 4) {
                if !hasSearched && tracks.isEmpty {
                    recentSearchesSection
                } else if let error = errorMessage {
                    errorView(error)
                } else if isLoading && tracks.isEmpty {
                    ProgressView()
                        .padding(.top, 40)
                } else if tracks.isEmpty {
                    noResultsView
                } else {
                    trackListView
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .navigationTitle("Search")
        // The system search field in the navigation bar
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Songs, artists"
        )
        .disableAutocorrection(true)
        .onSubmit(of: .search) { performSearch() }
        .onChange(of: searchText) { text in
            // Cleared (x or Cancel): back to the search history
            if text.isEmpty {
                tracks = []
                nextHref = nil
                hasSearched = false
                errorMessage = nil
            }
        }
        .onAppear { loadSearchHistory() }
    }

    // MARK: - Track List

    @ViewBuilder
    private var trackListView: some View {
        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
            GlassTrackRow(
                track: track,
                isCurrentlyPlaying: player.currentTrack?.id == track.id,
                showLikeButton: true,
                onTap: {
                    player.playQueue(tracks, startingAt: index)
                }
            )

            if index == tracks.count - 3 && nextHref != nil && !isLoadingMore {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        loadMoreResults()
                    }
            }
        }

        if isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: ScandiumTheme.textPrimary))
                    .padding(.vertical, 16)
                Spacer()
            }
        }
    }

    // MARK: - Search History

    @ViewBuilder
    private var recentSearchesSection: some View {
        if searchHistory.isEmpty {
            Text("Search SoundCloud for songs and artists.")
                .font(.system(size: 14))
                .foregroundColor(ScandiumTheme.subtext)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            recentSearchesList
        }
    }

    private var recentSearchesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Searches")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                Spacer()
                Button(action: clearSearchHistory) {
                    Text("Clear")
                        .font(.system(size: 14))
                        .foregroundColor(ScandiumTheme.accent)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            VStack(spacing: 0) {
                ForEach(searchHistory, id: \.self) { item in
                    HStack(spacing: 12) {
                        Button(action: {
                            triggerSearchKeyword(item)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 14))
                                    .foregroundColor(ScandiumTheme.subtext)

                                Text(item)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(ScandiumTheme.textPrimary)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            removeSearchHistoryItem(item)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ScandiumTheme.subtext.opacity(0.8))
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if item != searchHistory.last {
                        HairlineDivider(leadingPadding: 42)
                    }
                }
            }
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func triggerSearchKeyword(_ keyword: String) {
        searchText = keyword
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        performSearch()
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 50)

            Image(systemName: "music.note.list")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(ScandiumTheme.subtext.opacity(0.4))

            Text("No results found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ScandiumTheme.textPrimary)

            Text("Try searching for a different song or artist.")
                .font(.system(size: 13))
                .foregroundColor(ScandiumTheme.subtext)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 30)

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Color.orange)

            Text("Unable to load results")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ScandiumTheme.textPrimary)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(ScandiumTheme.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: performSearch) {
                Text("Retry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(ScandiumTheme.surfaceElevated)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Search Actions

    private func performSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saveSearchHistoryItem(trimmed)

        isLoading = true
        errorMessage = nil
        hasSearched = true

        Task {
            do {
                let response = try await api.searchTracks(query: trimmed)
                await MainActor.run {
                    self.tracks = deduplicateTracks(response.collection)
                    self.nextHref = response.nextHref
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func loadMoreResults() {
        guard let href = nextHref, !isLoadingMore else { return }
        isLoadingMore = true

        Task {
            do {
                let response = try await api.searchTracksNextPage(nextHref: href)
                await MainActor.run {
                    self.tracks = deduplicateTracks(self.tracks + response.collection)
                    self.nextHref = response.nextHref
                    self.isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingMore = false
                }
            }
        }
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

    private func loadSearchHistory() {
        if let items = UserDefaults.standard.array(forKey: Self.searchHistoryKey) as? [String] {
            searchHistory = items
        }
    }

    private func clearSearchHistory() {
        searchHistory = []
        UserDefaults.standard.removeObject(forKey: Self.searchHistoryKey)
    }

    private func removeSearchHistoryItem(_ keyword: String) {
        searchHistory.removeAll { $0.caseInsensitiveCompare(keyword) == .orderedSame }
        UserDefaults.standard.set(searchHistory, forKey: Self.searchHistoryKey)
    }

    private func saveSearchHistoryItem(_ keyword: String) {
        let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        var history = searchHistory.filter { $0.caseInsensitiveCompare(normalized) != .orderedSame }
        history.insert(normalized, at: 0)
        if history.count > Self.maxSearchHistory {
            history = Array(history.prefix(Self.maxSearchHistory))
        }
        searchHistory = history
        UserDefaults.standard.set(history, forKey: Self.searchHistoryKey)
    }
}
