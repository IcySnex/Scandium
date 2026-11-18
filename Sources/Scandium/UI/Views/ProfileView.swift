// ProfileView.swift — Account and settings, as native grouped lists
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var scraper: ClientIDScraper
    @ObservedObject private var auth = SoundCloudAuthManager.shared
    @ObservedObject private var storage = StorageManager.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var showSignIn = false
    @State private var manualSignIn: ManualSignInSheet.Mode?
    @State private var showLogOutConfirm = false
    @State private var showClearCacheConfirm = false
    @State private var toastMessage: String?

    private static let sourceURL = URL(string: "https://github.com/IcySnex/Scandium")
    private static let originalURL = URL(string: "https://github.com/MeoHunterr/Scandium")

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var manualSignInPresented: Binding<Bool> {
        Binding(get: { manualSignIn != nil }, set: { if !$0 { manualSignIn = nil } })
    }

    private var sleepTimer: Binding<SleepTimerOption> {
        Binding(
            get: { settings.sleepTimerOption },
            set: { option in
                AudioPlayerEngineWrapper.sharedEngine?.setSleepTimer(option)
                settings.sleepTimerOption = option
            }
        )
    }

    var body: some View {
        List {
            accountSection
            appearanceSection
            playbackSection
            storageSection
            advancedSection
            aboutSection
        }
        .listStyle(InsetGroupedListStyle())
        .toggleStyle(SwitchToggleStyle(tint: settings.accentColor.color))
        .navigationTitle("Profile")
        .sheet(isPresented: $showSignIn) {
            SoundCloudLoginSheet(isPresented: $showSignIn, onLoginSuccess: {
                showToast("Signed in")
            })
        }
        .sheet(isPresented: manualSignInPresented) {
            ManualSignInSheet(mode: manualSignIn ?? .token, isPresented: manualSignInPresented) { message in
                showToast(message)
            }
        }
        .confirmationDialog("Log out of SoundCloud?", isPresented: $showLogOutConfirm, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                auth.logout()
                SoundCloudLoginSheet.clearSoundCloudCookies()
                showToast("Logged out")
            }
        }
        .alert(isPresented: $showClearCacheConfirm) {
            Alert(
                title: Text("Clear all cached data?"),
                message: Text("Cached artwork and audio are removed. Your likes and settings are kept."),
                primaryButton: .destructive(Text("Clear")) {
                    storage.clearCache()
                    ImageCacheStore.shared.clear()
                    showToast("Cache cleared")
                },
                secondaryButton: .cancel()
            )
        }
        .overlay(toastOverlay, alignment: .bottom)
        .onAppear { storage.refreshUsage() }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        if auth.isLoggedIn, let user = auth.currentUser {
            Section {
                HStack(spacing: 14) {
                    CachedAsyncImage(url: user.highResAvatarURL, width: 52, height: 52, cornerRadius: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.username)
                            .font(.headline)
                            .lineLimit(1)
                        Text(auth.canSyncLikes
                             ? "\(auth.userLikedTracks.count) likes · \(auth.userPlaylists.count) playlists"
                             : "Public profile · read-only")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Button("Log Out", role: .destructive) { showLogOutConfirm = true }
            }
        } else {
            Section(footer: Text("A public profile is read-only: liking is turned off, and nothing is saved to SoundCloud.")) {
                Button(action: { showSignIn = true }) {
                    Label("Sign in to SoundCloud", systemImage: "person.crop.circle")
                }
                Button(action: { manualSignIn = .token }) {
                    Label("Sign in with a Token", systemImage: "key")
                }
                Button(action: { manualSignIn = .profile }) {
                    Label("Load a Public Profile", systemImage: "link")
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section(header: Text("Appearance")) {
            Picker("Theme", selection: $settings.themeMode) {
                ForEach(AppThemeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            HStack {
                Text("Accent Color")
                Spacer()
                HStack(spacing: 12) {
                    ForEach(AppAccentColor.allCases) { accent in
                        Button(action: {
                            settings.triggerHaptic()
                            settings.accentColor = accent
                        }) {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.black)
                                        .opacity(settings.accentColor == accent ? 1 : 0)
                                )
                        }
                        // Borderless, so only the circle reacts, not the whole row
                        .buttonStyle(BorderlessButtonStyle())
                        .accessibilityLabel(accent.title)
                    }
                }
            }
        }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        Section(header: Text("Playback"), footer: Text("Autoplay keeps playing similar tracks when the queue ends.")) {
            Toggle("Autoplay Similar Tracks", isOn: $settings.autoPlayRelated)
            Toggle("Pause When Headphones Disconnect", isOn: $settings.pauseOnHeadphoneDisconnect)
            Toggle("Skip Tracks That Fail to Play", isOn: $settings.autoSkipOnError)
            Toggle("Waveform Scrubber", isOn: $settings.showWaveform)
            Toggle("Keep Screen Awake", isOn: $settings.keepScreenAwake)
            Toggle("Haptic Feedback", isOn: $settings.enableHaptics)
            Picker("Sleep Timer", selection: sleepTimer) {
                ForEach(SleepTimerOption.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        Section(header: Text("Storage")) {
            cacheRow("Artwork Cache", size: storage.formattedImageCache) {
                storage.clearImageCacheOnly()
                ImageCacheStore.shared.clear()
                showToast("Artwork cache cleared")
            }
            cacheRow("Audio Cache", size: storage.formattedAudioNetwork) {
                storage.clearAudioCacheOnly()
                showToast("Audio cache cleared")
            }
            Button(role: .destructive, action: { showClearCacheConfirm = true }) {
                HStack {
                    Text("Clear All Cached Data")
                    Spacer()
                    Text(storage.formattedTotal).foregroundColor(.secondary)
                }
            }
        }
    }

    private func cacheRow(_ title: String, size: String, clear: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(size).foregroundColor(.secondary)
            Button("Clear", action: clear)
                .buttonStyle(BorderlessButtonStyle())
                .padding(.leading, 12)
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section(header: Text("Advanced")) {
            NavigationLink(destination: ClientIDSettingsView()) {
                HStack {
                    Text("Client ID")
                    Spacer()
                    Text(scraper.manualClientID != nil ? "Custom" : scraper.statusDescription)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section(
            header: Text("About"),
            footer: Text("Not affiliated with or endorsed by SoundCloud.")
                // Room for the mini player below the last section
                .padding(.bottom, 70)
        ) {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion).foregroundColor(.secondary)
            }
            linkRow("Source Code", detail: "By IcySnex · GPL-3.0", url: Self.sourceURL)
            linkRow("Based On", detail: "Scandium by MeoHunter", url: Self.originalURL)
        }
    }

    @ViewBuilder
    private func linkRow(_ title: String, detail: String, url: URL?) -> some View {
        if let url = url {
            Link(destination: url) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundColor(.primary)
                        Text(detail)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = toastMessage {
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(white: 0.15))
                .clipShape(Capsule())
                .padding(.bottom, 80)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                if toastMessage == message { toastMessage = nil }
            }
        }
    }
}

// MARK: - Client ID Settings

/// Status of the automatically detected client ID, plus a manual override.
struct ClientIDSettingsView: View {
    @EnvironmentObject var scraper: ClientIDScraper
    @State private var manualInput = ""
    @State private var isRefreshing = false
    @State private var message: String?

    var body: some View {
        Form {
            Section(
                header: Text("Status"),
                footer: Text("SoundCloud requires a client ID for every request. The app detects one automatically; set your own only if detection keeps failing.")
            ) {
                HStack {
                    Circle()
                        .fill(scraper.lastError == nil ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(scraper.statusDescription)
                    Spacer()
                    if let id = scraper.currentClientID {
                        Text(id.prefix(8) + "…")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                if let error = scraper.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
                Button(action: refresh) {
                    HStack {
                        Text("Detect Again")
                        Spacer()
                        if isRefreshing { ProgressView() }
                    }
                }
                .disabled(isRefreshing)
            }

            Section(header: Text("Custom Client ID"), footer: message.map { Text($0) }) {
                TextField("32-character client ID", text: $manualInput)
                    .font(.system(.body, design: .monospaced))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button("Save") {
                    scraper.setManualClientID(manualInput)
                    message = "Custom client ID saved"
                }
                .disabled(manualInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if scraper.manualClientID != nil {
                    Button("Use Automatic") {
                        scraper.setManualClientID(nil)
                        manualInput = ""
                        message = "Using the detected client ID"
                    }
                }
            }

            Section {
                NavigationLink("How to Find a Client ID", destination: ClientIDGuideView())
            }
        }
        .navigationTitle("Client ID")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            manualInput = scraper.manualClientID ?? ""
        }
    }

    private func refresh() {
        isRefreshing = true
        message = nil
        Task {
            do {
                try await scraper.refreshClientID()
                await MainActor.run { message = "Client ID updated" }
            } catch {
                await MainActor.run { message = error.localizedDescription }
            }
            await MainActor.run { isRefreshing = false }
        }
    }
}

// MARK: - Manual Sign-In

/// Sign in by pasting an OAuth token, or link a public profile by URL.
struct ManualSignInSheet: View {
    enum Mode {
        /// OAuth token: full account, likes sync both ways
        case token
        /// Public profile link: read-only, nothing is written to the account
        case profile
    }

    let mode: Mode
    @Binding var isPresented: Bool
    let onDone: (String) -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var input = ""

    var body: some View {
        NavigationView {
            Form {
                Section(footer: Text(mode == .token
                    ? "Paste the OAuth token of your SoundCloud account. Likes you add or remove here are saved to your account."
                    : "Paste a soundcloud.com profile link to load that profile's public likes and playlists. This is read-only, so liking is turned off.")
                ) {
                    TextField(mode == .token ? "OAuth token" : "soundcloud.com/username", text: $input)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(mode == .token ? .default : .URL)
                }
                if mode == .token {
                    Section {
                        NavigationLink("How to Find Your Token", destination: OAuthTokenGuideView())
                    }
                }
            }
            .navigationTitle(mode == .token ? "Sign In with Token" : "Public Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .token ? "Sign In" : "Load") { connect() }
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        // Sheets don't inherit the app's accent on iOS 15
        .accentColor(settings.accentColor.color)
        .preferredColorScheme(settings.themeMode.colorScheme)
    }

    private func connect() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isPresented = false
        Task {
            let auth = SoundCloudAuthManager.shared
            switch mode {
            case .token:
                await auth.handleOAuthToken(value)
                onDone("Signed in")
            case .profile:
                await auth.handleProfileURL(value)
                onDone("Profile loaded")
            }
        }
    }
}
