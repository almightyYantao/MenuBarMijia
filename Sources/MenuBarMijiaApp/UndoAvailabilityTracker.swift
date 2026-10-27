import Foundation
import MijiaCore
import Observation

/// Keeps the "撤销上一步" entry alive after the undo banner expires (#53).
///
/// The store keeps its own `lastAssistantUndo` for ten minutes, but it is internal and there is no
/// public "is undo available" flag. This tracker mirrors the *UI-visible* signal: an assistant
/// action finished successfully. The actual window is still enforced by the store, so a stale entry
/// only ever answers "没有可以撤销的操作".
@Observable
@MainActor
final class UndoAvailabilityTracker {
    static let shared = UndoAvailabilityTracker()

    /// Same window as `HomeStore.voiceUndoWindow` (10 minutes).
    static let window: TimeInterval = 10 * 60

    private(set) var lastActionAt: Date?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var suppressNotesUntil: Date = .distantPast

    private init() {}

    var isAvailable: Bool {
        lastActionAt != nil
    }

    /// Called when the assistant reports a completed command. Executing "撤销" itself also ends in
    /// `.done`, so the note is suppressed while (and just after) an undo runs.
    func noteAssistantAction() {
        guard Date() >= suppressNotesUntil else { return }
        lastActionAt = Date()
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.window))
            guard !Task.isCancelled else { return }
            self?.lastActionAt = nil
        }
    }

    func beginUndo() {
        suppressNotesUntil = Date().addingTimeInterval(1.5)
        expiryTask?.cancel()
        expiryTask = nil
        lastActionAt = nil
    }

    func finishUndo() {
        suppressNotesUntil = Date().addingTimeInterval(1.5)
        lastActionAt = nil
    }

    /// Shared button action for the AI bar and the panel footer.
    func performUndo(store: HomeStore) async {
        beginUndo()
        _ = await store.runAssistantCommand(L10n.tr("撤销", "undo"))
        finishUndo()
    }
}
