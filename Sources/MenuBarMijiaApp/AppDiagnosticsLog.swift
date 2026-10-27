import Foundation
import MijiaCore
import Observation

/// App-local ring buffer of *when* errors happened, used by "复制诊断信息" (#45).
///
/// Only timestamps are stored: error strings can embed a host or device payload, so the raw text is
/// never persisted. The diagnostics report therefore shows a count and the latest time, nothing else.
@Observable
@MainActor
final class AppDiagnosticsLog {
    static let shared = AppDiagnosticsLog()

    private static let storageKey = "diagnostics_error_timestamps"
    private static let capacity = 20

    private(set) var errorTimestamps: [Date]
    @ObservationIgnored private var lastRecordedToastId: UUID?

    private init() {
        let stored = UserDefaults.standard.array(forKey: Self.storageKey) as? [Double] ?? []
        errorTimestamps = stored.map(Date.init(timeIntervalSince1970:))
    }

    func record(_ notice: ToastNotice?) {
        guard let notice, notice.isError else { return }
        guard notice.id != lastRecordedToastId else { return }
        lastRecordedToastId = notice.id
        errorTimestamps.append(Date())
        if errorTimestamps.count > Self.capacity {
            errorTimestamps.removeFirst(errorTimestamps.count - Self.capacity)
        }
        UserDefaults.standard.set(errorTimestamps.map(\.timeIntervalSince1970), forKey: Self.storageKey)
    }
}
