// AppSettings.swift — Global user preferences
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI
import UIKit

public enum AppThemeMode: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }

    public var icon: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

public enum AppAccentColor: String, CaseIterable, Identifiable {
    case green
    case orange
    case cyan
    case purple

    public var id: String { rawValue }

    public init?(rawValue: String) {
        switch rawValue {
        case "green", "spotifyGreen": self = .green
        case "orange", "soundcloudOrange": self = .orange
        case "cyan", "neonCyan": self = .cyan
        case "purple", "violetPurple": self = .purple
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .green: return "Green"
        case .orange: return "Orange"
        case .cyan: return "Cyan"
        case .purple: return "Purple"
        }
    }

    public var color: Color {
        switch self {
        case .green:   return Color(red: 29/255, green: 185/255, blue: 84/255)
        case .orange:  return Color(red: 255/255, green: 85/255, blue: 0/255)
        case .cyan:    return Color(red: 0/255, green: 229/255, blue: 255/255)
        case .purple:  return Color(red: 187/255, green: 134/255, blue: 252/255)
        }
    }
}

public enum SleepTimerOption: Int, CaseIterable, Identifiable {
    case off = 0
    case min15 = 15
    case min30 = 30
    case min45 = 45
    case min60 = 60
    case endOfTrack = -1

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .off:        return "Off"
        case .min15:      return "15 minutes"
        case .min30:      return "30 minutes"
        case .min45:      return "45 minutes"
        case .min60:      return "1 hour"
        case .endOfTrack: return "End of track"
        }
    }
}

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    // MARK: - Published Properties

    @Published public var themeMode: AppThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: "scandium_theme_mode") }
    }

    @Published public var accentColor: AppAccentColor {
        didSet { UserDefaults.standard.set(accentColor.rawValue, forKey: "scandium_accent_color") }
    }

    @Published public var autoPlayRelated: Bool {
        didSet { UserDefaults.standard.set(autoPlayRelated, forKey: "scandium_autoplay_related") }
    }

    @Published public var keepScreenAwake: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenAwake, forKey: "scandium_keep_screen_awake")
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
    }

    @Published public var pauseOnHeadphoneDisconnect: Bool {
        didSet { UserDefaults.standard.set(pauseOnHeadphoneDisconnect, forKey: "scandium_pause_on_headphone_disconnect") }
    }

    @Published public var autoSkipOnError: Bool {
        didSet { UserDefaults.standard.set(autoSkipOnError, forKey: "scandium_auto_skip_on_error") }
    }

    @Published public var showWaveform: Bool {
        didSet { UserDefaults.standard.set(showWaveform, forKey: "scandium_show_waveform") }
    }

    @Published public var enableHaptics: Bool {
        didSet { UserDefaults.standard.set(enableHaptics, forKey: "scandium_enable_haptics") }
    }

    @Published public var sleepTimerOption: SleepTimerOption = .off

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        themeMode = AppThemeMode(rawValue: defaults.string(forKey: "scandium_theme_mode") ?? "") ?? .dark
        accentColor = AppAccentColor(rawValue: defaults.string(forKey: "scandium_accent_color") ?? "") ?? .green

        autoPlayRelated = defaults.object(forKey: "scandium_autoplay_related") as? Bool ?? true
        keepScreenAwake = defaults.bool(forKey: "scandium_keep_screen_awake")
        pauseOnHeadphoneDisconnect = defaults.object(forKey: "scandium_pause_on_headphone_disconnect") as? Bool ?? true
        autoSkipOnError = defaults.object(forKey: "scandium_auto_skip_on_error") as? Bool ?? true
        showWaveform = defaults.object(forKey: "scandium_show_waveform") as? Bool ?? true
        enableHaptics = defaults.object(forKey: "scandium_enable_haptics") as? Bool ?? true

        if keepScreenAwake {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // Settings that no longer exist
        for key in ["scandium_language", "scandium_app_icon", "scandium_audio_quality"] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Haptic Feedback

    public func triggerHaptic() {
        guard enableHaptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Dark Mode Detection

    public var isDark: Bool {
        switch themeMode {
        case .dark:
            return true
        case .light:
            return false
        case .system:
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow.traitCollection.userInterfaceStyle != .light
            }
            return UITraitCollection.current.userInterfaceStyle != .light
        }
    }
}
