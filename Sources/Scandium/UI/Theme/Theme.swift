// Theme.swift — Colors, sizes, image loading and placeholders
// Project: Scandium | Author: MeoHunter | License: GPL-3.0

import SwiftUI

// MARK: - Design Tokens

enum ScandiumTheme {
    static var isDark: Bool {
        AppSettings.shared.isDark
    }

    // iOS system colors: they match the platform in light and dark mode and
    // resolve against the current trait, so every view updates at once when
    // the theme changes.
    static let bgPrimary = Color(UIColor.systemBackground)
    static let surfaceDark = Color(UIColor.secondarySystemBackground)
    static let surfaceCard = Color(UIColor.secondarySystemBackground)
    static let surfaceElevated = Color(UIColor.tertiarySystemFill)

    static let textPrimary = Color(UIColor.label)
    static let subtext = Color(UIColor.secondaryLabel)

    static let hairline = Color(UIColor.separator)
    static let hairlinewidth: CGFloat = 0.5

    // Accents
    /// Follows the `.accentColor` set at the root (and on presented
    /// screens), so every view picks up a new accent immediately.
    static var accent: Color {
        Color.accentColor
    }
    static var spotifyGreen: Color {
        accent
    }

    // Dimensions
    static let cornerRadiusSmall: CGFloat = 6
    static let cornerRadiusMedium: CGFloat = 8
    static let cornerRadiusCard: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 16
    static let tabBarHeight: CGFloat = 49
}


// MARK: - Hairline Divider

struct HairlineDivider: View {
    var leadingPadding: CGFloat = 0

    init(leadingPadding: CGFloat = 0) {
        self.leadingPadding = leadingPadding
    }

    var body: some View {
        Rectangle()
            .fill(ScandiumTheme.hairline)
            .frame(height: ScandiumTheme.hairlinewidth)
            .padding(.leading, leadingPadding)
    }
}

// MARK: - Cached Async Image

struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let width: CGFloat?
    let height: CGFloat?
    let cornerRadius: CGFloat
    let contentMode: ContentMode
    let placeholder: () -> Placeholder

    /// The last image loaded, and the URL it belongs to. It is only shown
    /// while `url` still matches, so a track change can never leave the
    /// previous artwork on screen.
    @State private var loaded: (url: URL, image: UIImage)?

    init(
        url: URL?,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 0,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    /// Loaded image for the current URL, or one already in memory (so
    /// recreated views don't flash the placeholder).
    private var image: UIImage? {
        guard let url = url else { return nil }
        if let loaded = loaded, loaded.url == url { return loaded.image }
        return ImageCacheStore.shared.memoryImage(for: url)
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Restarts (and cancels the previous load) whenever the URL changes
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url = url, image == nil else { return }
        // Disk read, download and decoding all happen off the main thread
        let result = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            if let cached = ImageCacheStore.shared.diskImage(for: url) { return cached }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            var data = try? await URLSession.shared.data(for: request).0
            if data == nil {
                try? await Task.sleep(nanoseconds: 500_000_000) // one quick retry
                data = try? await URLSession.shared.data(for: request).0
            }
            return data.flatMap { ImageCacheStore.shared.store($0, for: url) }
        }.value
        if let result = result, !Task.isCancelled {
            loaded = (url, result)
        }
    }
}

// Convenience init for CachedAsyncImage with default placeholder
extension CachedAsyncImage where Placeholder == ShimmerView {
    init(
        url: URL?,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 0,
        contentMode: ContentMode = .fill
    ) {
        self.init(
            url: url,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            contentMode: contentMode,
            placeholder: { ShimmerView() }
        )
    }
}

// MARK: - Image Cache (Memory + Disk)

final class ImageCacheStore {
    static let shared = ImageCacheStore()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheDir: URL?

    private init() {
        memoryCache.countLimit = 300
        // Decoded bitmaps; the SE has 2 GB of RAM
        memoryCache.totalCostLimit = 64 * 1024 * 1024

        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        if let base = paths.first {
            let dir = base.appendingPathComponent("scandium_image_cache", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.diskCacheDir = dir
        } else {
            self.diskCacheDir = nil
        }
    }

    private func diskKey(for url: URL) -> String {
        let raw = url.absoluteString
        let hash = raw.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }
        return "img_\(abs(hash)).jpg"
    }

    /// Memory-only lookup, cheap enough to call while building a view.
    func memoryImage(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url.absoluteString as NSString)
    }

    /// Disk lookup. Reads and decodes the file, so call it off the main thread.
    func diskImage(for url: URL) -> UIImage? {
        guard let dir = diskCacheDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(diskKey(for: url))) else { return nil }
        return remember(data, for: url)
    }

    /// Decodes downloaded bytes, keeps the image in memory and the original
    /// bytes on disk (no re-encoding). Call it off the main thread.
    @discardableResult
    func store(_ data: Data, for url: URL) -> UIImage? {
        guard let image = remember(data, for: url) else { return nil }
        if let dir = diskCacheDir {
            try? data.write(to: dir.appendingPathComponent(diskKey(for: url)), options: .atomic)
        }
        return image
    }

    private func remember(_ data: Data, for url: URL) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        // Decode now, on this background thread, instead of on the main
        // thread the first time the image is drawn.
        let decoded = image.preparingForDisplay() ?? image
        let cost = Int(decoded.size.width * decoded.scale * decoded.size.height * decoded.scale * 4)
        memoryCache.setObject(decoded, forKey: url.absoluteString as NSString, cost: cost)
        return decoded
    }

    func clear() {
        memoryCache.removeAllObjects()
        if let dir = diskCacheDir,
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for f in files {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }
}

// MARK: - Loading Placeholder

/// Static placeholder for images and rows that are still loading. It does
/// not animate: on an iPhone SE every animated frame costs battery.
struct ShimmerView: View {
    init() {}

    var body: some View {
        ScandiumTheme.surfaceDark
    }
}
