import AppKit
import MijiaCore
import SwiftUI

// MARK: - Settings: 检查更新

/// Manual update check against GitHub Releases; opens the release page instead of installing.
struct UpdateSection: View {
    let store: HomeStore

    private enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(String)
    }

    @State private var status: Status = .idle

    var body: some View {
        let _ = store.effectiveLanguage
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr("版本 \(UpdateChecker.bundleVersion)", "Version \(UpdateChecker.bundleVersion)"))
                    .font(.system(size: 11, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if case .available(_, let url) = status {
                Button(L10n.tr("去下载", "Download")) {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(PillActionButtonStyle(isSelected: true, tintColor: .accentColor))
            } else {
                Button(status == .checking ? L10n.tr("检查中…", "Checking…") : L10n.tr("检查更新", "Check for Updates")) {
                    Task { await check() }
                }
                .buttonStyle(PillActionButtonStyle())
                .disabled(status == .checking)
            }
        }
        .padding(12)
        .glassTile(isActive: false, accent: .accentColor, cornerRadius: 12)
    }

    private var statusText: String {
        switch status {
        case .idle:
            return L10n.tr("MenuBarMijia 更新发布在 GitHub Releases", "MenuBarMijia updates are published on GitHub Releases")
        case .checking:
            return L10n.tr("正在查看 GitHub 上的最新版本…", "Checking GitHub for the latest release…")
        case .upToDate:
            return L10n.tr("已是最新版本", "You're up to date")
        case .available(let version, _):
            return L10n.tr(
                "有新版本 \(version)，下载后拖进「应用程序」替换即可",
                "New version \(version) available — download and drag into Applications"
            )
        case .failed(let message):
            return message
        }
    }

    private var statusIsError: Bool {
        if case .failed = status { return true }
        return false
    }

    private func check() async {
        status = .checking
        do {
            switch try await UpdateChecker(currentVersion: UpdateChecker.bundleVersion).check() {
            case .upToDate:
                status = .upToDate
            case .available(let version, let url, _):
                status = .available(version: version, url: url)
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
