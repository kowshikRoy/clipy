//
//  URLMetadataService.swift
//  Clipy
//
//  Created by Clipy on 14.10.2026.
//

import Foundation
import AppKit
import LinkPresentation

struct URLMetadataResult: Sendable, Equatable {
    let title: String?
    let description: String?
}

actor URLMetadataService {
    static let shared = URLMetadataService()
    
    private var cache: [String: URLMetadataResult] = [:]
    private var inFlightTasks: [String: Task<URLMetadataResult?, Never>] = [:]
    private nonisolated(unsafe) let logoMemoryCache = NSCache<NSString, NSImage>()
    private var inFlightLogoTasks: [String: Task<NSImage?, Never>] = [:]
    
    private let faviconDirectory: URL? = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("Clipy/favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.5
        config.timeoutIntervalForResource = 5.5
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        return URLSession(configuration: config)
    }()
    
    func fetchMetadata(for url: URL) async -> URLMetadataResult? {
        let key = url.absoluteString
        
        if let cached = cache[key] {
            return cached
        }
        
        if let existingTask = inFlightTasks[key] {
            return await existingTask.value
        }
        
        let task = Task<URLMetadataResult?, Never> {
            let result = await performFetch(for: url)
            return result
        }
        
        inFlightTasks[key] = task
        let result = await task.value
        inFlightTasks[key] = nil
        
        if let result = result {
            cache[key] = result
        }
        return result
    }
    
    // MARK: - Website Logo (Favicon) Fetching & Caching
    
    nonisolated func cachedWebsiteLogo(for url: URL) -> NSImage? {
        let key = Self.logoCacheKey(for: url) as NSString
        return logoMemoryCache.object(forKey: key)
    }
    
    func fetchWebsiteLogo(for url: URL) async -> NSImage? {
        let key = Self.logoCacheKey(for: url)
        let nsKey = key as NSString
        
        if let cached = logoMemoryCache.object(forKey: nsKey) {
            return cached
        }
        
        if let existing = inFlightLogoTasks[key] {
            return await existing.value
        }
        
        let task = Task<NSImage?, Never> {
            // 1. Check disk cache first
            if let diskImage = loadLogoFromDisk(key: key) {
                return diskImage
            }
            
            // 2. If it's a public domain (not intranet/corp SSO), fetch real website favicon
            if let host = url.host?.lowercased(), Self.canFetchPublicFavicon(host: host, url: url) {
                if let downloaded = await downloadFavicon(for: url, host: host) {
                    saveLogoToDisk(downloaded, key: key)
                    return downloaded
                }
            }
            
            // 3. Fallback: Render a crisp high-DPI Retina badge for intranet tools or offline domains
            let badge = await MainActor.run {
                Self.renderBrandedBadge(for: url)
            }
            return badge
        }
        
        inFlightLogoTasks[key] = task
        let image = await task.value
        inFlightLogoTasks[key] = nil
        
        if let image = image {
            logoMemoryCache.setObject(image, forKey: nsKey)
        }
        return image
    }
    
    private nonisolated static func logoCacheKey(for url: URL) -> String {
        let host = (url.host ?? "web").lowercased()
        if host == "docs.google.com" {
            if url.path.contains("/spreadsheets/") { return "docs.google.com_sheets" }
            if url.path.contains("/presentation/") { return "docs.google.com_slides" }
            if url.path.contains("/document/") { return "docs.google.com_docs" }
        }
        return host.replacingOccurrences(of: "[^a-z0-9._-]", with: "_", options: .regularExpression)
    }
    
    private static func canFetchPublicFavicon(host: String, url: URL) -> Bool {
        guard host.contains(".") else { return false }
        if host == "localhost" ||
           host == "127.0.0.1" ||
           host.hasSuffix(".local") ||
           host.hasSuffix(".internal") ||
           host.contains(".corp.") ||
           host.hasSuffix(".googleplex.com") ||
           host == "goto.google.com" ||
           host == "docs.google.com" ||
           host.hasPrefix("10.") ||
           host.hasPrefix("192.168.") {
            return false
        }
        return true
    }
    
    private func downloadFavicon(for url: URL, host: String) async -> NSImage? {
        // Candidate 1: Google S2 high-res 64px favicon service for public domains
        var candidates: [URL] = []
        if let encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let s2URL = URL(string: "https://www.google.com/s2/favicons?domain=\(encodedHost)&sz=64") {
            candidates.append(s2URL)
        }
        // Candidate 2: Direct origin /apple-touch-icon.png and /favicon.ico
        if let scheme = url.scheme {
            if let touchIcon = URL(string: "\(scheme)://\(host)/apple-touch-icon.png") {
                candidates.append(touchIcon)
            }
            if let directFavicon = URL(string: "\(scheme)://\(host)/favicon.ico") {
                candidates.append(directFavicon)
            }
        }
        
        for candidate in candidates {
            var request = URLRequest(url: candidate)
            request.timeoutInterval = 3.0
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      !data.isEmpty,
                      let image = NSImage(data: data),
                      image.size.width >= 14 else {
                    continue
                }
                return image
            } catch {
                continue
            }
        }
        return nil
    }
    
    private func loadLogoFromDisk(key: String) -> NSImage? {
        guard let dir = faviconDirectory else { return nil }
        let fileURL = dir.appendingPathComponent("\(key).png")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return NSImage(contentsOf: fileURL)
    }
    
    private func saveLogoToDisk(_ image: NSImage, key: String) {
        guard let dir = faviconDirectory,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            return
        }
        let fileURL = dir.appendingPathComponent("\(key).png")
        try? pngData.write(to: fileURL, options: .atomic)
    }
    
    @MainActor
    private static func renderBrandedBadge(for url: URL) -> NSImage {
        let host = (url.host ?? "web").lowercased()
        let path = url.path.lowercased()
        
        struct BadgeStyle {
            let color: NSColor
            let symbolName: String?
            let text: String?
        }
        
        let style: BadgeStyle = {
            if host == "go" || host == "goto" || host == "goto.google.com" {
                return BadgeStyle(color: NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1.0), symbolName: nil, text: "go")
            }
            if host == "g3doc" || host.hasPrefix("g3doc.") {
                return BadgeStyle(color: NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1.0), symbolName: "doc.text.fill", text: nil)
            }
            if host == "cl" || host == "critique" || host.hasPrefix("critique.") {
                return BadgeStyle(color: NSColor(calibratedRed: 0.92, green: 0.26, blue: 0.21, alpha: 1.0), symbolName: nil, text: "CL")
            }
            if host == "b" || host.hasPrefix("b.") || host.hasPrefix("buganizer.") {
                return BadgeStyle(color: NSColor(calibratedRed: 0.20, green: 0.66, blue: 0.33, alpha: 1.0), symbolName: "ladybug.fill", text: nil)
            }
            if host.hasPrefix("cider") {
                return BadgeStyle(color: NSColor(calibratedRed: 0.95, green: 0.60, blue: 0.05, alpha: 1.0), symbolName: "chevron.left.forwardslash.chevron.right", text: nil)
            }
            if host.hasPrefix("source.") {
                return BadgeStyle(color: NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1.0), symbolName: "magnifyingglass", text: nil)
            }
            if host.hasPrefix("moma.") {
                return BadgeStyle(color: NSColor(calibratedRed: 0.85, green: 0.23, blue: 0.38, alpha: 1.0), symbolName: nil, text: "M")
            }
            if host == "plx" || host.hasPrefix("plx.") {
                return BadgeStyle(color: NSColor(calibratedRed: 0.58, green: 0.20, blue: 0.90, alpha: 1.0), symbolName: "chart.bar.fill", text: nil)
            }
            if host == "pg" || host.hasPrefix("perfgate.") {
                return BadgeStyle(color: NSColor(calibratedRed: 0.0, green: 0.67, blue: 0.76, alpha: 1.0), symbolName: "gauge.with.dots.needle.67percent", text: nil)
            }
            if host == "ipdb" || host.hasPrefix("ipdb.") {
                return BadgeStyle(color: NSColor(calibratedRed: 0.12, green: 0.53, blue: 0.90, alpha: 1.0), symbolName: "network", text: nil)
            }
            if host == "docs.google.com" {
                if path.contains("/spreadsheets/") {
                    return BadgeStyle(color: NSColor(calibratedRed: 0.06, green: 0.62, blue: 0.35, alpha: 1.0), symbolName: "tablecells.fill", text: nil)
                }
                if path.contains("/presentation/") {
                    return BadgeStyle(color: NSColor(calibratedRed: 0.96, green: 0.71, blue: 0.0, alpha: 1.0), symbolName: "rectangle.on.rectangle.angled.fill", text: nil)
                }
                return BadgeStyle(color: NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1.0), symbolName: "doc.richtext.fill", text: nil)
            }
            if host.contains("google") {
                return BadgeStyle(color: NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1.0), symbolName: nil, text: "G")
            }
            let cleanHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let initial = String(cleanHost.prefix(1)).uppercased()
            return BadgeStyle(color: NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.52, alpha: 1.0), symbolName: nil, text: initial.isEmpty ? "W" : initial)
        }()
        
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14)
            style.color.setFill()
            path.fill()
            
            if let symbolName = style.symbolName,
               let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
                if let configured = symbol.withSymbolConfiguration(config) {
                    let symSize = configured.size
                    let symRect = NSRect(
                        x: (rect.width - symSize.width) / 2,
                        y: (rect.height - symSize.height) / 2,
                        width: symSize.width,
                        height: symSize.height
                    )
                    let tinted = NSImage(size: symSize, flipped: false) { r in
                        configured.draw(in: r)
                        NSColor.white.set()
                        r.fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: symRect)
                    return true
                }
            }
            
            let label = style.text ?? "W"
            let fontSize: CGFloat = label.count > 1 ? 26 : 34
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let attrStr = NSAttributedString(string: label, attributes: attrs)
            let strSize = attrStr.size()
            let strRect = NSRect(
                x: (rect.width - strSize.width) / 2,
                y: (rect.height - strSize.height) / 2,
                width: strSize.width,
                height: strSize.height
            )
            attrStr.draw(in: strRect)
            return true
        }
        return image
    }
    
    /// Determines if a URL is a public internet webpage suitable for unauthenticated HTTP scraping.
    private func isScrapablePublicWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              host.contains(".") else {
            return false
        }
        
        // Skip loopback, private IPs, and corporate SSO-walled domains
        if host == "localhost" ||
           host == "127.0.0.1" ||
           host == "0.0.0.0" ||
           host == "::1" ||
           host.hasSuffix(".local") ||
           host.hasSuffix(".internal") ||
           host.contains(".corp.") ||
           host.hasSuffix(".googleplex.com") ||
           host == "goto.google.com" ||
           host == "docs.google.com" ||
           host == "drive.google.com" ||
           host == "aistudio.google.com" ||
           host == "gemini.google.com" ||
           host.hasPrefix("10.") ||
           host.hasPrefix("192.168.") ||
           host.hasPrefix("169.254.") {
            return false
        }
        
        return true
    }
    
    private func performFetch(for url: URL) async -> URLMetadataResult? {
        var title: String? = nil
        var description: String? = nil
        
        if isScrapablePublicWebURL(url) {
            // 1. Lightweight HTML <head> fetch for OpenGraph / Meta description & title
            if let html = await fetchHTMLHead(for: url) {
                let parsed = Self.parseHTMLMetadata(html)
                if !Self.isGenericAuthOrErrorTitle(parsed.title) {
                    title = parsed.title
                    description = parsed.description
                }
            }
            
            // 2. Fallback to Apple's LinkPresentation if title is still missing
            if title == nil {
                if let lpTitle = await fetchLinkPresentationTitle(for: url),
                   !Self.isGenericAuthOrErrorTitle(lpTitle) {
                    title = lpTitle
                }
            }
        }
        
        // 3. Fallback / Enrichment using smart URL structure synthesis if title or description is missing
        let fallback = Self.synthesizeSmartMetadata(for: url)
        if title == nil {
            title = fallback?.title
        }
        if description == nil {
            description = fallback?.description
        }
        
        if title == nil && description == nil {
            return nil
        }
        
        return URLMetadataResult(title: title, description: description)
    }
    
    private func fetchHTMLHead(for url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Request first 96KB to capture <head> quickly without downloading huge pages
        request.setValue("bytes=0-98303", forHTTPHeaderField: "Range")
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            // Detect if the request was redirected to a login / SSO / authentication wall
            if let finalURL = httpResponse.url, Self.isAuthRedirect(original: url, final: finalURL) {
                return nil
            }
            
            if let mime = httpResponse.mimeType?.lowercased(),
               !mime.contains("html") && !mime.contains("xml") && !mime.contains("text") {
                return nil
            }
            
            let limitedData = data.prefix(131072) // Hard cap at 128KB
            if let utf8 = String(data: limitedData, encoding: .utf8) {
                return utf8
            } else if let latin1 = String(data: limitedData, encoding: .isoLatin1) {
                return latin1
            }
            return nil
        } catch {
            return nil
        }
    }
    
    @MainActor
    private func fetchLinkPresentationTitle(for url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.shouldFetchSubresources = false
        provider.timeout = 3.5
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            if let rawTitle = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawTitle.isEmpty {
                return String(rawTitle.prefix(240))
            }
        } catch {
            return nil
        }
        return nil
    }
    
    // MARK: - Auth Wall & Noise Detection
    
    private static func isAuthRedirect(original: URL, final: URL) -> Bool {
        let origHost = original.host?.lowercased() ?? ""
        let finalHost = final.host?.lowercased() ?? ""
        let finalPath = final.path.lowercased()
        
        if origHost != finalHost {
            if finalHost.contains("accounts.google.") ||
               finalHost.contains("login.") ||
               finalHost.contains("sso.") ||
               finalHost.contains("auth.") ||
               finalHost.contains("uberproxy") {
                return true
            }
        }
        
        if finalPath.contains("/servicelogin") ||
           finalPath.contains("/signin") ||
           finalPath.contains("/sso/") ||
           finalPath.contains("/oauth") {
            return true
        }
        
        return false
    }
    
    static func isGenericAuthOrErrorTitle(_ title: String?) -> Bool {
        guard let t = title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !t.isEmpty else {
            return true
        }
        let blockedExact: Set<String> = [
            "sign in", "sign-in", "log in", "login", "redirecting...", "redirecting",
            "just a moment...", "attention required!", "access denied", "403 forbidden",
            "404 not found", "page not found", "error", "google search"
        ]
        if blockedExact.contains(t) { return true }
        
        let blockedSubstrings = [
            "single sign on",
            "sign into corp",
            "sign in - google accounts",
            "cloudflare",
            "ddos-guard"
        ]
        for sub in blockedSubstrings where t.contains(sub) {
            return true
        }
        return false
    }
    
    // MARK: - Smart URL Structure Synthesis (Intranet, Docs, & Fallback)
    
    static func synthesizeSmartMetadata(for url: URL) -> URLMetadataResult? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path
        let pathParts = path.split(separator: "/").map(String.init)
        
        // 1. Go links (http://go/slug or goto.google.com/slug)
        if host == "go" || host == "goto" || host == "goto.google.com" {
            let slug = pathParts.joined(separator: "/")
            guard !slug.isEmpty else { return nil }
            let humanized = slug.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
            return URLMetadataResult(
                title: "go/\(slug)",
                description: "Go shortcut link • \(humanized)"
            )
        }
        
        // 2. Shortn links (http://shortn/id)
        if host == "shortn" || host.hasPrefix("shortn.") {
            let id = pathParts.first ?? ""
            return URLMetadataResult(
                title: "Shortn Link\(id.isEmpty ? "" : " (\(id))")",
                description: "Shortened URL redirect • \(url.absoluteString)"
            )
        }
        
        // 3. G3doc documentation
        if host == "g3doc" || host.hasPrefix("g3doc.") {
            let docName = pathParts.last ?? "Documentation"
            let dirPath = pathParts.dropLast().joined(separator: "/")
            return URLMetadataResult(
                title: "G3doc • \(docName)",
                description: dirPath.isEmpty ? "Internal G3doc markdown documentation" : "Documentation in \(dirPath)"
            )
        }
        
        // 4. Critique CLs
        if host == "cl" || host == "critique" || host.hasPrefix("critique.") {
            let clNum = pathParts.last(where: { $0.allSatisfy(\.isNumber) }) ?? pathParts.last ?? ""
            return URLMetadataResult(
                title: clNum.isEmpty ? "Critique Code Review" : "Critique CL #\(clNum)",
                description: clNum.isEmpty ? "Code review changelist on Critique" : "Code review changelist \(clNum) on Critique"
            )
        }
        
        // 5. Buganizer
        if host == "b" || host.hasPrefix("b.") || host.hasPrefix("buganizer.") {
            let bugID = pathParts.last ?? ""
            return URLMetadataResult(
                title: bugID.isEmpty ? "Buganizer Issue" : "Buganizer b/\(bugID)",
                description: "Issue tracker entry \(bugID)"
            )
        }
        
        // 6. Cider Web IDE
        if host == "cider" || host.hasPrefix("cider.") {
            let lastPart = pathParts.last ?? ""
            return URLMetadataResult(
                title: lastPart.isEmpty ? "Cider Web IDE" : "Cider • \(lastPart)",
                description: "Cloud development environment on \(host)"
            )
        }
        
        // 7. Google Code Search (source.corp.google.com)
        if host.hasPrefix("source.") {
            let target = pathParts.last ?? ""
            return URLMetadataResult(
                title: target.isEmpty ? "Google Code Search" : "Code Search • \(target)",
                description: pathParts.isEmpty ? "Source code search" : "Source path: \(pathParts.joined(separator: "/"))"
            )
        }
        
        // 8. Moma Intranet
        if host == "moma" || host.hasPrefix("moma.") {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let q = comps?.queryItems?.first(where: { $0.name == "q" })?.value, !q.isEmpty {
                return URLMetadataResult(
                    title: "Moma Search • \(q)",
                    description: "Internal search results on Moma"
                )
            }
            return URLMetadataResult(title: "Moma Intranet", description: "Internal Moma portal (\(host))")
        }
        
        // 9. Jetski / Eldar
        if host.hasPrefix("jetski.") {
            return URLMetadataResult(title: "Jetski", description: "Jetski web application (\(host))")
        }
        if host.hasPrefix("eldar.") {
            let item = pathParts.last ?? ""
            return URLMetadataResult(
                title: item.isEmpty ? "Eldar" : "Eldar • \(item)",
                description: "Internal compliance/assessment portal on \(host)"
            )
        }
        
        // 10. IPDB
        if host == "ipdb" || host.hasPrefix("ipdb.") {
            if path.contains("/proposal/"), let prop = pathParts.last {
                return URLMetadataResult(
                    title: "IPDB Proposal • \(prop)",
                    description: "IP database allocation/routing proposal (\(prop))"
                )
            }
            if path.contains("/drill-down") {
                let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let idParam = comps?.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
                return URLMetadataResult(
                    title: "IPDB Drill-Down\(idParam.isEmpty ? "" : " • \(idParam)")",
                    description: "IP network prefix drill-down query on IPDB"
                )
            }
            return URLMetadataResult(title: "IPDB (\(host))", description: "IP database resource • \(path)")
        }
        
        // 11. Screenshot
        if host == "screen" || host.hasPrefix("screenshot") {
            let id = pathParts.last ?? ""
            return URLMetadataResult(
                title: "Screenshot\(id.isEmpty ? "" : " • \(id)")",
                description: "Shared screenshot capture (\(url.absoluteString))"
            )
        }
        
        // 12. Perfgate
        if host == "pg" || host.hasPrefix("perfgate.") {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let runKey = comps?.queryItems?.first(where: { $0.name == "run_key" })?.value ?? pathParts.last ?? ""
            return URLMetadataResult(
                title: runKey.isEmpty ? "Perfgate Benchmark" : "Perfgate Run • \(runKey)",
                description: "Performance benchmark analysis on Perfgate"
            )
        }
        
        // 13. PLX
        if host == "plx" || host.hasPrefix("plx.") {
            let resource = pathParts.last ?? "Resource"
            return URLMetadataResult(
                title: "PLX • \(resource)",
                description: "PLX data script/snapshot in /\(pathParts.dropLast().joined(separator: "/"))"
            )
        }
        
        // 14. GPaste / Google Paste
        if host == "gpaste" || host.hasPrefix("gpaste.") || host == "paste.googleplex.com" {
            let pasteID = pathParts.last ?? ""
            return URLMetadataResult(
                title: "GPaste Snippet\(pasteID.isEmpty ? "" : " #\(pasteID)")",
                description: "Shared code/text snippet on GPaste"
            )
        }
        
        // 15. Google Workspace Docs / Sheets / Slides & Google AI tools
        if host == "docs.google.com" {
            if path.contains("/document/") {
                return URLMetadataResult(title: "Google Docs Document", description: "Collaborative document on docs.google.com")
            } else if path.contains("/spreadsheets/") {
                return URLMetadataResult(title: "Google Sheets Spreadsheet", description: "Spreadsheet on docs.google.com")
            } else if path.contains("/presentation/") {
                return URLMetadataResult(title: "Google Slides Presentation", description: "Presentation deck on docs.google.com")
            }
        }
        if host == "aistudio.google.com" {
            return URLMetadataResult(title: "Google AI Studio", description: "Prompt engineering & Gemini API workspace")
        }
        if host == "gemini.google.com" {
            return URLMetadataResult(title: "Google Gemini", description: "Google Gemini AI assistant")
        }
        if (host == "www.google.com" || host == "google.com") && path.hasPrefix("/search") {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let q = comps?.queryItems?.first(where: { $0.name == "q" })?.value, !q.isEmpty {
                return URLMetadataResult(
                    title: "\(q) — Google Search",
                    description: "Google Web Search results for \"\(q)\""
                )
            }
            return URLMetadataResult(title: "Google Search", description: "Search results on google.com")
        }
        
        // 16. Generic structured URL fallback when path or query has readable info
        if !pathParts.isEmpty {
            let readableLast = pathParts.last?
                .removingPercentEncoding?
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ") ?? ""
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let queryItems = comps?.queryItems, !queryItems.isEmpty {
                let querySummary = queryItems
                    .compactMap { item -> String? in
                        guard let val = item.value, !val.isEmpty else { return nil }
                        return "\(item.name)=\(val)"
                    }
                    .prefix(2)
                    .joined(separator: ", ")
                if !querySummary.isEmpty {
                    return URLMetadataResult(
                        title: readableLast.isEmpty ? host : "\(readableLast) — \(host)",
                        description: "Web link on \(host) (\(querySummary))"
                    )
                }
            }
            if !readableLast.isEmpty {
                return URLMetadataResult(
                    title: "\(readableLast) — \(host)",
                    description: "Web page at \(host)/\(pathParts.joined(separator: "/"))"
                )
            }
        }
        
        return URLMetadataResult(title: host, description: nil)
    }
    
    // MARK: - HTML Meta Tag Parser
    
    static func parseHTMLMetadata(_ html: String) -> URLMetadataResult {
        // Extract up to </head> if present to speed up regex scanning
        let headSlice: String
        if let headEndRange = html.range(of: "</head>", options: .caseInsensitive) {
            headSlice = String(html[..<headEndRange.upperBound])
        } else {
            headSlice = String(html.prefix(65536))
        }
        
        let ogTitle = extractMetaContent(from: headSlice, keys: ["og:title", "twitter:title"])
        let htmlTitle = extractTagContent(from: headSlice, tag: "title")
        let siteName = extractMetaContent(from: headSlice, keys: ["og:site_name"])
        
        var finalTitle = ogTitle ?? htmlTitle
        if let site = siteName, let t = finalTitle, !t.lowercased().contains(site.lowercased()) {
            finalTitle = "\(t) — \(site)"
        }
        
        let rawDesc = extractMetaContent(
            from: headSlice,
            keys: ["og:description", "description", "twitter:description"]
        )
        
        let cleanTitle = finalTitle.map { cleanHTMLText($0, maxLength: 220) }
        let cleanDesc = rawDesc.map { cleanHTMLText($0, maxLength: 420) }
        
        return URLMetadataResult(
            title: (cleanTitle?.isEmpty == false) ? cleanTitle : nil,
            description: (cleanDesc?.isEmpty == false) ? cleanDesc : nil
        )
    }
    
    private static func extractMetaContent(from html: String, keys: [String]) -> String? {
        // Match <meta ...> tags
        let metaPattern = "<meta\\s+[^>]*>"
        guard let metaRegex = try? NSRegularExpression(pattern: metaPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        
        let nsHTML = html as NSString
        let matches = metaRegex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))
        
        for key in keys {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let attrKeyPattern = "(?:property|name|itemprop)\\s*=\\s*[\"']\(escapedKey)[\"']"
            guard let keyRegex = try? NSRegularExpression(pattern: attrKeyPattern, options: [.caseInsensitive]) else {
                continue
            }
            
            for match in matches {
                let tagString = nsHTML.substring(with: match.range)
                let tagRange = NSRange(location: 0, length: (tagString as NSString).length)
                if keyRegex.firstMatch(in: tagString, options: [], range: tagRange) != nil {
                    if let content = extractAttribute("content", from: tagString),
                       !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return content
                    }
                }
            }
        }
        return nil
    }
    
    private static func extractAttribute(_ attribute: String, from tag: String) -> String? {
        // Match content="value" or content='value'
        let doubleQuotePattern = "\(attribute)\\s*=\\s*\"([^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: doubleQuotePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: tag, options: [], range: NSRange(location: 0, length: (tag as NSString).length)),
           match.numberOfRanges > 1 {
            return (tag as NSString).substring(with: match.range(at: 1))
        }
        
        let singleQuotePattern = "\(attribute)\\s*=\\s*'([^']*)'"
        if let regex = try? NSRegularExpression(pattern: singleQuotePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: tag, options: [], range: NSRange(location: 0, length: (tag as NSString).length)),
           match.numberOfRanges > 1 {
            return (tag as NSString).substring(with: match.range(at: 1))
        }
        
        return nil
    }
    
    private static func extractTagContent(from html: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: (html as NSString).length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return (html as NSString).substring(with: match.range(at: 1))
    }
    
    static func cleanHTMLText(_ raw: String, maxLength: Int) -> String {
        var text = raw
        
        // Strip any stray HTML tags inside title/description
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            text = tagRegex.stringByReplacingMatches(
                in: text,
                options: [],
                range: NSRange(location: 0, length: (text as NSString).length),
                withTemplate: ""
            )
        }
        
        // Decode common HTML entities
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&#39;", "'"),
            ("&#x27;", "'"),
            ("&apos;", "'"),
            ("&rsquo;", "’"),
            ("&lsquo;", "‘"),
            ("&rdquo;", "”"),
            ("&ldquo;", "“"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " "),
            ("&#160;", " "),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
            ("&bull;", "•"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™")
        ]
        
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        
        // Decode numeric decimal entities like &#8211;
        if let decRegex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
            let nsString = text as NSString
            let matches = decRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)).reversed()
            for match in matches {
                let codeStr = nsString.substring(with: match.range(at: 1))
                if let code = UInt32(codeStr), let scalar = UnicodeScalar(code) {
                    text = (text as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
                }
            }
        }
        
        // Decode numeric hex entities like &#x2019;
        if let hexRegex = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);", options: []) {
            let nsString = text as NSString
            let matches = hexRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)).reversed()
            for match in matches {
                let codeStr = nsString.substring(with: match.range(at: 1))
                if let code = UInt32(codeStr, radix: 16), let scalar = UnicodeScalar(code) {
                    text = (text as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
                }
            }
        }
        
        // Collapse consecutive whitespace and newlines into single spaces
        let components = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let collapsed = components.joined(separator: " ")
        
        if collapsed.count > maxLength {
            return String(collapsed.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return collapsed
    }
}
