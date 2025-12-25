//
//  ImageLoader.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI
import Combine
import AppKit

actor ImageLoader {
    static let shared = ImageLoader()
    
    private let cache = NSCache<NSString, NSImage>()
    
    // We can add in-flight deduplication if needed, but for now kept simple
    
    func loadImage(filename: String) -> NSImage? {
        if let cached = cache.object(forKey: filename as NSString) {
            return cached
        }
        
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = appSupportURL.appendingPathComponent("Clipy").appendingPathComponent(filename)
        guard let image = NSImage(contentsOf: fileURL) else { return nil }
        
        cache.setObject(image, forKey: filename as NSString)
        return image
    }
}
