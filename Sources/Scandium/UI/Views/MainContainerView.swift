// MainContainerView.swift — Root container with 4-tab system, glass tab bar & floating mini-player
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

enum ScandiumTab: Int, CaseIterable {
    case home = 0
    case search = 1
    case library = 2
    case profile = 3

    func title(settings: AppSettings) -> String {
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
        ZStack(alignment: .bottom) {
            ScandiumTheme.bgPrimary.ignoresSafeArea()

            // All tabs stay alive so each keeps its navigation stack and
            // scroll position while you switch between them.
            tabStack(.home) {
                DiscoverView(onNavigateToLibrary: { selectedTab = .library })
            }
            tabStack(.search) { SearchView() }
            tabStack(.library) { LibraryView() }
            tabStack(.profile) { ProfileView() }

            // Floating Mini Player & Bottom TabBar (Seamless at bottom Home Indicator)
            VStack(spacing: 0) {
                if player.currentTrack != nil {
                    FloatingMiniPlayer(onTap: {
                        showFullPlayer = true
                    })
                }

                bottomTabBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .bottom)
        .accentColor(settings.accentColor.color)
        .preferredColorScheme(settings.themeMode.colorScheme)
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView()
                .environmentObject(player)
                .environmentObject(api)
                .environmentObject(scraper)
                .environmentObject(library)
        }
        .overlay(alignment: .top) {
            if let message = library.likeSyncError {
                likeErrorBanner(message)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: library.likeSyncError)
        .onAppear {
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

    /// Wraps a tab's root screen in its own navigation stack with a large title.
    private func tabStack<Content: View>(_ tab: ScandiumTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationView {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AmbientCanvasBackground(artworkURL: player.currentTrack?.artworkURL(size: .t500x500)))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .opacity(selectedTab == tab ? 1 : 0)
        .allowsHitTesting(selectedTab == tab)
        .accessibilityHidden(selectedTab != tab)
    }

    // MARK: - Bottom TabBar (Seamless dark translucent with thin SF symbols)

    private var bottomTabBar: some View {
        VStack(spacing: 0) {
            // Hairline top border
            HairlineDivider()

            HStack(spacing: 0) {
                ForEach(ScandiumTab.allCases, id: \.rawValue) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: selectedTab == tab ? .semibold : .light))
                                .foregroundColor(selectedTab == tab ? ScandiumTheme.textPrimary : ScandiumTheme.subtext)

                            Text(tab.title(settings: settings))
                                .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundColor(selectedTab == tab ? ScandiumTheme.textPrimary : ScandiumTheme.subtext)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 24) // Extra bottom padding for iPhone 11 Home indicator
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(ScandiumTheme.bgPrimary.opacity(0.85))
            }
        )
    }

    // MARK: - Initialization

    private func initializeClientID() {
        Task {
            _ = try? await scraper.getClientID()
        }
    }
}
