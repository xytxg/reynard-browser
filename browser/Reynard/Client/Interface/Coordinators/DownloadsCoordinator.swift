//
//  DownloadsCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

protocol DownloadsCoordinatorDelegate: AnyObject {
    var downloadsShouldRefreshLayoutForStoreChange: Bool { get }
    
    func downloadsCoordinator(_ coordinator: DownloadsCoordinator, didUpdate summary: DownloadStoreSummary)
    func downloadsCoordinatorDidRequestLayoutRefresh(_ coordinator: DownloadsCoordinator)
}

final class DownloadsCoordinator {
    private struct ConfirmationRequest {
        let download: DownloadStore.PendingDownload
        let completion: (Bool) -> Void
    }
    
    private weak var delegate: DownloadsCoordinatorDelegate?
    private var confirmationQueue: [ConfirmationRequest] = []
    private var isShowingConfirmationAlert = false
    private var storeObserver: NSObjectProtocol?
    
    init(delegate: DownloadsCoordinatorDelegate) {
        self.delegate = delegate
    }
    
    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }
    
    func startObservingStore() {
        guard storeObserver == nil else {
            return
        }
        
        storeObserver = NotificationCenter.default.addObserver(
            forName: .downloadStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncToolbarButtonState()
        }
    }
    
    func syncToolbarButtonState() {
        let summary = DownloadStore.shared.currentSnapshot().summary
        delegate?.downloadsCoordinator(self, didUpdate: summary)
        if delegate?.downloadsShouldRefreshLayoutForStoreChange == true {
            delegate?.downloadsCoordinatorDidRequestLayoutRefresh(self)
        }
    }
    
    func enqueueConfirmation(_ pendingDownload: DownloadStore.PendingDownload) {
        queueConfirmation(pendingDownload) { shouldStart in
            if shouldStart {
                DownloadStore.shared.start(pendingDownload)
            }
        }
    }
    
    func confirm(_ pendingDownload: DownloadStore.PendingDownload) async -> Bool {
        return await withCheckedContinuation { continuation in
            queueConfirmation(pendingDownload) { shouldStart in
                if shouldStart {
                    DownloadStore.shared.start(pendingDownload)
                }
                continuation.resume(returning: shouldStart)
            }
        }
    }
    
    private func queueConfirmation(
        _ pendingDownload: DownloadStore.PendingDownload,
        completion: @escaping (Bool) -> Void
    ) {
        confirmationQueue.append(
            ConfirmationRequest(download: pendingDownload, completion: completion)
        )
        presentNextConfirmationAlertIfNeeded()
    }
    
    private func presentNextConfirmationAlertIfNeeded() {
        guard !isShowingConfirmationAlert,
              let request = confirmationQueue.first else {
            return
        }
        
        isShowingConfirmationAlert = true

        let sizeText: String
        if let expectedBytes = request.download.expectedBytes, expectedBytes > 0 {
            sizeText = ByteCountFormatter.string(fromByteCount: expectedBytes, countStyle: .file)
        } else {
            sizeText = NSLocalizedString("Unknown size", comment: "")
        }
        let typeText = request.download.mimeType ?? NSLocalizedString("Unknown type", comment: "Download MIME type")
        let details = [
            String(format: NSLocalizedString("Source: %@", comment: "Download source host"), request.download.sourceHost),
            String(format: NSLocalizedString("Size: %@", comment: "Download file size"), sizeText),
            String(format: NSLocalizedString("Type: %@", comment: "Download MIME type"), typeText),
        ].joined(separator: "\n")
        
        AlertPresenter.show(
            title: String(format: NSLocalizedString("Do you want to download \"%@\"?", comment: "File name"), request.download.fileName),
            message: details,
            buttons: [
                AlertPresenter.Button(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { [weak self] in
                    self?.resolveConfirmation(shouldStartDownload: false)
                },
                AlertPresenter.Button(title: NSLocalizedString("Download", comment: "")) { [weak self] in
                    Haptics.success()
                    self?.resolveConfirmation(shouldStartDownload: true)
                },
            ]
        )
    }
    
    private func resolveConfirmation(shouldStartDownload: Bool) {
        guard !confirmationQueue.isEmpty else {
            isShowingConfirmationAlert = false
            return
        }
        
        let request = confirmationQueue.removeFirst()
        isShowingConfirmationAlert = false
        request.completion(shouldStartDownload)
        
        DispatchQueue.main.async { [weak self] in
            self?.presentNextConfirmationAlertIfNeeded()
        }
    }
}
