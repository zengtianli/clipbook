import Foundation
import CoreData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Run against the production PocketLibrary.swift; never opens the user's store or iCloud.
@main
@MainActor
struct PocketLibraryRegression {
    enum Failure: Error { case assertion(String) }
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) throws {
        checks += 1
        guard condition else { throw Failure.assertion(message) }
    }
    static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw Failure.assertion(message) }
        return value
    }
    static func open(_ home: URL, _ preferences: UserDefaults) async throws -> ClipLibrary {
        let library = ClipLibrary(home: home, preferences: preferences)
        await library.start(localOnly: true)
        try check(library.ready, library.error ?? "store did not open")
        try check(!library.cloudEnabled, "test must remain local")
        return library
    }
    static func main() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("clip-pocket-regression-\(UUID().uuidString)")
        let suite = "ClipPocketRegression.\(UUID().uuidString)"
        let preferences = try unwrap(UserDefaults(suiteName: suite), "isolated defaults")
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: home)
        }
        let library = try await open(home, preferences)
        let key = try library.save(text: "synthetic private text", title: "synthetic private title", source: "synthetic source")
        try library.mutate(key, favorite: true)
        try check(try library.list(filter: "favorites").map(\.id) == [key], "favorite before deletion")
        try library.mutate(key, remove: true)
        let context = try unwrap(library.container?.viewContext, "view context")
        let request = NSFetchRequest<NSManagedObject>(entityName: "ClipRecord")
        request.predicate = NSPredicate(format: "key == %@", key)
        let tombstone = try unwrap(context.fetch(request).first, "deletion marker retained")
        try check(tombstone.value(forKey: "key") as? String == key, "content key retained")
        try check(tombstone.value(forKey: "removed") as? Bool == true, "removed marker")
        try check(tombstone.value(forKey: "updatedAt") as? Date != nil, "deletion timestamp")
        for field in ["text", "title", "source"] {
            try check(tombstone.value(forKey: field) as? String == "", "deleted \(field) retained")
        }
        try check(tombstone.value(forKey: "favorite") as? Bool == false, "deleted favorite retained")
        try check(tombstone.value(forKey: "image") == nil, "deleted image retained")
        try check(tombstone.value(forKey: "thumbnail") == nil, "deleted thumbnail retained")
        try check(try library.list().isEmpty, "deleted row visible")
        let reopened = try await open(home, preferences)
        _ = try reopened.save(text: "synthetic private text", revive: false)
        try check(try reopened.list().isEmpty, "Mac archive send must not revive deletion")
        _ = try reopened.save(text: "synthetic private text")
        try check(try reopened.list().map(\.id) == [key], "explicit save can restore content")

        let pixels = try unwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), "image context")
        pixels.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        pixels.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try unwrap(pixels.makeImage(), "image fixture")
        let encoded = NSMutableData()
        let destination = try unwrap(CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil), "PNG encoder")
        CGImageDestinationAddImage(destination, image, nil)
        try check(CGImageDestinationFinalize(destination), "PNG encoding")
        let imageKey = try reopened.save(text: "", image: encoded as Data, title: "synthetic image")
        let imageItem = try unwrap(reopened.list(filter: "image").first, "saved image")
        try check(try reopened.imageData(imageItem, thumbnail: true) != nil, "warm thumbnail cache")
        try check(try reopened.imageData(imageItem) != nil, "original image available")
        try reopened.mutate(imageKey, remove: true)
        try check(try reopened.imageData(imageItem, thumbnail: true) == nil, "warm cache exposed deleted image")
        try check(try reopened.imageData(imageItem) == nil, "old item exposed deleted original")
        try check(try reopened.list(filter: "image").isEmpty, "deleted image visible")
        print("PASS: PocketLibrary production regression (\(checks) checks, isolated store, iCloud disabled)")
    }
}
