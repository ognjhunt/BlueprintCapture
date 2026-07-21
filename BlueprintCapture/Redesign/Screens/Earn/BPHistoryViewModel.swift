import Foundation
import Combine

// MARK: - BPHistoryViewModel
//
// Real capture history for the History tab, plus per-capture detail (timeline,
// quality, earnings breakdown) fetched on demand. Backend-derived only.

@MainActor
final class BPHistoryViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var entries: [CaptureHistoryEntry] = []

    @Published var selectedEntry: CaptureHistoryEntry?
    @Published private(set) var selectedDetail: CaptureDetailResponse?
    @Published private(set) var detailLoading = false

    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        do {
            let history = try await APIService.shared.fetchCaptureHistory()
            entries = history.sorted { $0.capturedAt > $1.capturedAt }
            phase = .loaded
        } catch {
            entries = []
            phase = .failed("History sync is unavailable right now.")
        }
    }

    func select(_ entry: CaptureHistoryEntry) {
        selectedEntry = entry
        selectedDetail = nil
        detailLoading = true
        Task {
            let detail = try? await APIService.shared.fetchCaptureDetail(id: entry.id)
            if selectedEntry?.id == entry.id {
                selectedDetail = detail
                detailLoading = false
            }
        }
    }

    func clearSelection() {
        selectedEntry = nil
        selectedDetail = nil
        detailLoading = false
    }
}
