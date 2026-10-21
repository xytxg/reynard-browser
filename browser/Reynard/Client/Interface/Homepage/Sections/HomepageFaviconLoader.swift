//
//  HomepageFaviconLoader.swift
//  Reynard
//
//  Created by Minh Ton on 24/6/26.
//

import UIKit

final class HomepageFaviconLoader {
    private static let faviconStore = FaviconStore.shared
    private static let fallbackIconName = "reynard.globe"
    
    private let updateIcon: (UIImage?, UIColor?, Bool) -> Void
    private var representedURL: URL?
    private var loadTask: Task<Void, Never>?
    
    init(_ updateIcon: @escaping (UIImage?, UIColor?, Bool) -> Void) {
        self.updateIcon = updateIcon
    }
    
    deinit {
        loadTask?.cancel()
    }
    
    func loadIcon(for url: URL) {
        representedURL = url
        loadTask?.cancel()
        loadTask = nil
        
        if let bundledImage = UIImage(named: Self.bundledIconName(for: url)) {
            updateIcon(bundledImage, nil, false)
            return
        }
        
        if let cachedPresentation = Self.faviconStore.cachedFaviconPresentation(for: url) {
            updateIcon(cachedPresentation.image, nil, cachedPresentation.shouldInset)
            return
        }
        
        applyFallbackIcon()
        let loadingURL = url
        loadTask = Task { [weak self] in
            guard let self else {
                return
            }
            
            let loadedImage = await Self.faviconStore.favicon(for: loadingURL)
            guard !Task.isCancelled else {
                return
            }
            
            await MainActor.run {
                guard self.representedURL == loadingURL else {
                    return
                }
                
                guard let loadedImage else {
                    self.applyFallbackIcon()
                    return
                }
                
                let presentation = Self.faviconStore.faviconPresentation(for: loadedImage)
                self.updateIcon(presentation.image, nil, presentation.shouldInset)
            }
        }
    }
    
    func reset() {
        representedURL = nil
        loadTask?.cancel()
        loadTask = nil
        applyFallbackIcon()
    }
    
    private func applyFallbackIcon() {
        updateIcon(UIImage(named: Self.fallbackIconName), .secondaryLabel, false)
    }
    
    private static func bundledIconName(for url: URL) -> String {
        var iconName = url.absoluteString
        
        if let schemeRange = iconName.range(of: "://") {
            iconName.removeSubrange(iconName.startIndex..<schemeRange.upperBound)
        }
        
        if iconName.hasPrefix("www.") {
            iconName.removeFirst(4)
        }
        
        while iconName.hasSuffix("/") {
            iconName.removeLast()
        }
        
        return iconName
    }
}
