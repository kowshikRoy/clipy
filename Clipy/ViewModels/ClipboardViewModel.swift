//
//  ClipboardViewModel.swift
//  Clipy
//
//  Created by repon kumar roy on 15.11.2025.
//

import SwiftUI
import Combine

@MainActor
class ClipboardViewModel: ObservableObject {
    @Published var history: [ClipboardItem] = [] {
        didSet {
            saveHistory()
            // Trigger filtering when history changes
            applyFilter() 
        }
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
    
    var selectedItem: ClipboardItem? {
        history.first { $0.id == selectedItemID }
    }
    
    private let historyRepository = HistoryRepository()
    private let pasteboardService: PasteboardService
    private var cancellables = Set<AnyCancellable>()
    
    init(settings: AppSettings) {
        self.pasteboardService = PasteboardService(settings: settings)
        
        // Initial Load
        Task {
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
    }
    
    private func applyFilter() {
        let currentHistory = history
        let query = searchText
        
        if query.isEmpty {
            self.filteredHistory = currentHistory
            self.ensureSelection()
            return
        }
        
        Task.detached(priority: .userInitiated) {
            let filtered = currentHistory.filter { $0.matches(query) }
            
            await MainActor.run {
                self.filteredHistory = filtered
                self.ensureSelection()
            }
        }
    }
    
    func startMonitoring() {
        pasteboardService.startMonitoring()
    }
    
    func addOrUpdateItem(_ newItem: ClipboardItem) {
        // Check for existing item to increment count
        var existingCount = 1
        if let existing = history.first(where: { $0.data == newItem.data }) {
            existingCount = existing.copyCount + 1
        }
        
        // Remove existing duplicate logic
        history.removeAll { $0.data == newItem.data }
        
        var finalItem = newItem
        finalItem.copyCount = existingCount
        // Resetting ID is debatable, but we probably want a new ID to jump to top? 
        // Or keep ID? If we keep ID, we should update timestamps.
        // For now, let's treat it as a new "event" at the top, so new ID is fine or reuse ID if we want stable identity.
        // The original code made a new UUID.
        
        history.insert(finalItem, at: 0)
    }
    
    func copyToPasteboard(item: ClipboardItem) {
        pasteboardService.copyToPasteboard(item: item)
    }
    
    func togglePin(for itemID: UUID) {
        guard let index = history.firstIndex(where: { $0.id == itemID }) else { return }
        history[index].isPinned.toggle()
    }
    
    func deleteItem(id: UUID) {
        if let item = history.first(where: { $0.id == id }) {
            if case .image(let filename) = item.data {
                Task { await historyRepository.deleteImage(filename) }
            }
        }
        
        history.removeAll { $0.id == id }
        if selectedItemID == id {
            selectedItemID = nil
            ensureSelection()
        }
    }
    
    func deleteAll() {
        for item in history {
            if case .image(let filename) = item.data {
                Task { await historyRepository.deleteImage(filename) }
            }
        }
        history.removeAll()
        selectedItemID = nil
    }
    
    func updateItem(id: UUID, newText: String) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        var item = history[index]
        if case .text(_, let sourceURL) = item.data {
             item = ClipboardItem(
                id: item.id,
                data: .text(newText, sourceURL: sourceURL),
                createdAt: item.createdAt,
                sourceApp: item.sourceApp,
                isPinned: item.isPinned,
                copyCount: item.copyCount,
                customMetadata: item.customMetadata
            )
            history[index] = item
        }
    }
    
    func updateItemMetadata(id: UUID, metadata: String?) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        var item = history[index]
        item.customMetadata = metadata
        history[index] = item
    }
    
    // MARK: - Presentation Logic
    
    @Published var pinnedItems: [ClipboardItem] = []
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
                        proxy.scrollTo(newItem.id, anchor: nil)
                    }
                }
            }
        }
    }

    private func saveHistory() {
        let items = history
        Task {
            await historyRepository.save(items)
        }
    }
    
    func resetToDefault() {
        searchText = ""
        ensureSelection()
    }
    
    func ensureSelection() {
        if let selectedItemID, filteredHistory.contains(where: { $0.id == selectedItemID }) {
            return
        }

        if let firstItem = filteredHistory.first {
            selectedItemID = firstItem.id
        } else {
            selectedItemID = nil
        }
    }
}
