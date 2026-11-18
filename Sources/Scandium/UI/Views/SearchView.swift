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
        List {
            if !hasSearched && tracks.isEmpty {
                historySection
            } else if let error = errorMessage {
                errorRow(error)
            } else if isLoading && tracks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .plainListRow()
            } else if tracks.isEmpty {
                messageRow("No results. Try a different song or artist.")
            } else {
                resultRows
            }
            MiniPlayerSpacerRow()
        }
        .listStyle(PlainListStyle())
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

    // MARK: - Results

    @ViewBuilder
    private var resultRows: some View {
        ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
            GlassTrackRow(
                track: track,
                isCurrentlyPlaying: player.currentTrack?.id == track.id,
                onTap: { player.playQueue(tracks, startingAt: index) }
            )
            .plainListRow()
            .onAppear {
                // Load the next page shortly before the end
                if index == tracks.count - 3 { loadMoreResults() }
            }
        }
        if isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .plainListRow()
        }
    }

    // MARK: - Search History

    @ViewBuilder
    private var historySection: some View {
        if searchHistory.isEmpty {
            messageRow("Search SoundCloud for songs and artists.")
        } else {
            Section(header: HStack {
                Text("Recent Searches")
                Spacer()
                Button("Clear", action: clearSearchHistory)
                    .font(.subheadline)
            }) {
                ForEach(searchHistory, id: \.self) { item in
                    Button(action: { triggerSearchKeyword(item) }) {
                        Label(item, systemImage: "clock.arrow.circlepath")
                            .foregroundColor(.primary)
                    }
                }
                // Swipe left to delete an entry
                .onDelete { offsets in
                    offsets.map { searchHistory[$0] }.forEach(removeSearchHistoryItem)
                }
            }
        }
    }

    private func triggerSearchKeyword(_ keyword: String) {
        searchText = keyword
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        performSearch()
    }

    // MARK: - Messages

    private func messageRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .plainListRow()
    }

    private func errorRow(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Couldn't search: \(message)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: performSearch)
                .buttonStyle(BorderedButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .plainListRow()
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
