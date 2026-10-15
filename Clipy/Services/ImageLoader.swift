//
//  ImageLoader.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI
import Combine
import AppKit
import ImageIO

actor ImageLoader {
    static let shared = ImageLoader()
    
    // NSCache is thread-safe, allowing synchronous nonisolated reads on the main thread
    private nonisolated(unsafe) let imageCache = NSCache<NSString, NSImage>()
    private nonisolated(unsafe) let thumbnailCache = NSCache<NSString, NSImage>()
    private nonisolated(unsafe) let dimensionCache = NSCache<NSString, NSValue>()
    
    private var inFlightImages: [String: Task<NSImage?, Never>] = [:]
    private var inFlightThumbnails: [String: Task<NSImage?, Never>] = [:]
    
    init() {
        imageCache.countLimit = 60
        thumbnailCache.countLimit = 400
        dimensionCache.countLimit = 500
    }
    
    nonisolated func cachedImage(filename: String) -> NSImage? {
        imageCache.object(forKey: filename as NSString)
    }
    
    nonisolated func cachedThumbnail(filename: String) -> NSImage? {
        thumbnailCache.object(forKey: filename as NSString)
    }
    
    nonisolated func cachedDimensions(filename: String) -> NSSize? {
        dimensionCache.object(forKey: filename as NSString)?.sizeValue
    }
    
    private nonisolated static func resolvedSafeFileURL(for filename: String) -> URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let baseDir = appSupportURL.appendingPathComponent("Clipy").standardizedFileURL
        let fileURL = baseDir.appendingPathComponent(filename).standardizedFileURL
        guard fileURL.path.hasPrefix(baseDir.path + "/") else {
            return nil
        }
        return fileURL
    }
    
    func loadThumbnail(filename: String, maxPixelSize: Int = 80) async -> NSImage? {
        let key = filename as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        if let existing = inFlightThumbnails[filename] {
            return await existing.value
        }
        
        let task = Task.detached(priority: .userInitiated) { () -> (NSImage?, NSSize?) in
            guard let fileURL = Self.resolvedSafeFileURL(for: filename),
                  let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
                return (nil, nil)
            }
            
            var originalSize: NSSize? = nil
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
               let height = props[kCGImagePropertyPixelHeight] as? CGFloat,
               width > 0, height > 0 {
                originalSize = NSSize(width: width, height: height)
            }
            
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                let thumb = NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
                return (thumb, originalSize)
            }
            
            guard let fallback = NSImage(contentsOf: fileURL) else {
                return (nil, originalSize)
            }
            return (fallback, originalSize ?? fallback.size)
        }
        
        let wrapper = Task<NSImage?, Never> {
            let (thumb, origSize) = await task.value
            if let origSize {
                self.dimensionCache.setObject(NSValue(size: origSize), forKey: key)
            }
            if let thumb {
                self.thumbnailCache.setObject(thumb, forKey: key)
            }
            return thumb
        }
        
        inFlightThumbnails[filename] = wrapper
        let result = await wrapper.value
        inFlightThumbnails[filename] = nil
        return result
    }
    
    func loadImage(filename: String) async -> NSImage? {
        let key = filename as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }
        if let existing = inFlightImages[filename] {
            return await existing.value
        }
        
        let task = Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let fileURL = Self.resolvedSafeFileURL(for: filename),
                  let image = NSImage(contentsOf: fileURL) else {
                return nil
            }
            // Force bitmap decoding on background thread so main thread doesn't stall during draw
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return NSImage(cgImage: cgImage, size: image.size)
            }
            return image
        }
        
        let wrapper = Task<NSImage?, Never> {
            let image = await task.value
            if let image {
                self.imageCache.setObject(image, forKey: key)
                if self.dimensionCache.object(forKey: key) == nil {
                    self.dimensionCache.setObject(NSValue(size: image.size), forKey: key)
                }
            }
            return image
        }
        
        inFlightImages[filename] = wrapper
        let result = await wrapper.value
        inFlightImages[filename] = nil
        return result
    }
}
