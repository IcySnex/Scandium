// ScandiumApp.swift — @main entry point with Staged Launch & Safe Mode Crash Report
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI
import AVFoundation

@main
struct ScandiumApp: App {
    @StateObject private var scraper: ClientIDScraper
    @StateObject private var api: SoundCloudAPI
    @StateObject private var player: AudioPlayerEngine
    @StateObject private var library: LibraryManager
    @ObservedObject private var settings = AppSettings.shared

    /// Controls the staged launch: start with a black screen, then mount MainContainerView
    @State private var isUIReady: Bool = false
    /// Safe Mode: shown if a crash was detected from the previous launch
    @State private var showSafeMode: Bool = false

    init() {
        CrashDiagnosticManager.shared.install()

        let scraperInstance = ClientIDScraper()
        let apiInstance = SoundCloudAPI(scraper: scraperInstance)
        let playerInstance = AudioPlayerEngine(api: apiInstance)
        let libraryInstance = LibraryManager.shared

        _scraper = StateObject(wrappedValue: scraperInstance)
        _api = StateObject(wrappedValue: apiInstance)
        _player = StateObject(wrappedValue: playerInstance)
        _library = StateObject(wrappedValue: libraryInstance)

        SoundCloudAuthManager.shared.setAPI(apiInstance)
        AudioPlayerEngineWrapper.sharedEngine = playerInstance

        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Phase 0: Dynamic background baseline matching theme
                ScandiumTheme.bgPrimary
                    .ignoresSafeArea()

                if showSafeMode {
                    // Safe Mode: display crash report and recovery options
                    SafeModeView(
                        crashLog: CrashDiagnosticManager.shared.readCrashLog(),
                        onReset: {
                            CrashDiagnosticManager.shared.clearCacheData()
                            LibraryManager.shared.clearAllData()
                            CrashDiagnosticManager.shared.resetAll()
                            showSafeMode = false
                            mountMainUI()
                        },
                        onContinue: {
                            CrashDiagnosticManager.shared.resetAll()
                            showSafeMode = false
                            mountMainUI()
                        }
                    )
                } else if isUIReady {
                    // Phase 2: Full app UI — mounted AFTER window is ready
                    MainContainerView()
                        .environmentObject(scraper)
                        .environmentObject(api)
                        .environmentObject(player)
                        .environmentObject(library)
                }
            }
            .preferredColorScheme(settings.themeMode.colorScheme)
            .onAppear {
                // Phase 1: Window is now ready — check for previous crash, then mount UI
                let hadCrash = CrashDiagnosticManager.shared.didCrashDuringLastLaunch
                // Mark that we are launching NOW (so if we crash, next launch detects it)
                CrashDiagnosticManager.shared.markLaunchStarted()

                if hadCrash {
                    showSafeMode = true
                } else {
                    mountMainUI()
                }
            }
        }
    }

    // MARK: - Helpers

    private func mountMainUI() {
        // No animation: mounting inside an animation made the first layout of
        // every screen animate in from the top-left corner.
        isUIReady = true
        CrashDiagnosticManager.shared.markLaunchSucceeded()
    }

    private func configureAppearance() {
        // Clear while the page is scrolled to the top, then the system's
        // blurred bar once content scrolls underneath, so titles and buttons
        // stay readable in light and dark mode.
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        let atTop = UINavigationBarAppearance()
        atTop.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = atTop

        // Tab bar: always blurred, since the mini player sits on top of it
        let tabBar = UITabBarAppearance()
        tabBar.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
    }
}

// MARK: - Safe Mode View

struct SafeModeView: View {
    let crashLog: String
    let onReset: () -> Void
    let onContinue: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var showFullLog: Bool = false

    init(crashLog: String, onReset: @escaping () -> Void, onContinue: @escaping () -> Void) {
        self.crashLog = crashLog
        self.onReset = onReset
        self.onContinue = onContinue
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.yellow)
                            Text("Safe Mode")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("Scandium encountered an issue during the previous session. Here is the diagnostic report.")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.655, green: 0.655, blue: 0.655))
                        .lineLimit(nil)
                    }
                    .padding(.top, 60)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Crash Report")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Button(showFullLog ? "Collapse" : "Expand") {
                                showFullLog.toggle()
                            }
                            .font(.system(size: 12))
                            .foregroundColor(settings.accentColor.color)
                        }

                        ScrollView(.vertical) {
                            Text(showFullLog ? crashLog : String(crashLog.prefix(800)) + (crashLog.count > 800 ? "\n…(more)" : ""))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(red: 0.8, green: 0.8, blue: 0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(nil)
                        }
                        .frame(maxHeight: showFullLog ? 400 : 200)
                        .padding(12)
                        .background(Color(red: 0.071, green: 0.071, blue: 0.071))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(spacing: 12) {
                        Button(action: onContinue) {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Continue to App")
                                    .font(.body.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundColor(.white)
                            .background(settings.accentColor.color)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: onReset) {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("Clear All Cache & Reset")
                                    .font(.body.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundColor(.white)
                            .background(Color(red: 0.8, green: 0.15, blue: 0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .preferredColorScheme(.dark)
    }
}
