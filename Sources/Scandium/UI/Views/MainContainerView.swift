// MainContainerView.swift — Root container with 4-tab system, glass tab bar & floating mini-player
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

enum ScandiumTab: Int, CaseIterable {
    case home = 0
    case search = 1
    case library = 2
    case profile = 3

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .library: return "Library"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .library: return "books.vertical"
        case .profile: return "person"
        }
    }
}

struct MainContainerView: View {
    @EnvironmentObject var player: AudioPlayerEngine
    @EnvironmentObject var api: SoundCloudAPI
    @EnvironmentObject var scraper: ClientIDScraper
    @EnvironmentObject var library: LibraryManager
    @ObservedObject private var settings = AppSettings.shared

    @State private var selectedTab: ScandiumTab = .home
    @State private var showFullPlayer: Bool = false

    init() {}

    var body: some View {
        // A native TabView keeps every tab's navigation stack and scroll
        // position alive and handles safe areas and bar layout itself.
        TabView(selection: $selectedTab) {
            tabStack(.home) {
                DiscoverView(onNavigateToLibrary: { selectedTab = .library })
            }
            tabStack(.search) { SearchView() }
            tabStack(.library) { LibraryView() }
            tabStack(.profile) { ProfileView() }
        }
        .overlay(alignment: .bottom) {
            // Sits right above the tab bar
            if player.currentTrack != nil {
                FloatingMiniPlayer(onTap: { showFullPlayer = true })
                    .padding(.bottom, ScandiumTheme.tabBarHeight)
                    .ignoresSafeArea(.keyboard)
            }
        }
        .accentColor(settings.accentColor.color)
        .preferredColorScheme(settings.themeMode.colorScheme)
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView()
                .environmentObject(player)
                .environmentObject(api)
                .environmentObject(scraper)
                .environmentObject(library)
                .accentColor(settings.accentColor.color)
        }
        .overlay(alignment: .top) {
            if let message = library.likeSyncError {
                likeErrorBanner(message)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: library.likeSyncError)
        .onAppear {
            settings.applyWindowTint()
            initializeClientID()
            SoundCloudAuthManager.shared.setAPI(api)
            Task {
                await SoundCloudAuthManager.shared.syncOnLaunchIfNeeded()
            }
        }
    }

    // MARK: - Like Sync Error Banner

    private func likeErrorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.85))
            .clipShape(Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { library.likeSyncError = nil }
            .task(id: message) {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if library.likeSyncError == message {
                    library.likeSyncError = nil
                }
            }
    }

    // MARK: - Tab Stacks

    /// A tab's root screen in its own navigation stack with a large title.
    private func tabStack<Content: View>(_ tab: ScandiumTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationView {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ScandiumTheme.bgPrimary.ignoresSafeArea())
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .tabItem {
            Image(systemName: tab.icon)
            Text(tab.title)
        }
        .tag(tab)
    }

    // MARK: - Initialization

    private func initializeClientID() {
        Task {
            _ = try? await scraper.getClientID()
        }
    }
}
