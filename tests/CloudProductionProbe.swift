import Foundation

/// Compile with the iOS CloudProbe and shared ClipLibrary, then sign a disposable
/// test bundle with the Release app's entitlements/profile. Never opens user history.
@main
@MainActor
struct CloudProductionProbe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard let token = CloudProbe.token,
              let index = args.firstIndex(of: "--probe-root"), args.indices.contains(index + 1),
              Bundle.main.object(forInfoDictionaryKey: "ClipCloudEnvironment") as? String == "Production"
        else { throw ClipLibrary.LibraryError.message("Explicit probe token, isolated root and Production bundle required") }
        let sender = args.contains("--probe-sender")
        let role = sender ? "sender" : "receiver"
        let root = URL(fileURLWithPath: args[index + 1], isDirectory: true).standardizedFileURL
        var home = root.appendingPathComponent(role)
        if let archiveIndex = args.firstIndex(of: "--archive-home"), args.indices.contains(archiveIndex + 1) {
            let archive = URL(fileURLWithPath: args[archiveIndex + 1], isDirectory: true).standardizedFileURL
            guard archive.path.hasPrefix(root.path + "/"), args.contains("--cleanup") else {
                throw ClipLibrary.LibraryError.message("Archive cleanup must stay inside the isolated probe root")
            }
            home = archive
        }
        let preferences = UserDefaults(suiteName: "ClipProductionProbe.\(token).\(role)")!
        let library = ClipLibrary(home: home, preferences: preferences)
        await library.start(localOnly: true)
        if !args.contains("--cleanup") && !args.contains("--verify-cleanup") {
            await CloudProbe.run(library)
            return
        }
        await library.setCloudEnabled(true)
        guard library.cloudEnabled else { throw ClipLibrary.LibraryError.message(library.error ?? "Cloud unavailable") }
        let text = "Clip cloud probe \(token)"
        if args.contains("--cleanup") {
            try library.mutate(ClipLibrary.key(text: text, image: nil), remove: true)
            try library.mutate(ClipLibrary.key(text: "Clip live copy \(token)", image: nil), remove: true)
        }
        for _ in 0..<60 {
            try await Task.sleep(for: .seconds(2))
            library.refresh()
            let removed = try library.list(search: text).isEmpty
            let report: [String: Any] = ["role": role, "removed": removed, "status": library.syncStatus,
                "error": library.error ?? "", "environment": "Production"]
            try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
                .write(to: home.appendingPathComponent("cleanup-result.json"), options: .atomic)
            if !sender && removed { return }
        }
    }
}
