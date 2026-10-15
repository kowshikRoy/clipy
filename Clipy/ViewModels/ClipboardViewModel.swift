//
//  ClipboardViewModel.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI
import Combine
import AppKit

@MainActor
class ClipboardViewModel: ObservableObject {
    private var isApplyingEnrichment = false
    
    var history: [ClipboardItem] = [] {
        didSet {
            saveHistory()
            if !isApplyingEnrichment {
                // Trigger filtering when history changes
                applyFilter()
            }
        }
    }
    
    enum FilterType: String, CaseIterable, Identifiable {
        case all = "All"
        case text = "Text"
        case links = "Links"
        case image = "Image"
        
        var id: String { rawValue }
    }
    
    @Published var filterType: FilterType = .all {
        didSet { applyFilter() }
    }
    
    @Published var searchText: String = ""
    var filteredHistory: [ClipboardItem] = [] {
        didSet {
            if !isApplyingEnrichment {
                recalculateDerivedData()
            }
        }
    }
    @Published var selectedItemID: ClipboardItem.ID? {
        didSet {
            scheduleSelectionEnrichment()
        }
    }
    @Published var isEditing: Bool = false
    @Published var editingText: String = ""
    private(set) var enrichingItemIDs: Set<UUID> = []
    
    // Event specific to new items being added
    let newItemAdded = PassthroughSubject<Void, Never>()
    
    // Fast O(1) lookup caches updated alongside derived data
    private var itemByID: [UUID: ClipboardItem] = [:]
    private var visualIndexByID: [UUID: Int] = [:]
    private var pinnedIDSet: Set<UUID> = []
    
    var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        if let fast = itemByID[selectedItemID] {
            return fast
        }
        return filteredHistory.first { $0.id == selectedItemID } ?? history.first { $0.id == selectedItemID }
    }
    
    private let historyRepository = HistoryRepository()
    private let pasteboardService: PasteboardService
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    private var selectionEnrichmentTask: Task<Void, Never>?
    private var attemptedEnrichmentIDs = Set<UUID>()
    
    init(settings: AppSettings) {
        self.settings = settings
        self.pasteboardService = PasteboardService(settings: settings)
        
        // Initial Load
        Task {
            if settings.retentionDays > 0 {
                await historyRepository.executeDeletionPolicy(
                    retentionDays: settings.retentionDays,
                    cleanNoise: settings.autoCleanupNoise,
                    cleanLargeTransient: settings.autoCleanupLargeTransient
                )
            }
            let items = await historyRepository.load()
            self.history = items
            self.enrichRecentItemsInBackground(items: items)
        }
        
        // Bind PasteboardService
        pasteboardService.$newItem
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] newItem in
                self?.addOrUpdateItem(newItem)
            }
            .store(in: &cancellables)
            
        // Setup Search Subscription
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyFilter()
            }
            .store(in: &cancellables)
            
        // Auto-select first item when app becomes active
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .filter { notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return false }
                return app.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.ensureSelection()
            }
            .store(in: &cancellables)
    }
    
    private func scheduleSelectionEnrichment() {
        selectionEnrichmentTask?.cancel()
        guard let targetID = selectedItemID else { return }
        selectionEnrichmentTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self = self, self.selectedItemID == targetID else { return }
            if let item = self.selectedItem {
                self.enrichItemIfNeeded(item)
            }
        }
    }
    
    private func applyFilter() {
        searchTask?.cancel()
        let query = searchText
        let currentFilter = filterType
        
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            
            var filtered: [ClipboardItem]
            if query.isEmpty {
                filtered = self.history
            } else {
                // Perform SQL FTS Search
                filtered = await self.historyRepository.search(query: query)
            }
            
            if Task.isCancelled { return }
            
            // Apply Type Filter
            if currentFilter != .all {
                filtered = filtered.filter { item in
                    switch currentFilter {
                    case .all:
                        return true
                    case .text:
                        switch item.data {
                        case .text, .color: return true
                        case .image: return false
                        }
                    case .links:
                        return item.isDirectURL
                    case .image:
                        if case .image = item.data { return true }
                        return false
                    }
                }
            }
            
            if Task.isCancelled { return }
            
            self.filteredHistory = filtered
            self.ensureSelection()
        }
    }
    
    func startMonitoring() {
        pasteboardService.startMonitoring()
    }
    
    func addOrUpdateItem(_ newItem: ClipboardItem) {
        Task {
            // 1. Find existing duplicates in DB
            let dbDuplicates = await historyRepository.findDuplicates(of: newItem)
            
            await MainActor.run {
                // 2. Combine with memory duplicates
                let memDuplicates = history.filter { $0.id != newItem.id && $0.data.normalizationKey == newItem.data.normalizationKey }
                var allDuplicates: [ClipboardItem] = []
                var seenIDs = Set<UUID>()
                for dup in (memDuplicates + dbDuplicates) {
                    if !seenIDs.contains(dup.id) {
                        seenIDs.insert(dup.id)
                        allDuplicates.append(dup)
                    }
                }
                
                // 3. Merge metadata from all earlier duplicate entries into the new item
                var finalItem = newItem
                var totalCopyCount = finalItem.copyCount
                
                for older in allDuplicates {
                    if finalItem.customMetadata == nil, let oldMeta = older.customMetadata {
                        finalItem.customMetadata = oldMeta
                    }
                    if finalItem.urlTitle == nil, let oldTitle = older.urlTitle {
                        finalItem.urlTitle = oldTitle
                    }
                    if finalItem.urlDescription == nil, let oldDesc = older.urlDescription {
                        finalItem.urlDescription = oldDesc
                    }
                    if finalItem.ocrText == nil, let oldOCR = older.ocrText {
                        finalItem.ocrText = oldOCR
                    }
                    if older.isPinned {
                        finalItem.isPinned = true
                    }
                    if finalItem.sourceApp == nil, let oldApp = older.sourceApp {
                        finalItem.sourceApp = oldApp
                    }
                    if case .text(let text, let newURL) = finalItem.data,
                       newURL == nil,
                       case .text(_, let oldURL) = older.data,
                       oldURL != nil {
                        finalItem = ClipboardItem(
                            id: finalItem.id,
                            data: .text(text, sourceURL: oldURL),
                            createdAt: finalItem.createdAt,
                            sourceApp: finalItem.sourceApp,
                            isPinned: finalItem.isPinned,
                            copyCount: finalItem.copyCount,
                            customMetadata: finalItem.customMetadata,
                            urlTitle: finalItem.urlTitle,
                            urlDescription: finalItem.urlDescription,
                            ocrText: finalItem.ocrText
                        )
                    }
                    totalCopyCount += older.copyCount
                }
                
                finalItem.copyCount = totalCopyCount
                
                // 4. Remove older duplicate entries from history array and database
                for older in allDuplicates {
                    let oldID = older.id
                    history.removeAll { $0.id == oldID }
                    Task {
                        await historyRepository.delete(id: oldID)
                    }
                }
                
                history.removeAll { $0.data.normalizationKey == newItem.data.normalizationKey }
                
                // 5. Insert merged item at top of history
                history.insert(finalItem, at: 0)
                selectedItemID = finalItem.id
                newItemAdded.send()
                
                // 6. Persist merged item to DB & trigger background enrichment if needed
                let itemToPersist = finalItem
                Task {
                    await historyRepository.insert(itemToPersist)
                    await MainActor.run {
                        self.enrichItemIfNeeded(itemToPersist)
                    }
                }
            }
        }
    }
    
    // MARK: - Background URL & OCR Enrichment
    
    private func enrichRecentItemsInBackground(items: [ClipboardItem]) {
        Task {
            var enrichedCount = 0
            for item in items {
                guard enrichedCount < 50 else { break }
                let needsURL = item.detectedURL != nil && item.urlTitle == nil && item.urlDescription == nil && settings.fetchURLMetadata
                var needsOCR = false
                if case .image = item.data, item.ocrText == nil {
                    needsOCR = true
                }
                if needsURL || needsOCR {
                    enrichedCount += 1
                    enrichItemIfNeeded(item)
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
        }
    }
    
    func enrichItemIfNeeded(_ item: ClipboardItem) {
        guard !attemptedEnrichmentIDs.contains(item.id) else { return }
        
        let targetURL = item.detectedURL
        let needsURL: Bool = {
            guard let url = targetURL,
                  settings.fetchURLMetadata,
                  item.urlTitle == nil && item.urlDescription == nil else {
                return false
            }
            return !settings.isBlocked(app: item.sourceApp, host: url.host)
        }()
        
        let imageFilename: String? = {
            if case .image(let filename) = item.data, item.ocrText == nil {
                return filename
            }
            return nil
        }()
        
        guard needsURL || imageFilename != nil else { return }
        
        attemptedEnrichmentIDs.insert(item.id)
        let itemID = item.id
        if selectedItemID == itemID {
            objectWillChange.send()
        }
        enrichingItemIDs.insert(itemID)
        
        Task {
            var fetchedTitle: String? = nil
            var fetchedDescription: String? = nil
            var recognizedOCR: String? = nil
            
            if needsURL, let url = targetURL {
                if let metadata = await URLMetadataService.shared.fetchMetadata(for: url) {
                    fetchedTitle = metadata.title
                    fetchedDescription = metadata.description
                }
            }
            
            if let filename = imageFilename {
                if let ocr = await OCRService.shared.recognizeText(in: filename) {
                    recognizedOCR = ocr
                }
            }
            
            await MainActor.run {
                self.enrichingItemIDs.remove(itemID)
                
                guard fetchedTitle != nil || fetchedDescription != nil || recognizedOCR != nil else {
                    if self.selectedItemID == itemID {
                        self.objectWillChange.send()
                    }
                    return
                }
                
                self.isApplyingEnrichment = true
                if let idx = self.history.firstIndex(where: { $0.id == itemID }) {
                    var updated = self.history[idx]
                    if let fetchedTitle { updated.urlTitle = fetchedTitle }
                    if let fetchedDescription { updated.urlDescription = fetchedDescription }
                    if let recognizedOCR { updated.ocrText = recognizedOCR }
                    self.history[idx] = updated
                    self.itemByID[itemID] = updated
                }
                if let fIdx = self.filteredHistory.firstIndex(where: { $0.id == itemID }) {
                    var updated = self.filteredHistory[fIdx]
                    if let fetchedTitle { updated.urlTitle = fetchedTitle }
                    if let fetchedDescription { updated.urlDescription = fetchedDescription }
                    if let recognizedOCR { updated.ocrText = recognizedOCR }
                    self.filteredHistory[fIdx] = updated
                    self.itemByID[itemID] = updated
                }
                self.isApplyingEnrichment = false
                
                if self.selectedItemID == itemID {
                    self.objectWillChange.send()
                }
                
                Task {
                    await self.historyRepository.updateEnrichment(
                        id: itemID,
                        urlTitle: fetchedTitle,
                        urlDescription: fetchedDescription,
                        ocrText: recognizedOCR
                    )
                }
            }
        }
    }
    
    func openURL(for item: ClipboardItem) {
        guard let url = item.detectedURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    func copyPlainText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    func copyToPasteboard(item: ClipboardItem) {
        pasteboardService.copyToPasteboard(item: item)
    }
    
    func paste() {
        pasteboardService.paste()
    }
    
    func togglePin(for itemID: UUID) {
        var updatedItem: ClipboardItem?
        if let index = history.firstIndex(where: { $0.id == itemID }) {
            history[index].isPinned.toggle()
            updatedItem = history[index]
        }
        if let index = filteredHistory.firstIndex(where: { $0.id == itemID }) {
            if history.firstIndex(where: { $0.id == itemID }) == nil {
                filteredHistory[index].isPinned.toggle()
                updatedItem = filteredHistory[index]
            } else if let updatedItem {
                filteredHistory[index] = updatedItem
            }
            recalculateDerivedData()
        }
        if let updatedItem {
            Task { await historyRepository.insert(updatedItem) }
        }
    }
    
    func deleteItem(id: UUID) {
        let itemToDelete = itemByID[id] ?? filteredHistory.first(where: { $0.id == id }) ?? history.first(where: { $0.id == id })
        if let item = itemToDelete {
            if case .image(let filename) = item.data {
                Task { await historyRepository.deleteImage(filename) }
            }
            Task { await historyRepository.delete(id: id) }
        }
        
        history.removeAll { $0.id == id }
        filteredHistory.removeAll { $0.id == id }
        if selectedItemID == id {
            selectedItemID = nil
            ensureSelection()
        }
    }
    
    func deleteAll() {
        var allItems = history
        for item in filteredHistory where !allItems.contains(where: { $0.id == item.id }) {
            allItems.append(item)
        }
        for item in allItems {
            if case .image(let filename) = item.data {
                Task { await historyRepository.deleteImage(filename) }
            }
        }
        Task { await historyRepository.deleteAll() }
        history.removeAll()
        filteredHistory.removeAll()
        selectedItemID = nil
    }
    
    func updateItem(id: UUID, newText: String) {
        let trimmedNewText = newText.trimmingLineWhitespaces()
        guard !trimmedNewText.isEmpty else { return }
        var updatedItem: ClipboardItem?
        if let index = history.firstIndex(where: { $0.id == id }) {
            var item = history[index]
            if case .text(_, let sourceURL) = item.data {
                let textChanged = item.textRepresentation != trimmedNewText
                item = ClipboardItem(
                    id: item.id,
                    data: .text(trimmedNewText, sourceURL: sourceURL),
                    createdAt: item.createdAt,
                    sourceApp: item.sourceApp,
                    isPinned: item.isPinned,
                    copyCount: item.copyCount,
                    customMetadata: item.customMetadata,
                    urlTitle: textChanged ? nil : item.urlTitle,
                    urlDescription: textChanged ? nil : item.urlDescription,
                    ocrText: item.ocrText
                )
                history[index] = item
                updatedItem = item
            }
        }
        if let index = filteredHistory.firstIndex(where: { $0.id == id }) {
            var item = filteredHistory[index]
            if case .text(_, let sourceURL) = item.data {
                let textChanged = item.textRepresentation != trimmedNewText
                item = ClipboardItem(
                    id: item.id,
                    data: .text(trimmedNewText, sourceURL: sourceURL),
                    createdAt: item.createdAt,
                    sourceApp: item.sourceApp,
                    isPinned: item.isPinned,
                    copyCount: item.copyCount,
                    customMetadata: item.customMetadata,
                    urlTitle: textChanged ? nil : item.urlTitle,
                    urlDescription: textChanged ? nil : item.urlDescription,
                    ocrText: item.ocrText
                )
                filteredHistory[index] = item
                updatedItem = item
            }
        }
        if let updatedItem {
            attemptedEnrichmentIDs.remove(updatedItem.id)
            Task {
                await historyRepository.insert(updatedItem)
                await MainActor.run {
                    self.enrichItemIfNeeded(updatedItem)
                }
            }
        }
    }
    
    func updateItemMetadata(id: UUID, metadata: String?) {
        var updatedItem: ClipboardItem?
        if let index = history.firstIndex(where: { $0.id == id }) {
            var item = history[index]
            item.customMetadata = metadata
            history[index] = item
            updatedItem = item
        }
        if let index = filteredHistory.firstIndex(where: { $0.id == id }) {
            var item = filteredHistory[index]
            item.customMetadata = metadata
            filteredHistory[index] = item
            updatedItem = item
        }
        if let updatedItem {
            Task { await historyRepository.insert(updatedItem) }
        }
        if !searchText.isEmpty {
            applyFilter()
        }
    }
    
    // MARK: - Presentation Logic
    
    struct CategorySection: Identifiable, Equatable {
        let category: DateCategory
        let items: [ClipboardItem]
        var id: DateCategory { category }
    }
    
    @Published var pinnedItems: [ClipboardItem] = []
    @Published var unpinnedHistory: [ClipboardItem] = []
    @Published var categorizedHistory: [CategorySection] = []
    
    // Combined history in visual order for navigation
    var visualHistory: [ClipboardItem] = []
    
    private func recalculateDerivedData() {
        let currentFiltered = filteredHistory
        
        var pItems: [ClipboardItem] = []
        var recentItems: [ClipboardItem] = []
        pItems.reserveCapacity(16)
        recentItems.reserveCapacity(currentFiltered.count)
        
        var newPinSet = Set<UUID>()
        var newItemMap = [UUID: ClipboardItem](minimumCapacity: currentFiltered.count)
        
        for item in currentFiltered {
            newItemMap[item.id] = item
            if item.isPinned {
                pItems.append(item)
                newPinSet.insert(item.id)
            } else {
                recentItems.append(item)
            }
        }
        
        let combined = pItems + recentItems
        var newIndexMap = [UUID: Int](minimumCapacity: combined.count)
        for (idx, item) in combined.enumerated() {
            newIndexMap[item.id] = idx
        }
        
        self.itemByID = newItemMap
        self.pinnedIDSet = newPinSet
        self.visualIndexByID = newIndexMap
        self.pinnedItems = pItems
        self.unpinnedHistory = recentItems
        self.visualHistory = combined
        
        let calendar = Calendar.current
        let now = Date()
        
        var today: [ClipboardItem] = []
        var yesterday: [ClipboardItem] = []
        var thisWeek: [ClipboardItem] = []
        var thisMonth: [ClipboardItem] = []
        var rest: [ClipboardItem] = []
        
        for item in recentItems {
            if calendar.isDateInToday(item.createdAt) {
                today.append(item)
            } else if calendar.isDateInYesterday(item.createdAt) {
                yesterday.append(item)
            } else if calendar.isDate(item.createdAt, equalTo: now, toGranularity: .weekOfYear) {
                thisWeek.append(item)
            } else if calendar.isDate(item.createdAt, equalTo: now, toGranularity: .month) {
                thisMonth.append(item)
            } else {
                rest.append(item)
            }
        }
        
        var result: [CategorySection] = []
        if !today.isEmpty { result.append(CategorySection(category: .today, items: today)) }
        if !yesterday.isEmpty { result.append(CategorySection(category: .yesterday, items: yesterday)) }
        if !thisWeek.isEmpty { result.append(CategorySection(category: .thisWeek, items: thisWeek)) }
        if !thisMonth.isEmpty { result.append(CategorySection(category: .thisMonth, items: thisMonth)) }
        if !rest.isEmpty { result.append(CategorySection(category: .rest, items: rest)) }
        
        self.categorizedHistory = result
    }
    
    enum DateCategory: String {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case rest = "Rest"
        
        var title: String { rawValue }
        
        var icon: String {
            switch self {
            case .today: return "sun.max"
            case .yesterday: return "clock.arrow.circlepath"
            case .thisWeek: return "calendar"
            case .thisMonth: return "calendar.circle"
            case .rest: return "archivebox"
            }
        }
    }
    
    func moveSelection(offset: Int, proxy: ScrollViewProxy? = nil) {
        let history = visualHistory
        guard !history.isEmpty else { return }
        
        let currentIndex: Int
        if let selectedItemID, let fastIndex = visualIndexByID[selectedItemID] {
            currentIndex = fastIndex
        } else {
            currentIndex = history.firstIndex { $0.id == selectedItemID } ?? -1
        }
        
        // Prevent jitter at bounds
        if currentIndex == 0 && offset < 0 { return }
        if currentIndex == history.count - 1 && offset > 0 { return }
        
        var newIndex = currentIndex + offset
        
        // Clamp selection
        newIndex = max(0, min(newIndex, history.count - 1))
        
        let newItem = history[newIndex]
        if selectedItemID != newItem.id {
            selectedItemID = newItem.id
            if isEditing {
                isEditing = false
            }
            
            if let proxy = proxy, !pinnedIDSet.contains(newItem.id) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if !searchText.isEmpty {
                        proxy.scrollTo(newItem.id, anchor: nil)
                    } else if unpinnedHistory.first?.id == newItem.id {
                        proxy.scrollTo("top-anchor", anchor: .top)
                    } else {
                        proxy.scrollTo(newItem.id, anchor: nil)
                    }
                }
            }
        }
    }

    private func saveHistory() {
        // No-op: Items are saved individually via addOrUpdateItem -> insert
    }
    
    func resetToDefault() {
        let needsReset = !searchText.isEmpty || filterType != .all || filteredHistory.count != history.count
        if !searchText.isEmpty {
            searchText = ""
        }
        if filterType != .all {
            filterType = .all
        }
        if needsReset {
            filteredHistory = history
        }
        
        // Sticky selection: Keep current selection if valid
        if let selectedItemID, itemByID[selectedItemID] != nil {
            return
        }
        
        if let first = visualHistory.first ?? history.first {
            selectedItemID = first.id
        } else {
            selectedItemID = nil
        }
    }
    
    func ensureSelection() {
        if let selectedItemID, itemByID[selectedItemID] != nil {
            return
        }

        if let firstItem = visualHistory.first ?? filteredHistory.first {
            selectedItemID = firstItem.id
        } else {
            selectedItemID = nil
        }
    }
}
