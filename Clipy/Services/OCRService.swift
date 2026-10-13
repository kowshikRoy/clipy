//
//  OCRService.swift
//  Clipy
//
//  Created by Clipy on 14.10.2026.
//

import Foundation
import AppKit
import Vision

actor OCRService {
    static let shared = OCRService()
    
    private var cache: [String: String] = [:]
    private var inFlightTasks: [String: Task<String?, Never>] = [:]
    
    func recognizeText(in filename: String) async -> String? {
        if let cached = cache[filename] {
            return cached
        }
        
        if let existing = inFlightTasks[filename] {
            return await existing.value
        }
        
        let task = Task<String?, Never> {
            return await performOCR(filename: filename)
        }
        
        inFlightTasks[filename] = task
        let result = await task.value
        inFlightTasks[filename] = nil
        
        if let result = result {
            cache[filename] = result
        }
        return result
    }
    
    private func performOCR(filename: String) async -> String? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let baseDir = appSupportURL.appendingPathComponent("Clipy").standardizedFileURL
        let fileURL = baseDir.appendingPathComponent(filename).standardizedFileURL
        
        // Enforce directory boundary check to prevent path traversal
        guard fileURL.path.hasPrefix(baseDir.path + "/") else {
            return nil
        }
        
        guard let nsImage = NSImage(contentsOf: fileURL),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: joined)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
