import AppKit
import SwiftUI

struct FinderFileIcon: View {
    let url: URL
    var size: CGFloat = 20
    var cache: FinderFileIconCache = .shared

    var body: some View {
        Image(nsImage: cache.icon(for: url))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

@MainActor
final class FinderFileIconCache {
    static let shared = FinderFileIconCache()

    private let storage = NSCache<NSURL, NSImage>()
    private let loader: (URL) -> NSImage

    init(
        countLimit: Int = 512,
        loader: @escaping (URL) -> NSImage = { url in
            NSWorkspace.shared.icon(forFile: url.path)
        }
    ) {
        self.loader = loader
        storage.countLimit = countLimit
    }

    func icon(for url: URL) -> NSImage {
        let key = url.standardizedFileURL as NSURL
        if let cached = storage.object(forKey: key) {
            return cached
        }

        let image = loader(url.standardizedFileURL)
        storage.setObject(image, forKey: key)
        return image
    }

    func removeAllObjects() {
        storage.removeAllObjects()
    }
}
