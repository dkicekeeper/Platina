import CryptoKit
import Foundation
import ImageIO
import OSLog
import UIKit

/// The app's pictures (game art, logos, trophy icons, avatars), each loaded once: in memory while
/// the app runs, on disk between launches (Caches, which iOS may empty when it needs the room).
/// DesignKit's `RemotePhoto` loads through it (`DesignKitPhotoLoader`, wired in `PlatinaApp`), so
/// a picture seen before shows at once, with no skeleton and no download.
@MainActor
final class PhotoCache {
    static let shared = PhotoCache()

    /// The longest side a picture is decoded at: a 13-inch iPad's width at 2×, so a 4K key art
    /// does not take 33 MB of memory for a phone's screen.
    nonisolated static let maxPixelSize = 2752
    /// What the decoded pictures may take in memory before the oldest go.
    private static let memoryLimit = 160 * 1024 * 1024
    /// What the pictures may take on disk; the least recently used go first, at launch.
    nonisolated static let diskLimit = 300 * 1024 * 1024

    private let memory = NSCache<NSString, UIImage>()
    /// One download per picture, however many views ask for it at once (the hero draws its art
    /// twice: sharp and blurred).
    private var loading: [String: Task<DecodedPhoto?, Never>] = [:]
    nonisolated let directory: URL

    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        // The pictures are kept here, not in URLCache's small shared cache.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private init() {
        memory.totalCostLimit = Self.memoryLimit
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let directory = directory
        Task.detached(priority: .background) {
            Self.trimDisk(directory: directory, limit: Self.diskLimit)
        }
    }

    /// The picture for `key` if it is in memory: `DesignKitPhotoLoader.cached`.
    func cached(_ key: String) -> UIImage? {
        memory.object(forKey: key as NSString)
    }

    /// The picture for `key`: from memory, else from disk, else downloaded from `url` and kept.
    func image(key: String, url: URL) async -> UIImage? {
        if let image = cached(key) { return image }
        if let task = loading[key] { return await task.value?.image }
        let file = Self.file(for: key, in: directory)
        let task = Task.detached(priority: .userInitiated) {
            await Self.load(file: file, url: url)
        }
        loading[key] = task
        let photo = await task.value
        loading[key] = nil
        guard let photo else { return nil }
        memory.setObject(photo.image, forKey: key as NSString, cost: photo.cost)
        return photo.image
    }

    // MARK: Off the main thread

    nonisolated private static func load(file: URL, url: URL) async -> DecodedPhoto? {
        if let data = try? Data(contentsOf: file), let photo = decode(data) {
            // Recently used: the disk trim keeps it.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return photo
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let photo = decode(data) else {
                Logger.photos.error("Picture not loaded: \(url.host() ?? "", privacy: .public) \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }
            try? data.write(to: file, options: .atomic)
            return photo
        } catch {
            Logger.photos.error("Picture not loaded: \(url.host() ?? "", privacy: .public) \((error as? URLError)?.code.rawValue ?? 0)")
            return nil
        }
    }

    /// Decodes and, if it is larger, downsamples the picture now, so drawing it costs nothing.
    nonisolated private static func decode(_ data: Data) -> DecodedPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return DecodedPhoto(image: UIImage(cgImage: image), cost: image.bytesPerRow * image.height)
    }

    nonisolated private static func file(for key: String, in directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest)
    }

    /// Removes the least recently used pictures until the folder is under `limit`.
    nonisolated private static func trimDisk(directory: URL, limit: Int) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles
        ) else { return }
        var entries = files.compactMap { file -> (url: URL, date: Date, size: Int)? in
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
            return (file, values.contentModificationDate ?? .distantPast, values.totalFileAllocatedSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > limit else { return }
        entries.sort { $0.date < $1.date }
        for entry in entries where total > limit {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

/// A decoded picture handed from the loading task to the main actor.
private struct DecodedPhoto: @unchecked Sendable {
    let image: UIImage
    let cost: Int
}

private extension Logger {
    static let photos = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Platina", category: "Photos")
}
