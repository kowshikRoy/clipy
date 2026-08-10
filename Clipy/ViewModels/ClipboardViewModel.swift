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
    @Published var history: [ClipboardItem] = [] {
        didSet {
            saveHistory()
            // Trigger filtering when history changes
            applyFilter() 
        }
    }
    
    enum FilterType: String, CaseIterable, Identifiable {
        case all = "All"
        case text = "Text"
        case image = "Image"
        
        var id: String { rawValue }
    }
    
    @Published var filterType: FilterType = .all {
        didSet { applyFilter() }
    }
    
    @Published var searchText: String = ""
    @Published var filteredHistory: [ClipboardItem] = [] {
        didSet {
            recalculateDerivedData()
        }
    }
    @Published var selectedItemID: ClipboardItem.ID?
    @Published var isEditing: Bool = false
    @Published var editingText: String = ""
    
    // Event specific to new items being added
    let newItemAdded = PassthroughSubject<Void, Never>()
    
    var selectedItem: ClipboardItem? {
        guard let selectedItemID else { return nil }
        return filteredHistory.first { $0.id == selectedItemID } ?? history.first { $0.id == selectedItemID }
    }
    
    private let historyRepository = HistoryRepository()
    private let pasteboardService: PasteboardService
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    
    init(settings: AppSettings) {
        self.pasteboardService = PasteboardService(settings: settings)
        
        // Initial Load, Deduplication, and Deletion Policy
        Task {
            await historyRepository.deduplicate()
            await historyRepository.executeDeletionPolicy(
                retentionDays: settings.retentionDays,
                cleanNoise: settings.autoCleanupNoise,
                cleanLargeTransient: settings.autoCleanupLargeTransient
            )
            let items = await historyRepository.load()
            self.history = items
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
                    switch item.data {
                    case .text, .color:
                        return currentFilter == .text
                    case .image:
                        return currentFilter == .image
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
                            customMetadata: finalItem.customMetadata
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
                
                // 6. Persist merged item to DB
                Task {
                    await historyRepository.insert(finalItem)
                }
            }
        }
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
        let itemToDelete = filteredHistory.first(where: { $0.id == id }) ?? history.first(where: { $0.id == id })
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
                item = ClipboardItem(
                    id: item.id,
                    data: .text(trimmedNewText, sourceURL: sourceURL),
                    createdAt: item.createdAt,
                    sourceApp: item.sourceApp,
                    isPinned: item.isPinned,
                    copyCount: item.copyCount,
                    customMetadata: item.customMetadata
                )
                history[index] = item
                updatedItem = item
            }
        }
        if let index = filteredHistory.firstIndex(where: { $0.id == id }) {
            var item = filteredHistory[index]
            if case .text(_, let sourceURL) = item.data {
                item = ClipboardItem(
                    id: item.id,
                    data: .text(trimmedNewText, sourceURL: sourceURL),
                    createdAt: item.createdAt,
                    sourceApp: item.sourceApp,
                    isPinned: item.isPinned,
                    copyCount: item.copyCount,
                    customMetadata: item.customMetadata
                )
                filteredHistory[index] = item
                updatedItem = item
            }
            recalculateDerivedData()
        }
        if let updatedItem {
            Task { await historyRepository.insert(updatedItem) }
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
            recalculateDerivedData()
        }
        if let updatedItem {
            Task { await historyRepository.insert(updatedItem) }
        }
        if !searchText.isEmpty {
            applyFilter()
        }
    }
    
    // MARK: - Presentation Logic
    
    @Published var pinnedItems: [ClipboardItem] = []
    @Published var unpinnedHistory: [ClipboardItem] = []
    @Published var categorizedHistory: [(DateCategory, [ClipboardItem])] = []
    
    // Combined history in visual order for navigation
    // Note: We don't necessarily need this to be Published if it's just for internal logic, but for safety lets keep it. 
    // Actually moveSelection uses it, so it can be a simple property that is updated.
    var visualHistory: [ClipboardItem] = []
    
    private func recalculateDerivedData() {
        let currentFiltered = filteredHistory
        
        let pItems = currentFiltered.filter { $0.isPinned }
        let recentItems = currentFiltered.filter { !$0.isPinned }
        
        self.pinnedItems = pItems
        self.unpinnedHistory = recentItems
        self.visualHistory = pItems + recentItems
        
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
        
        var result: [(DateCategory, [ClipboardItem])] = []
        if !today.isEmpty { result.append((.today, today)) }
        if !yesterday.isEmpty { result.append((.yesterday, yesterday)) }
        if !thisWeek.isEmpty { result.append((.thisWeek, thisWeek)) }
        if !thisMonth.isEmpty { result.append((.thisMonth, thisMonth)) }
        if !rest.isEmpty { result.append((.rest, rest)) }
        
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
        
        let currentIndex = history.firstIndex { $0.id == selectedItemID } ?? -1
        
        // Prevent jitter at bounds
        if currentIndex == 0 && offset < 0 { return }
        if currentIndex == history.count - 1 && offset > 0 { return }
        
        var newIndex = currentIndex + offset
        
        // Clamp selection
        newIndex = max(0, min(newIndex, history.count - 1))
        
        let newItem = history[newIndex]
        if selectedItemID != newItem.id {
            selectedItemID = newItem.id
            isEditing = false
            
            if let proxy = proxy {
                // Allow scrolling for any item that is not pinned
                if !pinnedItems.contains(where: { $0.id == newItem.id }) {
                    withAnimation {
                        // If searching, always scroll to item (no named sections)
                        if !searchText.isEmpty {
                            proxy.scrollTo(newItem.id, anchor: nil)
                        } else {
                            // Check if this item is the FIRST in a category
                            if let category = categorizedHistory.first(where: { $0.1.first?.id == newItem.id }) {
                                // Scroll to HEADER
                                proxy.scrollTo(category.0.title, anchor: .top)
                            } else {
                                proxy.scrollTo(newItem.id, anchor: nil)
                            }
                        }
                    }
                }
            }
        }
    }

    private func saveHistory() {
        // No-op: Items are now saved individually via addOrUpdateItem -> insert
        // or we need to expose an update method.
        // For simplicity, we can rely on addOrUpdateItem doing the insert.
        // But removing items needs to be handled.
    }
    
    func resetToDefault() {
        searchText = ""
        filteredHistory = history
        
        // Sticky selection: Keep current selection if valid
        if let selectedItemID, history.contains(where: { $0.id == selectedItemID }) {
            return
        }
        
        if let first = visualHistory.first ?? history.first {
            selectedItemID = first.id
        } else {
            selectedItemID = nil
        }
    }
    
    func ensureSelection() {
        if let selectedItemID, filteredHistory.contains(where: { $0.id == selectedItemID }) {
            return
        }

        if let firstItem = visualHistory.first ?? filteredHistory.first {
            selectedItemID = firstItem.id
        } else {
            selectedItemID = nil
        }
    }
}
