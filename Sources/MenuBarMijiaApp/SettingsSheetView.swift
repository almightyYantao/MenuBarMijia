import SwiftUI
import AppKit
import ServiceManagement
import MijiaCore

public struct SettingsSheetView: View {
    public let store: HomeStore

    @State private var urlDraft: String = ""
    @State private var tokenDraft: String = ""
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @AppStorage(AppSkin.storageKey) private var skinRaw: String = AppSkin.classic.rawValue
    @AppStorage(AppSkin.climatePanelKey) private var climatePanelModule: Bool = true
    @AppStorage(PanelHeight.storageKey) private var panelHeightRaw: String = PanelHeight.standard.rawValue

    public init(store: HomeStore) {
        self.store = store
    }

    public var body: some View {
        let _ = store.effectiveLanguage
        VStack(alignment: .leading, spacing: 0) {
            // Pinned Header
            HStack {
                Button {
                    withAnimation(AppleMotion.snappySpring) {
                        store.isShowingSettings = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text(L10n.tr("返回面板", "Dashboard"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(PillActionButtonStyle())

                Spacer()

                Text(L10n.tr("偏好设置", "Settings"))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button {
                    withAnimation(AppleMotion.snappySpring) {
                        store.reopenOnboarding()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                        Text(L10n.tr("新手引导", "Guide"))
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(PillActionButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()
                .overlay(Color.primary.opacity(0.07))

            // Scrollable Settings Body
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 11) {
                    // 0. Panel Skin
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("面板皮肤", "Panel Skin"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        SkinPickerGrid(selection: Binding(
                            get: { AppSkin(rawValue: skinRaw) ?? .classic },
                            set: { skinRaw = $0.rawValue }
                        ))

                        Text(L10n.tr(
                            "经典之外的皮肤还带有：房间滑块、卡片依次入场、在灯上左右拖动调亮度、按住「全关」0.6 秒确认。",
                            "Skins other than Classic add a sliding room pill, staggered tiles, drag across a light to dim, and hold-to-confirm All Off."
                        ))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Divider().overlay(Color.primary.opacity(0.06))

                        HStack {
                            Text(L10n.tr("面板高度", "Panel Height"))
                                .font(.system(size: 12))
                            Spacer()
                            Picker("", selection: $panelHeightRaw) {
                                ForEach(PanelHeight.allCases) { h in
                                    Text(h.title).tag(h.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 196)
                            .controlSize(.small)
                        }

                        settingsToggleRow(
                            title: L10n.tr("空调使用整行面板模块", "Full-Width Climate Panel"),
                            isOn: $climatePanelModule
                        )
                    }
                    .padding(12)
                    .glassTile(isActive: false, accent: .accentColor, cornerRadius: 12)

                    // 1. Menu Bar & Interface Options
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("菜单栏与交互体验", "Menu Bar & Interface"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(L10n.tr("界面语言 / Language", "Language / 界面语言"))
                                .font(.system(size: 12))
                            Spacer()
                            Picker(
                                "",
                                selection: Binding(
                                    get: { store.appLanguagePreference },
                                    set: { store.appLanguagePreference = $0 }
                                )
                            ) {
                                ForEach(AppLanguagePreference.allCases) { pref in
                                    Text(pref.label).tag(pref)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 176)
                            .controlSize(.small)
                        }

                        Divider().overlay(Color.primary.opacity(0.06))

                        HStack {
                            Text(L10n.tr("面板标题", "Dashboard Title"))
                                .font(.system(size: 12))
                            Spacer()
                            TextField(
                                KeychainHelper.localizedDefaultHomeName,
                                text: Binding(
                                    get: { store.homeName },
                                    set: { store.homeName = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .frame(width: 140)
                        }

                        Divider().overlay(Color.primary.opacity(0.06))

                        HStack {
                            Text(L10n.tr("菜单栏旁显示", "Menu Bar Readout"))
                                .font(.system(size: 12))
                            Spacer()
                            Picker(
                                "",
                                selection: Binding(
                                    get: { store.menuBarTargetId },
                                    set: { store.menuBarTargetId = $0 }
                                )
                            ) {
                                ForEach(store.availableMenuBarOptions) { option in
                                    Text(option.title).tag(option.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 176)
                            .controlSize(.small)
                        }

                        Divider().overlay(Color.primary.opacity(0.06))

                        settingsToggleRow(
                            title: L10n.tr("显示顶部快捷场景栏", "Show Quick Scenes Bar"),
                            isOn: Binding(
                                get: { store.showQuickActionsBar },
                                set: { store.showQuickActionsBar = $0 }
                            )
                        )

                        settingsToggleRow(
                            title: L10n.tr("双列紧凑磁贴视图", "2-Column Compact Grid"),
                            isOn: Binding(
                                get: { store.isCompactGridMode },
                                set: { store.isCompactGridMode = $0 }
                            )
                        )

                        settingsToggleRow(
                            title: L10n.tr("全局快捷键 ⌥M 呼出面板", "Global Hotkey ⌥M for Dashboard"),
                            isOn: Binding(
                                get: { store.enableGlobalHotkey },
                                set: { store.enableGlobalHotkey = $0 }
                            )
                        )

                        settingsToggleRow(
                            title: L10n.tr("主动安全与低电量提醒", "Safety & Low Battery Alerts"),
                            isOn: Binding(
                                get: { store.enableSafetyAlerts },
                                set: { store.enableSafetyAlerts = $0 }
                            )
                        )

                        settingsToggleRow(
                            title: L10n.tr("隐藏离线/未通电的设备", "Hide Offline / Unpowered Devices"),
                            isOn: Binding(
                                get: { store.hideOfflineDevices },
                                set: { store.hideOfflineDevices = $0 }
                            )
                        )

                        HStack {
                            Text(L10n.tr("登录 Mac 时自动启动", "Launch at Login"))
                                .font(.system(size: 12))
                            Spacer()
                            Toggle("", isOn: $launchAtLogin)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .onChange(of: launchAtLogin) { _, newValue in
                                    do {
                                        if newValue {
                                            try SMAppService.mainApp.register()
                                        } else {
                                            try SMAppService.mainApp.unregister()
                                        }
                                    } catch {
                                        store.showToast(
                                            L10n.tr("开机自启需要在应用程序目录运行", "Launch at Login requires running from /Applications"),
                                            isError: true
                                        )
                                    }
                                }
                        }
                    }
                    .padding(12)
                    .glassTile(isActive: false, accent: .accentColor, cornerRadius: 12)

                    // 2. Hidden Devices Management (if any)
                    if !store.hiddenDevices.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.tr(
                                "已隐藏的设备 (\(store.hiddenDevices.count))",
                                "Hidden Devices (\(store.hiddenDevices.count))"
                            ))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ForEach(store.hiddenDevices) { dev in
                                HStack(spacing: 8) {
                                    Image(systemName: dev.sfSymbolName)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(dev.name)
                                            .font(.system(size: 11.5, weight: .medium))
                                        Text(L10n.displayRoomName(dev.roomName))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button(L10n.tr("恢复显示", "Unhide")) {
                                        withAnimation(AppleMotion.snappySpring) {
                                            store.unhideDevice(dev.id)
                                        }
                                    }
                                    .buttonStyle(PillActionButtonStyle())
                                }
                            }
                        }
                        .padding(12)
                        .glassTile(isActive: false, accent: .accentColor, cornerRadius: 12)
                    }

                    // 3. Connection Configuration (Home Assistant / Xiaomi Cloud)
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(L10n.tr("连接配置", "Connection"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(connectionBadgeText)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(connectionBadgeColor)
                        }

                        Picker(
                            "",
                            selection: Binding(
                                get: { store.homeBackend },
                                set: { newBackend in
                                    withAnimation(AppleMotion.snappySpring) {
                                        store.switchBackend(newBackend)
                                    }
                                }
                            )
                        ) {
                            ForEach(HomeBackend.allCases) { backend in
                                Text(backend.title).tag(backend)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)

                        if store.homeBackend == .homeAssistant {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(L10n.tr("服务器地址", "Server URL"))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if let firstHA = store.discoveredHAInstances.first {
                                        if HAWebSocketProvider.normalizeBaseURL(urlDraft) == firstHA.baseURL {
                                            Label(
                                                L10n.tr("局域网已识别 · \(firstHA.locationName)", "LAN Detected · \(firstHA.locationName)"),
                                                systemImage: "checkmark.seal.fill"
                                            )
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.green)
                                        } else {
                                            Button(L10n.tr("填入已发现：\(firstHA.hostAndPort)", "Use Found: \(firstHA.hostAndPort)")) {
                                                urlDraft = firstHA.baseURL
                                            }
                                            .buttonStyle(.plain)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                TextField("http://homeassistant.local:8123", text: $urlDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .font(.system(size: 11.5, design: .monospaced))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(L10n.tr("长期访问令牌 (安全存入钥匙串)", "Long-Lived Access Token (Stored in Keychain)"))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if let secURL = URL(string: "\(HAWebSocketProvider.normalizeBaseURL(urlDraft))/profile/security") {
                                        Button(L10n.tr("打开网页取令牌", "Open Security Page")) {
                                            NSWorkspace.shared.open(secURL)
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.accentColor)
                                    }
                                }
                                SecureField(L10n.tr("粘贴 HA 长期访问令牌", "Paste HA Long-Lived Access Token"), text: $tokenDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .font(.system(size: 11.5, design: .monospaced))
                            }

                            HStack {
                                Button(store.isDiscoveringHA ? L10n.tr("扫描中…", "Scanning…") : L10n.tr("扫描局域网 HA", "Scan LAN for HA")) {
                                    Task {
                                        let found = await store.discoverHomeAssistantOnLAN(autoApplyIfDefault: false)
                                        if let first = found.first {
                                            urlDraft = first.baseURL
                                            store.showToast(L10n.tr("已发现：\(first.displaySummary)", "Found: \(first.displaySummary)"))
                                        } else {
                                            store.showToast(L10n.tr("未在局域网扫描到 Home Assistant", "No Home Assistant found on LAN"), isError: true)
                                        }
                                    }
                                }
                                .buttonStyle(PillActionButtonStyle())
                                .disabled(store.isDiscoveringHA)

                                Button(L10n.tr("默认地址", "Default URL")) {
                                    urlDraft = KeychainHelper.defaultNASURL
                                }
                                .buttonStyle(PillActionButtonStyle())

                                Spacer()

                                Button(L10n.tr("保存并重新连接", "Save & Reconnect")) {
                                    store.updateConnection(serverURL: urlDraft, token: tokenDraft)
                                    withAnimation(AppleMotion.snappySpring) {
                                        store.isShowingSettings = false
                                    }
                                }
                                .buttonStyle(PillActionButtonStyle(isSelected: true, tintColor: .accentColor))
                            }
                            .padding(.top, 2)
                        } else {
                            MiAccountSection(store: store)
                        }
                    }
                    .padding(12)
                    .glassTile(isActive: false, accent: .accentColor, cornerRadius: 12)

                    LGWebOSSettingsSection(store: store)

                    AssistantSettingsSection(store: store)

                    UpdateSection(store: store)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
            }
            .frame(maxHeight: .infinity)

            Divider()
                .overlay(Color.primary.opacity(0.07))

            // Pinned Bottom Quit Row
            HStack {
                Text(L10n.tr(
                    "\(store.homeName) · 在线 \(store.onlineDeviceCount)/\(store.devices.count) 台",
                    "\(store.homeName) · \(store.onlineDeviceCount)/\(store.devices.count) online"
                ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text(L10n.tr("退出 MenuBarMijia", "Quit MenuBarMijia"))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .onAppear {
            urlDraft = store.serverURLString
            tokenDraft = KeychainHelper.loadToken()
            if store.discoveredHAInstances.isEmpty {
                Task {
                    let found = await store.discoverHomeAssistantOnLAN(autoApplyIfDefault: true)
                    if let first = found.first,
                       HAWebSocketProvider.normalizeBaseURL(urlDraft) == KeychainHelper.defaultNASURL {
                        urlDraft = first.baseURL
                    }
                }
            }
        }
    }

    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var connectionBadgeText: String {
        switch store.connectionStatus {
        case .connected: return L10n.tr("● 已连接", "● Connected")
        case .connecting: return L10n.tr("● 连接中…", "● Connecting…")
        case .disconnected: return L10n.tr("● 未连接", "● Disconnected")
        }
    }

    private var connectionBadgeColor: Color {
        switch store.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }
}

private struct LGWebOSSettingsSection: View {
    let store: HomeStore
    @State private var isEnabled: Bool = false
    @State private var hostDraft: String = ""
    @State private var macDraft: String = ""
    @State private var nameDraft: String = ""
    @State private var isScanning: Bool = false

    var body: some View {
        let _ = store.effectiveLanguage
        let isPaired = !store.lgConfig.clientKey.isEmpty
        let hasHost = !hostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L10n.tr("LG webOS 电视局域网直连", "LG webOS TV Direct LAN"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isPaired
                     ? L10n.tr("● 已配对密钥", "● Paired")
                     : (isEnabled
                        ? (hasHost ? L10n.tr("● 待电视确认", "● Awaiting TV Prompt") : L10n.tr("● 待填电视 IP", "● Enter TV IP"))
                        : L10n.tr("● 已停用", "● Disabled")))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isPaired ? .green : (isEnabled ? .orange : .secondary))
            }

            HStack {
                Text(L10n.tr("启用 LG 电视局域网直连 (SSAP + WoL)", "Enable LG TV LAN Control (SSAP + WoL)"))
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: isEnabled) { _, newValue in
                        var next = store.lgConfig
                        next.isEnabled = newValue
                        next.host = hostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        next.macAddress = macDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.updateLGWebOSConfig(next)
                    }
            }

            if isEnabled {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.tr("局域网 IP", "LAN IP"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        TextField(L10n.tr("如 192.168.1.50", "e.g. 192.168.1.50"), text: $hostDraft)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .font(.system(size: 11, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.tr("MAC 地址 (Wake-on-LAN)", "MAC Address (Wake-on-LAN)"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        TextField(L10n.tr("如 AA:BB:CC:DD:EE:FF", "e.g. AA:BB:CC:DD:EE:FF"), text: $macDraft)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }

                HStack {
                    Button(isScanning ? L10n.tr("扫描中…", "Scanning…") : L10n.tr("扫描局域网电视", "Scan LAN TV")) {
                        isScanning = true
                        Task {
                            let found = await store.discoverLGWebOSTVs(hostHint: hostDraft)
                            isScanning = false
                            if let first = found.first {
                                hostDraft = first.host
                                store.showToast(L10n.tr(
                                    "已发现：\(first.friendlyName) (\(first.host))",
                                    "Found: \(first.friendlyName) (\(first.host))"
                                ))
                            } else {
                                store.showToast(
                                    L10n.tr("未扫描到开机状态的 LG 电视", "No powered-on LG TV found on LAN"),
                                    isError: true
                                )
                            }
                        }
                    }
                    .buttonStyle(PillActionButtonStyle())
                    .disabled(isScanning)

                    Button(L10n.tr("发起电视配对", "Pair TV")) {
                        saveDrafts()
                        store.triggerLGWebOSPairing()
                    }
                    .buttonStyle(PillActionButtonStyle())

                    Spacer()

                    Button(L10n.tr("保存配置", "Save")) {
                        saveDrafts()
                    }
                    .buttonStyle(PillActionButtonStyle(isSelected: true, tintColor: .accentColor))
                }
            }
        }
        .padding(12)
        .glassTile(isActive: false, accent: .accentColor, cornerRadius: 12)
        .onAppear {
            isEnabled = store.lgConfig.isEnabled
            hostDraft = store.lgConfig.host
            macDraft = store.lgConfig.macAddress
            nameDraft = store.lgConfig.name
        }
    }

    private func saveDrafts() {
        var next = store.lgConfig
        next.isEnabled = isEnabled
        next.host = hostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        next.macAddress = macDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        store.updateLGWebOSConfig(next)
    }
}

