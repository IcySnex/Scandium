// GuideViews.swift — Step-by-step help pages for manual sign-in and Client ID setup
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

/// How to copy the `oauth_token` from soundcloud.com for manual sign-in.
struct OAuthTokenGuideView: View {
    private enum Platform: String, CaseIterable, Identifiable {
        case computer = "Computer"
        case iPhone = "iPhone"
        var id: String { rawValue }
    }

    @State private var platform: Platform = .computer

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Platform", selection: $platform) {
                    ForEach(Platform.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(SegmentedPickerStyle())

                if platform == .computer {
                    GuideHeading("From browser cookies")
                    GuideStep(1, "Sign in on soundcloud.com", "Use Chrome, Edge, Safari or Firefox on your computer.")
                    GuideStep(2, "Open the developer tools", "Press F12, or Cmd + Option + I on a Mac.")
                    GuideStep(3, "Open the cookies for soundcloud.com", "Application → Cookies in Chrome and Edge, Storage → Cookies in Firefox and Safari.")
                    GuideStep(4, "Copy the oauth_token value", "Find the row named oauth_token and copy its value.")
                    GuideStep(5, "Paste it into the app", "Send it to your iPhone and paste it into the sign-in field.")

                    GuideHeading("Alternative: from a network request")
                    GuideStep(1, "Open the Network tab", "In the developer tools, filter requests for \"me\".")
                    GuideStep(2, "Reload the page or play a track", "Requests to api-v2.soundcloud.com appear in the list.")
                    GuideStep(3, "Copy the token from the headers", "Select the request and copy the text after \"OAuth \" in the Authorization header.")
                } else {
                    GuideHeading("With a network capture app")
                    GuideStep(1, "Install a capture app", "For example HTTP Catcher, Surge, Thor or Shadowrocket.")
                    GuideStep(2, "Start capturing and sign in", "Open soundcloud.com in Safari and sign in.")
                    GuideStep(3, "Find a request to /me or /stream", "Play a track, then open one of those requests in the capture log.")
                    GuideStep(4, "Copy the token", "Copy the text after \"OAuth \" in the Authorization header.")
                    GuideStep(5, "Paste it into the app", "Return here and paste it into the sign-in field.")
                }
            }
            .padding(16)
            .padding(.bottom, 80)
        }
        .background(ScandiumTheme.bgPrimary.ignoresSafeArea())
        .navigationTitle("Find Your Token")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// How to copy a client_id from soundcloud.com when automatic detection fails.
struct ClientIDGuideView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("The app normally finds a client ID on its own. If that keeps failing, copy one from soundcloud.com on a computer.")
                    .font(.system(size: 14))
                    .foregroundColor(ScandiumTheme.subtext)

                GuideStep(1, "Open soundcloud.com", "Use Chrome, Edge, Safari or Firefox on your computer.")
                GuideStep(2, "Open the Network tab", "Press F12 (Cmd + Option + I on a Mac) and filter requests for \"client_id\".")
                GuideStep(3, "Play any track", "Requests to api-v2.soundcloud.com appear with ?client_id=… in the URL.")
                GuideStep(4, "Copy the 32-character value", "Paste it under Client ID on the previous page.")
            }
            .padding(16)
            .padding(.bottom, 80)
        }
        .background(ScandiumTheme.bgPrimary.ignoresSafeArea())
        .navigationTitle("Find a Client ID")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Building Blocks

private struct GuideHeading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(ScandiumTheme.textPrimary)
            .padding(.top, 4)
    }
}

private struct GuideStep: View {
    let number: Int
    let title: String
    let detail: String

    init(_ number: Int, _ title: String, _ detail: String) {
        self.number = number
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(ScandiumTheme.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(ScandiumTheme.surfaceElevated))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ScandiumTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(ScandiumTheme.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ScandiumTheme.surfaceDark)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
