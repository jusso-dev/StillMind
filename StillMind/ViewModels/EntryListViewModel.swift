import Foundation
import Observation

/// ViewModel for the journal entry list screen.
@Observable
@MainActor
final class EntryListViewModel {
    var entries: [VoiceEntry] = []
    var isLoading = false
    var errorMessage: String?

    private let entryRepository: EntryRepository

    nonisolated private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    init(entryRepository: EntryRepository) {
        self.entryRepository = entryRepository
    }

    func loadEntries() async {
        isLoading = true
        do {
            entries = try await entryRepository.allEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func deleteEntry(_ entry: VoiceEntry) async {
        do {
            try await entryRepository.delete(id: entry.id)
            entries.removeAll { $0.id == entry.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    func formattedDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
