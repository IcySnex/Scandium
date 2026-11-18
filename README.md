# Scandium

![iOS 15.0+](https://img.shields.io/badge/iOS-15.0%2B-000000) ![License](https://img.shields.io/badge/license-GPL--3.0-000000)

A native SoundCloud client for iOS 15 and later, tuned for older iPhones.

This is a fork of [MeoHunterr/Scandium](https://github.com/MeoHunterr/Scandium). It keeps the original's audio engine and client ID detection and changes the rest:

- **SoundCloud login with sync.** Every liked track and playlist is loaded, however many you have. Liking or unliking a track saves it to your account immediately, and the library syncs once at launch or when you pull to refresh.
- **Home like soundcloud.com.** The home page shows SoundCloud's personalized sections (Made for you, mixes, stations, recently played) and loads once per launch.
- **Native iOS look and feel.** Tabs, large titles, the search field and back swipes are the system ones.
- **Queue and shuffle.** Tapping any track plays the whole list from there. Shuffle and Play All set the shuffle switch, and turning shuffle off restores the original order.
- **Light on battery.** No animated backgrounds, looping animations or background redraws; images decode off the main thread.

## Installing

Download `Scandium-xxx.ipa` from [Releases](https://github.com/IcySnex/Scandium/releases) and install it with [TrollStore](https://github.com/opa334/TrollStore) or a sideloading tool such as [Sideloadly](https://sideloadly.io) or AltStore, which signs it with your own Apple ID.

## Signing in

In **Profile** you can:

- **Sign in to SoundCloud** in a web view. This is the normal option: likes sync both ways.
- **Sign in with a token** by pasting an OAuth token (Profile shows how to find it).
- **Load a public profile** from a soundcloud.com link. This is read-only, so liking is turned off.

## Building

On macOS with Xcode installed:

    ./scripts/build_ipa_macos.sh

This compiles with Xcode's `swiftc`, weak-links frameworks newer than iOS 15, ad-hoc signs the app and writes `Scandium.ipa` to the project root. Install it with TrollStore or a sideloading tool. The version comes from `Info.plist`.

On Linux, or on macOS without Xcode, the original [xtool](https://xtool.sh) build still works:

    python3 scripts/prebuild_audit.py
    ./scripts/build_ipa.sh

## Credits

- **MeoHunter**: the original [Scandium](https://github.com/MeoHunterr/Scandium).

## Disclaimer

Scandium is an independent open-source project for personal use. It is not affiliated with, endorsed by, or connected to SoundCloud.

## License

Licensed under the [GPL-3.0 License](LICENSE).
