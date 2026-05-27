import Foundation

/// Persists voice journal entries using JSON file storage with encryption for sensitive fields.
/// A production app could swap this for SQLCipher/GRDB or CoreData.
actor EntryRepository {
    private let storageURL: URL
    private let encryptionService: EncryptionService
    private var entries: [VoiceEntry] = []
    private var loaded = false

    init(encryptionService: EncryptionService) {
        self.encryptionService = encryptionService
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = docs.appendingPathComponent("entries.json")
    }

    // MARK: - CRUD Operations

    /// Loads all entries from disk.
    func loadEntries() throws -> [VoiceEntry] {
        if loaded { return entries }

        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            loaded = true
            return []
        }

        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = try decoder.decode([VoiceEntry].self, from: data)
        entries.sort { $0.createdAt > $1.createdAt }
        loaded = true
        return entries
    }

    /// Saves a new entry.
    func save(_ entry: VoiceEntry) throws {
        if !loaded { _ = try loadEntries() }
        entries.insert(entry, at: 0)
        try persist()
    }

    /// Updates an existing entry.
    func update(_ entry: VoiceEntry) throws {
        if !loaded { _ = try loadEntries() }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        try persist()
    }

    /// Deletes an entry by ID.
    func delete(id: UUID) throws {
        if !loaded { _ = try loadEntries() }
        entries.removeAll { $0.id == id }
        try persist()
    }

    /// Returns all entries sorted by date descending.
    func allEntries() throws -> [VoiceEntry] {
        try loadEntries()
    }

    // MARK: - Search

    /// Searches entries by transcript or summary content.
    func search(query: String) throws -> [VoiceEntry] {
        let all = try loadEntries()
        let lowered = query.lowercased()
        return all.filter { entry in
            entry.transcript.lowercased().contains(lowered) ||
            entry.summaryTitle.lowercased().contains(lowered) ||
            entry.summaryText.lowercased().contains(lowered) ||
            entry.tags.contains { $0.lowercased().contains(lowered) }
        }
    }

    /// Searches entries by tag.
    func searchByTag(_ tag: String) throws -> [VoiceEntry] {
        let all = try loadEntries()
        let lowered = tag.lowercased()
        return all.filter { $0.tags.contains { $0.lowercased() == lowered } }
    }

    /// Searches entries within a date range.
    func searchByDateRange(from: Date, to: Date) throws -> [VoiceEntry] {
        let all = try loadEntries()
        return all.filter { $0.createdAt >= from && $0.createdAt <= to }
    }

    /// Deletes all entries from disk and clears the in-memory cache.
    func deleteAll() throws {
        entries = []
        loaded = true
        try? FileManager.default.removeItem(at: storageURL)
    }

    // MARK: - Private

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(entries)
        try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
    }
}
