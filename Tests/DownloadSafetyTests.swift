import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case expectation(String)

    var description: String {
        switch self {
        case .expectation(let message):
            return message
        }
    }
}

private struct DownloadEntry {
    let name: String
    let addedAt: Date
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure.expectation(message)
    }
}

@main
private struct DownloadSafetyTests {
    static func main() throws {
        try testPartialCleanupRetainsOlderEntries()
        try testFullCleanupRemovesEveryCompletedEntry()
        try testManifestEncodingAndRecovery()
        try testFileNameSanitization()
        try testFileNameLengthPreservesExtension()
        try testContainedPaths()
        try testCapturedTemporaryPaths()
        try testDuplicateFileNames()
        print("DownloadSafetyTests: all tests passed")
    }

    private static func testPartialCleanupRetainsOlderEntries() throws {
        let cutoff = Date(timeIntervalSince1970: 2_000)
        let entries = [
            DownloadEntry(name: "older", addedAt: Date(timeIntervalSince1970: 1_000)),
            DownloadEntry(name: "cutoff", addedAt: cutoff),
            DownloadEntry(name: "newer", addedAt: Date(timeIntervalSince1970: 3_000)),
        ]
        let partition = DownloadCleanupPolicy.partition(entries, since: cutoff, addedAt: { $0.addedAt })

        try expect(partition.removed.map(\.name) == ["cutoff", "newer"], "Partial cleanup removed the wrong entries")
        try expect(partition.retained.map(\.name) == ["older"], "Partial cleanup deleted older history")
    }

    private static func testFullCleanupRemovesEveryCompletedEntry() throws {
        let entries = [
            DownloadEntry(name: "one", addedAt: .distantPast),
            DownloadEntry(name: "two", addedAt: .distantFuture),
        ]
        let partition = DownloadCleanupPolicy.partition(entries, since: nil, addedAt: { $0.addedAt })

        try expect(partition.removed.count == 2, "Full cleanup did not remove every completed entry")
        try expect(partition.retained.isEmpty, "Full cleanup retained completed entries")
    }

    private static func testManifestEncodingAndRecovery() throws {
        struct ManifestEntry: Codable, Equatable {
            let name: String
            let size: Int64
        }
        let entries = [ManifestEntry(name: "archive.zip", size: 42)]
        let encoded = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([ManifestEntry].self, from: encoded)
        try expect(decoded == entries, "Download manifest did not round-trip")

        let recovery = DownloadManifestRecovery.recover(
            primaryData: Data("not-json".utf8),
            backupData: encoded,
            decode: { try? JSONDecoder().decode([ManifestEntry].self, from: $0) }
        )
        try expect(recovery.entries == entries, "Corrupt manifest did not recover from its backup")
        try expect(recovery.source == .backup, "Manifest recovery reported the wrong source")
    }

    private static func testFileNameSanitization() throws {
        let unsafeName = "..／..\\\u{202E}/private/\u{0000}report.pdf"
        let sanitized = DownloadFileSafety.sanitizedFileName(unsafeName, fallback: "Download")

        try expect(!sanitized.isEmpty, "Sanitized file name is empty")
        try expect(!sanitized.contains("/"), "Sanitized file name contains a solidus")
        try expect(!sanitized.contains("\\"), "Sanitized file name contains a reverse solidus")
        try expect(!sanitized.unicodeScalars.contains(where: { $0.value == 0x202E }), "Sanitized file name contains a bidi override")
        try expect(sanitized != "." && sanitized != "..", "Sanitized file name is a traversal component")
    }

    private static func testFileNameLengthPreservesExtension() throws {
        let longName = String(repeating: "文", count: 300) + ".pdf"
        let sanitized = DownloadFileSafety.sanitizedFileName(longName, fallback: "Download")

        try expect(sanitized.utf8.count <= DownloadFileSafety.maximumFileNameLength, "Sanitized file name exceeds the UTF-8 length limit")
        try expect(sanitized.hasSuffix(".pdf"), "File extension was not preserved")
    }

    private static func testContainedPaths() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ReynardDownloadSafetyTests", isDirectory: true)

        try expect(
            DownloadFileSafety.containedFileURL(forRelativePath: "safe.pdf", in: directory) != nil,
            "A safe direct child path was rejected"
        )
        try expect(
            DownloadFileSafety.containedFileURL(forRelativePath: "../escape.pdf", in: directory) == nil,
            "A traversal path was accepted"
        )
        try expect(
            DownloadFileSafety.containedFileURL(forRelativePath: "nested/escape.pdf", in: directory) == nil,
            "A nested path was accepted"
        )
        try expect(
            DownloadFileSafety.containedFileURL(forRelativePath: "/tmp/escape.pdf", in: directory) == nil,
            "An absolute path was accepted"
        )
    }

    private static func testDuplicateFileNames() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ReynardDownloadSafetyTests", isDirectory: true)
        let destination = DownloadFileSafety.uniqueDestinationURL(
            for: "document.pdf",
            in: directory,
            reservedFileNames: ["document.pdf"],
            fileExists: { _ in false }
        )

        try expect(destination.lastPathComponent == "document 2.pdf", "Duplicate file name was not resolved predictably")

        let longDestination = DownloadFileSafety.uniqueDestinationURL(
            for: String(repeating: "文", count: 200) + ".pdf",
            in: directory,
            reservedFileNames: [],
            fileExists: { $0.lastPathComponent.hasSuffix(".pdf") && !$0.lastPathComponent.contains(" 2.pdf") }
        )
        try expect(longDestination.lastPathComponent.hasSuffix(" 2.pdf"), "Long duplicate lost its numeric suffix")
        try expect(
            longDestination.lastPathComponent.utf8.count <= DownloadFileSafety.maximumFileNameLength,
            "Long duplicate exceeds the UTF-8 length limit"
        )
    }

    private static func testCapturedTemporaryPaths() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ReynardCapturedDownloadTests", isDirectory: true)
        let validPath = directory.appendingPathComponent("reynard-download.tmp-1").path

        try expect(
            DownloadFileSafety.capturedTemporaryFileURL(forPath: validPath, temporaryDirectoryURL: directory) != nil,
            "A valid Gecko captured-download path was rejected"
        )
        try expect(
            DownloadFileSafety.capturedTemporaryFileURL(
                forPath: directory.appendingPathComponent("unrelated.tmp").path,
                temporaryDirectoryURL: directory
            ) == nil,
            "An unrelated temporary file was accepted"
        )
        try expect(
            DownloadFileSafety.capturedTemporaryFileURL(
                forPath: "/private/var/mobile/escape",
                temporaryDirectoryURL: directory
            ) == nil,
            "A captured-download path outside the temporary directory was accepted"
        )
    }
}
