// ProfileView.swift — Account and settings
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

    private static let sourceURL = URL(string: "https://github.com/MeoHunterr/Scandium")!

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                accountCard
                appearanceSection
                playbackSection
                storageSection
                advancedSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .navigationTitle("Profile")
        .sheet(isPresented: $showSignIn) {
            SoundCloudLoginSheet(isPresented: $showSignIn, onLoginSuccess: {
                showToast("Signed in")
            })
        }
        .sheet(isPresented: Binding(
            get: { manualSignIn != nil },
            set: { if !$0 { manualSignIn = nil } }
        )) {
            ManualSignInSheet(
                mode: manualSignIn ?? .token,
                isPresented: Binding(
                    get: { manualSignIn != nil },
                    set: { if !$0 { manualSignIn = nil } }
                )
            ) { message in
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
    private var accountCard: some View {
        if auth.isLoggedIn, let user = auth.currentUser {
            HStack(spacing: 14) {
                CachedAsyncImage(url: user.highResAvatarURL, width: 56, height: 56, cornerRadius: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(user.username)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .lineLimit(1)
                    Text(auth.canSyncLikes
                         ? "\(auth.userLikedTracks.count) likes · \(auth.userPlaylists.count) playlists"
                         : "Public profile · read-only")
                        .font(.system(size: 13))
                        .foregroundColor(ScandiumTheme.subtext)
                }

                Spacer()

                Button("Log Out") { showLogOutConfirm = true }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red)
            }
            .padding(14)
            .background(ScandiumTheme.surfaceDark)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            SettingsGroup {
                SettingsButtonRow(icon: "person.crop.circle", title: "Sign in to SoundCloud", subtitle: "Sync your likes and playlists") {
                    showSignIn = true
                }
                SettingsDivider()
                SettingsButtonRow(icon: "key", title: "Sign in with a token") {
                    manualSignIn = .token
                }
                SettingsDivider()
                SettingsButtonRow(icon: "link", title: "Load a public profile", subtitle: "Read-only, nothing is saved to SoundCloud") {
                    manualSignIn = .profile
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsGroup(title: "Appearance") {
            Picker("Theme", selection: $settings.themeMode) {
                ForEach(AppThemeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(12)

            SettingsDivider()

            HStack {
                Text("Accent Color")
                    .font(.system(size: 15))
                    .foregroundColor(ScandiumTheme.textPrimary)
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
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(accent.title)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        SettingsGroup(title: "Playback") {
            SettingsToggleRow(title: "Autoplay Similar Tracks", subtitle: "When the queue ends", isOn: $settings.autoPlayRelated)
            SettingsDivider()
            SettingsToggleRow(title: "Pause When Headphones Disconnect", isOn: $settings.pauseOnHeadphoneDisconnect)
            SettingsDivider()
            SettingsToggleRow(title: "Skip Tracks That Fail to Play", isOn: $settings.autoSkipOnError)
            SettingsDivider()
            SettingsToggleRow(title: "Waveform Scrubber", subtitle: "In the full player", isOn: $settings.showWaveform)
            SettingsDivider()
            SettingsToggleRow(title: "Keep Screen Awake", isOn: $settings.keepScreenAwake)
            SettingsDivider()
            SettingsToggleRow(title: "Haptic Feedback", isOn: $settings.enableHaptics)
            SettingsDivider()

            HStack {
                Text("Sleep Timer")
                    .font(.system(size: 15))
                    .foregroundColor(ScandiumTheme.textPrimary)
                Spacer()
                Menu {
                    Picker("Sleep Timer", selection: Binding(
                        get: { settings.sleepTimerOption },
                        set: { option in
                            AudioPlayerEngineWrapper.sharedEngine?.setSleepTimer(option)
                            settings.sleepTimerOption = option
                        }
                    )) {
                        ForEach(SleepTimerOption.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(settings.sleepTimerOption.title)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 15))
                    .foregroundColor(ScandiumTheme.subtext)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        SettingsGroup(title: "Storage") {
            SettingsValueRow(title: "Artwork Cache", value: storage.formattedImageCache) {
                storage.clearImageCacheOnly()
                ImageCacheStore.shared.clear()
                showToast("Artwork cache cleared")
            }
            SettingsDivider()
            SettingsValueRow(title: "Audio Cache", value: storage.formattedAudioNetwork) {
                storage.clearAudioCacheOnly()
                showToast("Audio cache cleared")
            }
            SettingsDivider()
            Button(action: { showClearCacheConfirm = true }) {
                HStack {
                    Text("Clear All Cached Data")
                        .foregroundColor(.red)
                    Spacer()
                    Text(storage.formattedTotal)
                        .foregroundColor(ScandiumTheme.subtext)
                }
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        SettingsGroup(title: "Advanced") {
            NavigationLink(destination: ClientIDSettingsView()) {
                SettingsRowLabel(
                    icon: "network",
                    title: "Client ID",
                    subtitle: scraper.manualClientID != nil ? "Custom" : scraper.statusDescription,
                    showsChevron: true
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsGroup(title: "About") {
                HStack {
                    Text("Version")
                        .foregroundColor(ScandiumTheme.textPrimary)
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(ScandiumTheme.subtext)
                }
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                SettingsDivider()

                Link(destination: Self.sourceURL) {
                    SettingsRowLabel(icon: nil, title: "Source Code", subtitle: "Scandium by MeoHunter · GPL-3.0", trailingIcon: "arrow.up.right")
                }
            }

            Text("Not affiliated with or endorsed by SoundCloud.")
                .font(.system(size: 12))
                .foregroundColor(ScandiumTheme.subtext)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = toastMessage {
            Text(message)
                .font(.system(size: 13, weight: .semibold))
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("SoundCloud requires a client ID for every request. The app detects one automatically; set your own only if detection keeps failing.")
                    .font(.system(size: 13))
                    .foregroundColor(ScandiumTheme.subtext)

                SettingsGroup(title: "Status") {
                    HStack {
                        Circle()
                            .fill(scraper.lastError == nil ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(scraper.statusDescription)
                            .foregroundColor(ScandiumTheme.textPrimary)
                        Spacer()
                        if let id = scraper.currentClientID {
                            Text(id.prefix(8) + "…")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(ScandiumTheme.subtext)
                        }
                    }
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)

                    if let error = scraper.lastError {
                        SettingsDivider()
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }

                    SettingsDivider()

                    Button(action: refresh) {
                        HStack {
                            Text("Detect Again")
                                .foregroundColor(ScandiumTheme.accent)
                            Spacer()
                            if isRefreshing {
                                ProgressView().scaleEffect(0.8)
                            }
                        }
                        .font(.system(size: 15))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isRefreshing)
                }

                SettingsGroup(title: "Custom Client ID") {
                    TextField("32-character client ID", text: $manualInput)
                        .font(.system(size: 15, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)

                    SettingsDivider()

                    HStack(spacing: 20) {
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
                        Spacer()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(ScandiumTheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }

                if let message = message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(ScandiumTheme.subtext)
                }

                NavigationLink(destination: ClientIDGuideView()) {
                    Text("How to find a client ID")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ScandiumTheme.accent)
                }
            }
            .padding(16)
            .padding(.bottom, 80)
        }
        .background(ScandiumTheme.bgPrimary.ignoresSafeArea())
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(mode == .token
                         ? "Paste the OAuth token of your SoundCloud account. Likes you add or remove here are saved to your account."
                         : "Paste a soundcloud.com profile link to load that profile's public likes and playlists. This is read-only: likes you change here stay on this phone.")
                        .font(.system(size: 14))
                        .foregroundColor(ScandiumTheme.subtext)

                    TextField(mode == .token ? "OAuth token" : "soundcloud.com/username", text: $input)
                        .font(.system(size: 15))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .keyboardType(mode == .token ? .default : .URL)
                        .foregroundColor(ScandiumTheme.textPrimary)
                        .padding(12)
                        .background(ScandiumTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if mode == .token {
                        NavigationLink(destination: OAuthTokenGuideView()) {
                            Text("How to find your token")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(ScandiumTheme.accent)
                        }
                    }
                }
                .padding(20)
            }
            .background(ScandiumTheme.bgPrimary.ignoresSafeArea())
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

// MARK: - Settings Building Blocks

struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ScandiumTheme.subtext)
                    .padding(.horizontal, 4)
            }
            VStack(spacing: 0, content: content)
                .background(ScandiumTheme.surfaceDark)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct SettingsDivider: View {
    var body: some View { HairlineDivider(leadingPadding: 16) }
}

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(ScandiumTheme.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(ScandiumTheme.subtext)
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: ScandiumTheme.accent))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// A row showing a size with a trailing "Clear" action.
struct SettingsValueRow: View {
    let title: String
    let value: String
    let onClear: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(ScandiumTheme.textPrimary)
            Spacer()
            Text(value)
                .foregroundColor(ScandiumTheme.subtext)
            Button("Clear", action: onClear)
                .foregroundColor(ScandiumTheme.accent)
                .padding(.leading, 8)
        }
        .font(.system(size: 15))
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

struct SettingsRowLabel: View {
    let icon: String?
    let title: String
    var subtitle: String? = nil
    var showsChevron: Bool = false
    var trailingIcon: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(ScandiumTheme.accent)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(ScandiumTheme.textPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(ScandiumTheme.subtext)
                }
            }
            Spacer()
            if showsChevron || trailingIcon != nil {
                Image(systemName: trailingIcon ?? "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ScandiumTheme.subtext)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct SettingsButtonRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowLabel(icon: icon, title: title, subtitle: subtitle, showsChevron: true)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
