//
//  DownloadSafety.swift
//  Reynard
//

import Foundation

enum DownloadCleanupPolicy {
    static func partition<Entry>(
        _ entries: [Entry],
        since startDate: Date?,
        addedAt: (Entry) -> Date
    ) -> (removed: [Entry], retained: [Entry]) {
        guard let startDate else {
            return (entries, [])
        }

        var removed: [Entry] = []
        var retained: [Entry] = []
        removed.reserveCapacity(entries.count)
        retained.reserveCapacity(entries.count)

        for entry in entries {
            if addedAt(entry) >= startDate {
                removed.append(entry)
            } else {
                retained.append(entry)
            }
        }

        return (removed, retained)
    }
}

enum DownloadManifestRecoverySource: Equatable {
    case primary
    case backup
    case empty
}

enum DownloadManifestRecovery {
    static func recover<Entry>(
        primaryData: Data?,
        backupData: Data?,
        decode: (Data) -> [Entry]?
    ) -> (entries: [Entry], source: DownloadManifestRecoverySource) {
        if let primaryData, let entries = decode(primaryData) {
            return (entries, .primary)
        }
        if let backupData, let entries = decode(backupData) {
            return (entries, .backup)
        }
        return ([], .empty)
    }
}

enum DownloadFileSafety {
    static let maximumFileNameLength = 180

    private static let pathSeparatorsAndLookalikes: Set<UInt32> = [
        0x002F, // Solidus
        0x005C, // Reverse solidus
        0x003A, // Colon
        0x2044, // Fraction slash
        0x2215, // Division slash
        0x29F8, // Big solidus
        0xFF0F, // Fullwidth solidus
        0xFF3C, // Fullwidth reverse solidus
    ]

    private static let bidiControlScalars: Set<UInt32> = [
        0x061C,
        0x200E,
        0x200F,
        0x202A,
        0x202B,
        0x202C,
        0x202D,
        0x202E,
        0x2066,
        0x2067,
        0x2068,
        0x2069,
    ]

    static func sanitizedFileName(_ value: String, fallback: String) -> String {
        let normalizedValue = value.precomposedStringWithCanonicalMapping
        var sanitized = ""
        var lastScalarWasReplacement = false

        for scalar in normalizedValue.unicodeScalars {
            let scalarValue = scalar.value
            if pathSeparatorsAndLookalikes.contains(scalarValue) {
                if !lastScalarWasReplacement {
                    sanitized.append("-")
                }
                lastScalarWasReplacement = true
                continue
            }

            if scalarValue == 0 || scalarValue < 0x20 || scalarValue == 0x7F || bidiControlScalars.contains(scalarValue) {
                continue
            }

            sanitized.unicodeScalars.append(scalar)
            lastScalarWasReplacement = false
        }

        let trimmingCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        var candidate = sanitized.trimmingCharacters(in: trimmingCharacters)
        if candidate.isEmpty {
            candidate = fallback.precomposedStringWithCanonicalMapping.trimmingCharacters(in: trimmingCharacters)
        }
        if candidate.isEmpty {
            candidate = "Download"
        }

        return truncatedFileName(candidate, maximumLength: maximumFileNameLength)
    }

    static func containedFileURL(forRelativePath relativePath: String, in directoryURL: URL) -> URL? {
        guard !relativePath.isEmpty,
              relativePath != ".",
              relativePath != "..",
              !relativePath.contains("/"),
              !relativePath.contains("\\"),
              URL(fileURLWithPath: relativePath).lastPathComponent == relativePath else {
            return nil
        }

        let rootURL = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidateURL = rootURL.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
        guard candidateURL.deletingLastPathComponent().path == rootURL.path else {
            return nil
        }

        let resolvedURL = candidateURL.resolvingSymlinksInPath()
        guard resolvedURL.deletingLastPathComponent().path == rootURL.path else {
            return nil
        }

        return candidateURL
    }

    static func capturedTemporaryFileURL(
        forPath path: String,
        temporaryDirectoryURL: URL = FileManager.default.temporaryDirectory
    ) -> URL? {
        guard !path.isEmpty else {
            return nil
        }

        let rootURL = temporaryDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidateURL = URL(fileURLWithPath: path).standardizedFileURL
        guard candidateURL.lastPathComponent.hasPrefix("reynard-download"),
              candidateURL.deletingLastPathComponent().resolvingSymlinksInPath().path == rootURL.path,
              candidateURL.resolvingSymlinksInPath().deletingLastPathComponent().path == rootURL.path else {
            return nil
        }
        return candidateURL
    }

    static func uniqueDestinationURL(
        for fileName: String,
        in directoryURL: URL,
        reservedFileNames: Set<String>,
        fileExists: (URL) -> Bool
    ) -> URL {
        let normalizedReservedNames = Set(reservedFileNames.map { $0.lowercased() })
        let fallbackName = UUID().uuidString
        let safeFileName = sanitizedFileName(fileName, fallback: fallbackName)
        let initialURL = containedFileURL(forRelativePath: safeFileName, in: directoryURL)
            ?? directoryURL.appendingPathComponent(fallbackName, isDirectory: false)

        if !fileExists(initialURL), !normalizedReservedNames.contains(initialURL.lastPathComponent.lowercased()) {
            return initialURL
        }

        let fileURL = URL(fileURLWithPath: safeFileName)
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let extensionName = fileURL.pathExtension

        for index in 2...10_000 {
            let duplicateSuffix = " \(index)"
            let extensionSuffix = extensionName.isEmpty ? "" : ".\(extensionName)"
            let availableBaseBytes = maximumFileNameLength
                - duplicateSuffix.utf8.count
                - extensionSuffix.utf8.count
            let truncatedBaseName = prefix(baseName, fittingUTF8ByteCount: max(availableBaseBytes, 1))
            let candidateName = truncatedBaseName + duplicateSuffix + extensionSuffix

            guard let candidateURL = containedFileURL(forRelativePath: candidateName, in: directoryURL) else {
                continue
            }
            if !fileExists(candidateURL), !normalizedReservedNames.contains(candidateName.lowercased()) {
                return candidateURL
            }
        }

        return directoryURL.appendingPathComponent(fallbackName, isDirectory: false)
    }

    private static func truncatedFileName(_ fileName: String, maximumLength: Int) -> String {
        guard fileName.utf8.count > maximumLength else {
            return fileName
        }

        let fileURL = URL(fileURLWithPath: fileName)
        let extensionName = fileURL.pathExtension
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let extensionSuffix = extensionName.isEmpty ? "" : ".\(extensionName)"
        let availableBaseLength = maximumLength - extensionSuffix.utf8.count

        if availableBaseLength > 0 {
            return prefix(baseName, fittingUTF8ByteCount: availableBaseLength) + extensionSuffix
        }
        return prefix(fileName, fittingUTF8ByteCount: maximumLength)
    }

    private static func prefix(_ value: String, fittingUTF8ByteCount maximumByteCount: Int) -> String {
        var result = ""
        result.reserveCapacity(min(value.count, maximumByteCount))
        for character in value {
            let next = result + String(character)
            guard next.utf8.count <= maximumByteCount else {
                break
            }
            result = next
        }
        return result
    }
}
