//
//  DownloadStore.swift
//  Reynard
//
//  Created by Minh Ton on 2/4/26.
//

import Foundation
import GeckoView
import UniformTypeIdentifiers
import MobileCoreServices

struct DownloadStoreSummary {
    let totalCount: Int
    let activeCount: Int
    let aggregateProgress: Float
    let hasUnviewedCompletedDownloads: Bool
    
    var showsToolbarButton: Bool {
        return activeCount > 0 || (hasUnviewedCompletedDownloads && totalCount > 0)
    }
}

struct DownloadStoreSnapshot {
    let summary: DownloadStoreSummary
    let items: [DownloadItemSnapshot]
}

struct DownloadItemSnapshot {
    enum State: Equatable {
        case downloading
        case completed
        case failed
        case cancelled
    }
    
    let id: UUID
    let fileName: String
    let fileURL: URL?
    let sourceURL: URL
    let originalURL: URL?
    let mimeType: String?
    let state: State
    let fileExists: Bool
    let totalBytes: Int64?
    let downloadedBytes: Int64
    let bytesPerSecond: Int64
    let addedAt: Date
    let failureDescription: String?
    let canRetry: Bool
}

final class DownloadStore: NSObject {
    static let shared = DownloadStore()
    
    struct PendingDownload {
        let fileName: String
        let sourceHost: String
        let expectedBytes: Int64?
        let mimeType: String?
        fileprivate let startHandler: () -> Void
    }
    
    private struct StorageURLs {
        let downloadsDirectoryURL: URL
        let appDataDirectoryURL: URL
        let manifestFileURL: URL
        let manifestBackupFileURL: URL
    }
    
    private struct PersistedDownloadEntry: Codable {
        let id: UUID
        let fileName: String
        let relativePath: String
        let sourceURLString: String
        let originalURLString: String?
        let mimeType: String?
        let fileSize: Int64
        let addedAt: Date
    }
    
    private struct ProgressSample {
        let bytesWritten: Int64
        let timestamp: TimeInterval
    }
    
    private final class ActiveDownload {
        let id: UUID
        let sourceURL: URL
        let originalURL: URL?
        let fileName: String
        let destinationURL: URL
        let mimeType: String?
        let addedAt: Date
        let task: URLSessionDownloadTask
        var expectedBytes: Int64?
        var downloadedBytes: Int64
        var bytesPerSecond: Int64
        var lastProgressSample: ProgressSample?
        
        init(
            id: UUID,
            sourceURL: URL,
            originalURL: URL?,
            fileName: String,
            destinationURL: URL,
            mimeType: String?,
            addedAt: Date,
            task: URLSessionDownloadTask
        ) {
            self.id = id
            self.sourceURL = sourceURL
            self.originalURL = originalURL
            self.fileName = fileName
            self.destinationURL = destinationURL
            self.mimeType = mimeType
            self.addedAt = addedAt
            self.task = task
            self.expectedBytes = nil
            self.downloadedBytes = 0
            self.bytesPerSecond = 0
        }
    }
    
    private final class CapturedDownload {
        let id: UUID
        let localFilePath: String
        let sourceURL: URL
        let fileName: String
        let destinationURL: URL
        let mimeType: String?
        let addedAt: Date
        var expectedBytes: Int64?
        var downloadedBytes: Int64
        var bytesPerSecond: Int64
        var lastProgressSample: ProgressSample?
        
        init(
            id: UUID,
            localFilePath: String,
            sourceURL: URL,
            fileName: String,
            destinationURL: URL,
            mimeType: String?,
            addedAt: Date,
            expectedBytes: Int64?
        ) {
            self.id = id
            self.localFilePath = localFilePath
            self.sourceURL = sourceURL
            self.fileName = fileName
            self.destinationURL = destinationURL
            self.mimeType = mimeType
            self.addedAt = addedAt
            self.expectedBytes = expectedBytes
            self.downloadedBytes = 0
            self.bytesPerSecond = 0
        }
    }

    private struct TerminalDownload {
        let id: UUID
        let sourceURL: URL
        let originalURL: URL?
        let fileName: String
        let mimeType: String?
        let addedAt: Date
        let expectedBytes: Int64?
        let downloadedBytes: Int64
        let state: DownloadItemSnapshot.State
        let failureDescription: String?
        let canRetry: Bool
    }
    
    private let fileManager: FileManager
    private let storage: StorageURLs
    private let storageIsAvailable: Bool
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.DownloadStore.Queue", qos: .userInitiated)
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    private var activeDownloads: [Int: ActiveDownload] = [:]
    private var capturedDownloads: [String: CapturedDownload] = [:]
    private var terminalDownloads: [UUID: TerminalDownload] = [:]
    private var persistedDownloads: [PersistedDownloadEntry] = []
    private let progressNotificationInterval: TimeInterval = 0.35
    private var lastProgressNotificationTime: TimeInterval = 0
    private var pendingProgressNotification: DispatchWorkItem?
    private var progressNotificationGeneration = 0
    private var hasUnviewedCompletedDownloads = false
    
    // MARK: - Lifecycle
    
    override init() {
        self.fileManager = .default
        
        let documentsDirectoryURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.storageIsAvailable = documentsDirectoryURL != nil && applicationSupportDirectoryURL != nil
        let fallbackDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent("ReynardUnavailableStorage", isDirectory: true)
        
        let downloadsDirectoryURL = (documentsDirectoryURL ?? fallbackDirectoryURL).appendingPathComponent("Downloads", isDirectory: true)
        let appDataDirectoryURL = (applicationSupportDirectoryURL ?? fallbackDirectoryURL).appendingPathComponent("AppData", isDirectory: true)
        let manifestFileURL = appDataDirectoryURL.appendingPathComponent("DownloadStore", isDirectory: false)
        self.storage = StorageURLs(
            downloadsDirectoryURL: downloadsDirectoryURL,
            appDataDirectoryURL: appDataDirectoryURL,
            manifestFileURL: manifestFileURL,
            manifestBackupFileURL: appDataDirectoryURL.appendingPathComponent("DownloadStore.backup", isDirectory: false)
        )
        
        super.init()
        
        stateQueue.sync {
            self.prepareStorageLocked()
            self.loadPersistedDownloadsLocked()
        }
    }
    
    // MARK: - Downloads
    
    func currentSnapshot() -> DownloadStoreSnapshot {
        stateQueue.sync {
            makeSnapshotLocked()
        }
    }
    
    // MARK: - Pending Downloads
    
    func pendingDownload(from response: ExternalResponseInfo) -> PendingDownload? {
        guard storageIsAvailable, let sourceURL = URL(string: response.url) else {
            return nil
        }
        
        return PendingDownload(
            fileName: resolvedFileName(
                suggestedFileName: response.filename,
                sourceURL: sourceURL,
                mimeType: response.mimeType
            ),
            sourceHost: sourceURL.host ?? sourceURL.absoluteString,
            expectedBytes: response.contentLength.flatMap { $0 > 0 ? $0 : nil },
            mimeType: response.mimeType,
            startHandler: { [weak self] in
                self?.beginCapturedDownload(
                    localFilePath: response.localFilePath,
                    sourceURL: sourceURL,
                    suggestedFileName: response.filename,
                    mimeType: response.mimeType,
                    expectedBytes: response.contentLength
                )
            }
        )
    }
    
    func pendingDownload(from request: SavePdfInfo) -> PendingDownload? {
        guard storageIsAvailable else {
            return nil
        }
        let candidateURLs = [request.url, request.originalUrl].compactMap { $0 }.compactMap(URL.init(string:))
        guard let sourceURL = candidateURLs.first(where: { URLUtils.isWebURL($0) }) else {
            return nil
        }
        
        return PendingDownload(
            fileName: resolvedFileName(
                suggestedFileName: request.filename,
                sourceURL: sourceURL,
                mimeType: "application/pdf"
            ),
            sourceHost: sourceURL.host ?? sourceURL.absoluteString,
            expectedBytes: nil,
            mimeType: "application/pdf",
            startHandler: { [weak self] in
                self?.enqueueDownload(
                    sourceURL: sourceURL,
                    originalURL: URL(string: request.originalUrl ?? ""),
                    suggestedFileName: request.filename,
                    mimeType: "application/pdf"
                )
            }
        )
    }
    
    func start(_ download: PendingDownload) {
        download.startHandler()
    }
    
    func updateCapturedDownload(localFilePath: String, bytesReceived: Int64) -> Bool {
        return stateQueue.sync {
            guard let active = capturedDownloads[localFilePath] else {
                return false
            }
            
            updateCapturedProgress(active, bytesReceived: bytesReceived)
            return true
        }
    }
    
    func completeCapturedDownload(localFilePath: String, succeeded: Bool) {
        stateQueue.sync {
            self.completeCapturedDownloadLocked(
                localFilePath: localFilePath,
                succeeded: succeeded
            )
        }
    }
    
    // MARK: - Download Management
    
    func cancel(id: UUID) {
        stateQueue.async {
            if let active = self.activeDownloads.values.first(where: { $0.id == id }) {
                self.activeDownloads.removeValue(forKey: active.task.taskIdentifier)
                self.terminalDownloads[id] = self.terminalDownload(
                    from: active,
                    state: .cancelled,
                    failureDescription: NSLocalizedString("Cancelled", comment: "Download state"),
                    canRetry: true
                )
                active.task.cancel()
                self.postDidChange()
                return
            }
            
            guard let captured = self.capturedDownloads.values.first(where: { $0.id == id }) else {
                return
            }
            
            self.capturedDownloads.removeValue(forKey: captured.localFilePath)
            if let temporaryURL = DownloadFileSafety.capturedTemporaryFileURL(forPath: captured.localFilePath) {
                try? self.fileManager.removeItem(at: temporaryURL)
            }
            self.terminalDownloads[id] = self.terminalDownload(
                from: captured,
                state: .cancelled,
                failureDescription: NSLocalizedString("Cancelled", comment: "Download state"),
                canRetry: false
            )
            self.postDidChange()
        }
    }

    func retry(id: UUID) {
        stateQueue.async {
            guard let failed = self.terminalDownloads[id],
                  failed.canRetry,
                  failed.state == .failed || failed.state == .cancelled else {
                return
            }
            self.terminalDownloads.removeValue(forKey: id)
            self.enqueueDownloadLocked(
                sourceURL: failed.sourceURL,
                originalURL: failed.originalURL,
                suggestedFileName: failed.fileName,
                mimeType: failed.mimeType
            )
        }
    }
    
    func removeDownload(id: UUID) {
        stateQueue.async {
            if self.terminalDownloads.removeValue(forKey: id) != nil {
                self.postDidChange()
                return
            }

            guard let index = self.persistedDownloads.firstIndex(where: { $0.id == id }) else {
                return
            }
            
            let entry = self.persistedDownloads.remove(at: index)
            if let fileURL = DownloadFileSafety.containedFileURL(
                forRelativePath: entry.relativePath,
                in: self.storage.downloadsDirectoryURL
            ), self.fileManager.fileExists(atPath: fileURL.path) {
                try? self.fileManager.removeItem(at: fileURL)
            }
            
            self.savePersistedDownloadsLocked()
            self.postDidChange()
        }
    }
    
    func clearCompletedDownloadFiles(since startDate: Date? = nil) {
        stateQueue.async {
            let partition = DownloadCleanupPolicy.partition(
                self.persistedDownloads,
                since: startDate,
                addedAt: { $0.addedAt }
            )
            self.persistedDownloads = partition.retained
            let fileURLs = partition.removed.compactMap {
                DownloadFileSafety.containedFileURL(
                    forRelativePath: $0.relativePath,
                    in: self.storage.downloadsDirectoryURL
                )
            }
            
            for fileURL in Set(fileURLs) {
                try? self.fileManager.removeItem(at: fileURL)
            }
            
            if !self.fileManager.fileExists(atPath: self.storage.downloadsDirectoryURL.path) {
                try? self.fileManager.createDirectory(
                    at: self.storage.downloadsDirectoryURL,
                    withIntermediateDirectories: true
                )
            }
            
            self.savePersistedDownloadsLocked()
            self.postDidChange()
        }
    }
    
    func markCompletedAsViewed() {
        stateQueue.async {
            guard self.hasUnviewedCompletedDownloads else {
                return
            }
            
            self.hasUnviewedCompletedDownloads = false
            self.postDidChange()
        }
    }
    
    // MARK: - Active Downloads
    
    private func beginCapturedDownload(
        localFilePath: String,
        sourceURL: URL,
        suggestedFileName: String?,
        mimeType: String?,
        expectedBytes: Int64?
    ) {
        stateQueue.sync {
            guard self.storageIsAvailable,
                  !localFilePath.isEmpty,
                  DownloadFileSafety.capturedTemporaryFileURL(forPath: localFilePath) != nil,
                  self.capturedDownloads[localFilePath] == nil else {
                return
            }
            self.prepareStorageLocked()
            
            let fileName = self.resolvedFileName(
                suggestedFileName: suggestedFileName,
                sourceURL: sourceURL,
                mimeType: mimeType
            )
            let destinationURL = self.makeUniqueDestinationURLLocked(for: fileName)
            self.capturedDownloads[localFilePath] = CapturedDownload(
                id: UUID(),
                localFilePath: localFilePath,
                sourceURL: sourceURL,
                fileName: destinationURL.lastPathComponent,
                destinationURL: destinationURL,
                mimeType: mimeType,
                addedAt: Date(),
                expectedBytes: expectedBytes
            )
            self.postDidStartDownload()
            self.postDidChange()
        }
    }
    
    private func enqueueDownload(
        sourceURL: URL,
        originalURL: URL?,
        suggestedFileName: String?,
        mimeType: String?
    ) {
        stateQueue.async {
            self.enqueueDownloadLocked(
                sourceURL: sourceURL,
                originalURL: originalURL,
                suggestedFileName: suggestedFileName,
                mimeType: mimeType
            )
        }
    }

    private func enqueueDownloadLocked(
        sourceURL: URL,
        originalURL: URL?,
        suggestedFileName: String?,
        mimeType: String?
    ) {
        guard storageIsAvailable else {
            return
        }
        prepareStorageLocked()

        let fileName = resolvedFileName(
            suggestedFileName: suggestedFileName,
            sourceURL: sourceURL,
            mimeType: mimeType
        )
        let destinationURL = makeUniqueDestinationURLLocked(for: fileName)

        let task = session.downloadTask(with: sourceURL)
        let active = ActiveDownload(
            id: UUID(),
            sourceURL: sourceURL,
            originalURL: originalURL,
            fileName: destinationURL.lastPathComponent,
            destinationURL: destinationURL,
            mimeType: mimeType,
            addedAt: Date(),
            task: task
        )

        activeDownloads[task.taskIdentifier] = active
        task.resume()
        postDidStartDownload()
        postDidChange()
    }
    
    // MARK: - Snapshots
    
    private func makeSnapshotLocked() -> DownloadStoreSnapshot {
        let sessionItems = activeDownloads.values
            .map { active in
                DownloadItemSnapshot(
                    id: active.id,
                    fileName: active.fileName,
                    fileURL: nil,
                    sourceURL: active.sourceURL,
                    originalURL: active.originalURL,
                    mimeType: active.mimeType,
                    state: .downloading,
                    fileExists: true,
                    totalBytes: active.expectedBytes,
                    downloadedBytes: active.downloadedBytes,
                    bytesPerSecond: active.bytesPerSecond,
                    addedAt: active.addedAt,
                    failureDescription: nil,
                    canRetry: false
                )
            }
            .sorted { $0.addedAt > $1.addedAt }
        
        let capturedItems = capturedDownloads.values
            .map { active in
                DownloadItemSnapshot(
                    id: active.id,
                    fileName: active.fileName,
                    fileURL: nil,
                    sourceURL: active.sourceURL,
                    originalURL: nil,
                    mimeType: active.mimeType,
                    state: .downloading,
                    fileExists: true,
                    totalBytes: active.expectedBytes,
                    downloadedBytes: active.downloadedBytes,
                    bytesPerSecond: active.bytesPerSecond,
                    addedAt: active.addedAt,
                    failureDescription: nil,
                    canRetry: false
                )
            }
        
        let activeItems = (sessionItems + capturedItems)
            .sorted { $0.addedAt > $1.addedAt }

        let terminalItems = terminalDownloads.values
            .map { item in
                DownloadItemSnapshot(
                    id: item.id,
                    fileName: item.fileName,
                    fileURL: nil,
                    sourceURL: item.sourceURL,
                    originalURL: item.originalURL,
                    mimeType: item.mimeType,
                    state: item.state,
                    fileExists: false,
                    totalBytes: item.expectedBytes,
                    downloadedBytes: item.downloadedBytes,
                    bytesPerSecond: 0,
                    addedAt: item.addedAt,
                    failureDescription: item.failureDescription,
                    canRetry: item.canRetry
                )
            }
            .sorted { $0.addedAt > $1.addedAt }
        
        let completedItems = persistedDownloads
            .map { entry in
                let fileURL = DownloadFileSafety.containedFileURL(
                    forRelativePath: entry.relativePath,
                    in: storage.downloadsDirectoryURL
                )
                return DownloadItemSnapshot(
                    id: entry.id,
                    fileName: entry.fileName,
                    fileURL: fileURL,
                    sourceURL: URL(string: entry.sourceURLString) ?? fileURL ?? storage.downloadsDirectoryURL,
                    originalURL: entry.originalURLString.flatMap(URL.init(string:)),
                    mimeType: entry.mimeType,
                    state: .completed,
                    fileExists: fileURL.map { fileManager.fileExists(atPath: $0.path) } ?? false,
                    totalBytes: entry.fileSize,
                    downloadedBytes: entry.fileSize,
                    bytesPerSecond: 0,
                    addedAt: entry.addedAt,
                    failureDescription: nil,
                    canRetry: false
                )
            }
        
        return DownloadStoreSnapshot(summary: makeSummaryLocked(), items: activeItems + terminalItems + completedItems)
    }
    
    private func makeSummaryLocked() -> DownloadStoreSummary {
        let activeProgress = activeDownloads.values.map { ($0.expectedBytes, $0.downloadedBytes) }
        + capturedDownloads.values.map { ($0.expectedBytes, $0.downloadedBytes) }
        let totalExpectedBytes = activeProgress.reduce(Int64(0)) { partialResult, item in
            partialResult + max(item.0 ?? 0, 0)
        }
        let totalDownloadedBytes = activeProgress.reduce(Int64(0)) { partialResult, item in
            partialResult + min(item.1, item.0 ?? item.1)
        }
        let aggregateProgress: Float
        if totalExpectedBytes > 0 {
            aggregateProgress = Float(totalDownloadedBytes) / Float(totalExpectedBytes)
        } else {
            aggregateProgress = 0
        }
        
        return DownloadStoreSummary(
            totalCount: persistedDownloads.count + terminalDownloads.count + activeProgress.count,
            activeCount: activeProgress.count,
            aggregateProgress: min(max(aggregateProgress, 0), 1),
            hasUnviewedCompletedDownloads: hasUnviewedCompletedDownloads
        )
    }
    
    // MARK: - Persistence
    
    private func prepareStorageLocked() {
        guard storageIsAvailable else {
            return
        }
        try? fileManager.createDirectory(at: storage.downloadsDirectoryURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: storage.appDataDirectoryURL, withIntermediateDirectories: true)
        
        guard !fileManager.fileExists(atPath: storage.manifestFileURL.path) else {
            return
        }
        
        let emptyManifest = (try? JSONEncoder().encode([PersistedDownloadEntry]())) ?? Data("[]".utf8)
        fileManager.createFile(atPath: storage.manifestFileURL.path, contents: emptyManifest)
    }
    
    private func loadPersistedDownloadsLocked() {
        guard storageIsAvailable else {
            persistedDownloads = []
            return
        }

        let recovery = DownloadManifestRecovery.recover(
            primaryData: try? Data(contentsOf: storage.manifestFileURL),
            backupData: try? Data(contentsOf: storage.manifestBackupFileURL),
            decode: decodedAndValidatedEntries(from:)
        )
        persistedDownloads = recovery.entries.sorted { $0.addedAt > $1.addedAt }
        if recovery.source != .primary {
            writeManifestLocked(createBackup: false)
        }
    }
    
    private func savePersistedDownloadsLocked() {
        writeManifestLocked(createBackup: true)
    }

    private func writeManifestLocked(createBackup: Bool) {
        guard storageIsAvailable else {
            return
        }
        guard let data = try? JSONEncoder().encode(persistedDownloads.sorted { $0.addedAt > $1.addedAt }) else {
            return
        }
        
        if createBackup,
           let currentData = try? Data(contentsOf: storage.manifestFileURL),
           decodedAndValidatedEntries(from: currentData) != nil {
            try? currentData.write(to: storage.manifestBackupFileURL, options: .atomic)
        }
        try? data.write(to: storage.manifestFileURL, options: .atomic)
    }
    
    private func decodedAndValidatedEntries(from data: Data) -> [PersistedDownloadEntry]? {
        guard let decoded = try? JSONDecoder().decode([PersistedDownloadEntry].self, from: data) else {
            return nil
        }
        return decoded.filter {
            DownloadFileSafety.containedFileURL(
                forRelativePath: $0.relativePath,
                in: storage.downloadsDirectoryURL
            ) != nil
        }
    }

    // MARK: - Files
    
    private func resolvedFileName(suggestedFileName: String?, sourceURL: URL, mimeType: String?) -> String {
        let fallbackName = sourceURL.lastPathComponent.isEmpty ? NSLocalizedString("Download", comment: "") : sourceURL.lastPathComponent
        let initialName = DownloadFileSafety.sanitizedFileName(
            suggestedFileName ?? fallbackName,
            fallback: NSLocalizedString("Download", comment: "")
        )
        
        guard URL(fileURLWithPath: initialName).pathExtension.isEmpty,
              let mimeType,
              let contentType = UTTypeCreatePreferredIdentifierForTag(
                kUTTagClassMIMEType,
                mimeType as CFString,
                nil
              )?.takeRetainedValue(),
              let preferredExtension = UTTypeCopyPreferredTagWithClass(
                contentType,
                kUTTagClassFilenameExtension
              )?.takeRetainedValue() as String? else {
            return initialName
        }
        
        return DownloadFileSafety.sanitizedFileName(
            "\(initialName).\(preferredExtension)",
            fallback: NSLocalizedString("Download", comment: "")
        )
    }
    
    private func makeUniqueDestinationURLLocked(for fileName: String) -> URL {
        let activeNames = Set(
            activeDownloads.values.map { $0.destinationURL.lastPathComponent.lowercased() }
            + capturedDownloads.values.map { $0.destinationURL.lastPathComponent.lowercased() }
        )
        return DownloadFileSafety.uniqueDestinationURL(
            for: fileName,
            in: storage.downloadsDirectoryURL,
            reservedFileNames: activeNames,
            fileExists: { self.fileManager.fileExists(atPath: $0.path) }
        )
    }
    
    private func importFileLocked(from sourceURL: URL, to destinationURL: URL) -> Bool {
        guard fileManager.fileExists(atPath: sourceURL.path),
              DownloadFileSafety.containedFileURL(
                forRelativePath: destinationURL.lastPathComponent,
                in: storage.downloadsDirectoryURL
              )?.standardizedFileURL == destinationURL.standardizedFileURL else {
            return false
        }
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                try? fileManager.removeItem(at: sourceURL)
            }
            
            return true
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            return false
        }
    }
    
    // MARK: - Transfer Lifecycle
    
    private func completeCapturedDownloadLocked(localFilePath: String, succeeded: Bool) {
        guard let active = capturedDownloads.removeValue(forKey: localFilePath) else {
            return
        }
        
        guard let sourceFileURL = DownloadFileSafety.capturedTemporaryFileURL(forPath: localFilePath) else {
            terminalDownloads[active.id] = terminalDownload(
                from: active,
                state: .failed,
                failureDescription: NSLocalizedString("Couldn’t save the downloaded file.", comment: "Invalid temporary file path"),
                canRetry: false
            )
            postDidChange()
            return
        }
        guard succeeded else {
            try? fileManager.removeItem(at: sourceFileURL)
            terminalDownloads[active.id] = terminalDownload(
                from: active,
                state: .failed,
                failureDescription: NSLocalizedString("Download failed in the browser engine.", comment: "Captured download failure"),
                canRetry: false
            )
            postDidChange()
            return
        }
        
        prepareStorageLocked()
        
        guard importFileLocked(from: sourceFileURL, to: active.destinationURL) else {
            terminalDownloads[active.id] = terminalDownload(
                from: active,
                state: .failed,
                failureDescription: NSLocalizedString("Couldn’t save the downloaded file.", comment: "File move failure"),
                canRetry: false
            )
            postDidChange()
            return
        }
        
        let fileSize = resolvedFileSize(at: active.destinationURL) ?? active.downloadedBytes
        persistedDownloads.insert(
            PersistedDownloadEntry(
                id: active.id,
                fileName: active.fileName,
                relativePath: active.destinationURL.lastPathComponent,
                sourceURLString: active.sourceURL.absoluteString,
                originalURLString: nil,
                mimeType: active.mimeType,
                fileSize: fileSize,
                addedAt: active.addedAt
            ),
            at: 0
        )
        savePersistedDownloadsLocked()
        hasUnviewedCompletedDownloads = true
        postDidChange()
    }
    
    private func updateCapturedProgress(_ active: CapturedDownload, bytesReceived: Int64) {
        active.downloadedBytes = bytesReceived
        updateTransferRate(
            totalBytesWritten: bytesReceived,
            bytesPerSecond: &active.bytesPerSecond,
            lastProgressSample: &active.lastProgressSample
        )
        postProgressDidChangeLocked()
    }
    
    private func updateTransferRate(
        totalBytesWritten: Int64,
        bytesPerSecond: inout Int64,
        lastProgressSample: inout ProgressSample?
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        if let previousSample = lastProgressSample {
            let deltaTime = max(now - previousSample.timestamp, 0.001)
            let deltaBytes = max(totalBytesWritten - previousSample.bytesWritten, 0)
            let instantaneousSpeed = Int64(Double(deltaBytes) / deltaTime)
            if bytesPerSecond == 0 {
                bytesPerSecond = instantaneousSpeed
            } else {
                let smoothedSpeed = (Double(bytesPerSecond) * 0.65) + (Double(instantaneousSpeed) * 0.35)
                bytesPerSecond = Int64(smoothedSpeed)
            }
        }
        lastProgressSample = ProgressSample(bytesWritten: totalBytesWritten, timestamp: now)
    }
    
    private func completeDownload(taskIdentifier: Int, temporaryLocation: URL) {
        guard let active = activeDownloads.removeValue(forKey: taskIdentifier) else {
            return
        }
        
        prepareStorageLocked()
        
        do {
            if fileManager.fileExists(atPath: active.destinationURL.path) {
                try fileManager.removeItem(at: active.destinationURL)
            }
            
            try fileManager.moveItem(at: temporaryLocation, to: active.destinationURL)
            let fileSize = resolvedFileSize(at: active.destinationURL) ?? active.downloadedBytes
            
            persistedDownloads.insert(
                PersistedDownloadEntry(
                    id: active.id,
                    fileName: active.fileName,
                    relativePath: active.destinationURL.lastPathComponent,
                    sourceURLString: active.sourceURL.absoluteString,
                    originalURLString: active.originalURL?.absoluteString,
                    mimeType: active.mimeType,
                    fileSize: fileSize,
                    addedAt: active.addedAt
                ),
                at: 0
            )
            savePersistedDownloadsLocked()
            hasUnviewedCompletedDownloads = true
        } catch {
            try? fileManager.removeItem(at: temporaryLocation)
            try? fileManager.removeItem(at: active.destinationURL)
            terminalDownloads[active.id] = terminalDownload(
                from: active,
                state: .failed,
                failureDescription: failureDescription(for: error),
                canRetry: true
            )
        }
        
        postDidChange()
    }
    
    private func resolvedFileSize(at url: URL) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        
        return size.int64Value
    }
    
    private func updateProgress(
        taskIdentifier: Int,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let active = activeDownloads[taskIdentifier] else {
            return
        }
        
        active.downloadedBytes = totalBytesWritten
        if totalBytesExpectedToWrite > 0 {
            active.expectedBytes = totalBytesExpectedToWrite
        }
        
        updateTransferRate(
            totalBytesWritten: totalBytesWritten,
            bytesPerSecond: &active.bytesPerSecond,
            lastProgressSample: &active.lastProgressSample
        )
        
        postProgressDidChangeLocked()
    }
    
    private func failDownload(taskIdentifier: Int, error: Error) {
        guard let active = activeDownloads.removeValue(forKey: taskIdentifier) else {
            return
        }
        try? fileManager.removeItem(at: active.destinationURL)
        terminalDownloads[active.id] = terminalDownload(
            from: active,
            state: .failed,
            failureDescription: failureDescription(for: error),
            canRetry: true
        )
        postDidChange()
    }

    private func terminalDownload(
        from active: ActiveDownload,
        state: DownloadItemSnapshot.State,
        failureDescription: String?,
        canRetry: Bool
    ) -> TerminalDownload {
        TerminalDownload(
            id: active.id,
            sourceURL: active.sourceURL,
            originalURL: active.originalURL,
            fileName: active.fileName,
            mimeType: active.mimeType,
            addedAt: active.addedAt,
            expectedBytes: active.expectedBytes,
            downloadedBytes: active.downloadedBytes,
            state: state,
            failureDescription: failureDescription,
            canRetry: canRetry
        )
    }

    private func terminalDownload(
        from active: CapturedDownload,
        state: DownloadItemSnapshot.State,
        failureDescription: String?,
        canRetry: Bool
    ) -> TerminalDownload {
        TerminalDownload(
            id: active.id,
            sourceURL: active.sourceURL,
            originalURL: nil,
            fileName: active.fileName,
            mimeType: active.mimeType,
            addedAt: active.addedAt,
            expectedBytes: active.expectedBytes,
            downloadedBytes: active.downloadedBytes,
            state: state,
            failureDescription: failureDescription,
            canRetry: canRetry
        )
    }

    private func failureDescription(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteOutOfSpaceError:
                return NSLocalizedString("Not enough storage space.", comment: "Download failure")
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                return NSLocalizedString("Reynard doesn’t have permission to save this file.", comment: "Download failure")
            default:
                return NSLocalizedString("Couldn’t save the downloaded file.", comment: "Download failure")
            }
        }

        if nsError.domain == NSURLErrorDomain {
            return NSLocalizedString("A network error interrupted the download.", comment: "Download failure")
        }
        return NSLocalizedString("The download could not be completed.", comment: "Download failure")
    }
    
    // MARK: - Notifications
    
    private func postDidChange() {
        progressNotificationGeneration += 1
        pendingProgressNotification?.cancel()
        pendingProgressNotification = nil
        lastProgressNotificationTime = ProcessInfo.processInfo.systemUptime
        dispatchDidChangeNotification()
    }

    private func postProgressDidChangeLocked() {
        guard pendingProgressNotification == nil else {
            return
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - lastProgressNotificationTime
        if elapsed >= progressNotificationInterval {
            lastProgressNotificationTime = ProcessInfo.processInfo.systemUptime
            dispatchDidChangeNotification()
            return
        }

        let generation = progressNotificationGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.progressNotificationGeneration == generation else {
                return
            }
            self.pendingProgressNotification = nil
            self.lastProgressNotificationTime = ProcessInfo.processInfo.systemUptime
            self.dispatchDidChangeNotification()
        }
        pendingProgressNotification = workItem
        stateQueue.asyncAfter(
            deadline: .now() + max(progressNotificationInterval - elapsed, 0),
            execute: workItem
        )
    }

    private func dispatchDidChangeNotification() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .downloadStoreDidChange, object: self)
        }
    }
    
    private func postDidStartDownload() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .downloadStoreDidStartDownload, object: self)
        }
    }
}

extension DownloadStore: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        stateQueue.async {
            self.updateProgress(
                taskIdentifier: downloadTask.taskIdentifier,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        stateQueue.sync {
            self.completeDownload(taskIdentifier: downloadTask.taskIdentifier, temporaryLocation: location)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else {
            return
        }
        
        stateQueue.async {
            self.failDownload(taskIdentifier: task.taskIdentifier, error: error)
        }
    }
}
