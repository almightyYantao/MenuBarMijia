import SwiftUI
import AppKit
import MijiaCore

public struct ControlCenterPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppSkin.storageKey) private var skinRaw: String = AppSkin.classic.rawValue
    @AppStorage(AppSkin.climatePanelKey) private var climatePanelModule: Bool = true
    @AppStorage(DeviceLayoutPrefs.storageKey) private var tileSizesRaw: String = "{}"
    @AppStorage(DeviceLayoutPrefs.orderKey) private var orderRaw: String = "[]"
    @State private var isEditingLayout = false
    @State private var draggingId: String?
    // In-memory mirrors of the saved order/sizes: @AppStorage publishes changes outside the
    // current animation transaction, so moves made through it alone snap instead of sliding.
    @State private var liveOrder: [String]?
    @State private var liveSizes: [String: TileSize]?
    @State private var tileFrames: [String: CGRect] = [:]
    @State private var dragLocation: CGPoint?
    @State private var grabOffset: CGSize = .zero
    @State private var lastSwapTarget: String?
    @State private var lastSwapAt: Date = .distantPast
    @State private var pressTask: Task<Void, Never>?
    @State private var pressCancelled = false
    @AppStorage(GroupPrefs.groupsKey) private var groupsRaw: String = "[]"
    @AppStorage(GroupPrefs.mapKey) private var groupMapRaw: String = "{}"
    @AppStorage(GroupPrefs.collapsedKey) private var collapsedRaw: String = "[]"
    @State private var liveGroupMap: [String: String]?
    @AppStorage(GroupPrefs.aliasesKey) private var aliasesRaw: String = "{}"
    @State private var layoutUI = LayoutUIState.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Opens the ⌘, Settings window; the popover no longer hosts the long form (#42).
    @Environment(\.openSettings) private var openSettings
    /// Drives the open animation; reset whenever the menu-bar window closes so every open replays it.
    @State private var isPresented = false

    /// Card sizes are remembered per page: a room id, or "all" for the overview.
    private var layoutScope: String { store.selectedRoomId ?? "all" }
    @AppStorage(PanelHeight.storageKey) private var panelHeightRaw: String = PanelHeight.standard.rawValue
    @Namespace private var roomPillNamespace
    public let store: HomeStore

    private static let panelWidth: CGFloat = 376
    private var panelHeight: CGFloat { (PanelHeight(rawValue: panelHeightRaw) ?? .standard).points }
    private var skin: AppSkin { AppSkin(rawValue: skinRaw) ?? .classic }
    private var skinAccentFill: AnyShapeStyle { skin.isClassic ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(skin.palette.accentGradient) }
    private var skinOnAccent: Color { skin.isClassic ? .white : skin.palette.onAccent }

    public init(store: HomeStore) {
        self.store = store
    }

    public var body: some View {
        let _ = store.effectiveLanguage
        ZStack(alignment: .bottom) {
            if store.shouldShowOnboarding {
                OnboardingGuideView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                mainDashboard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            overlayNotifications

            groupPromptOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Keep the in-memory mirrors in step with edits made elsewhere (card context menus).
        .onChange(of: groupMapRaw) { _, raw in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { liveGroupMap = GroupPrefs.map(raw) }
        }
        .onChange(of: tileSizesRaw) { _, raw in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { liveSizes = DeviceLayoutPrefs.decode(raw) }
        }
        .onChange(of: store.favoriteOrder) { _, favOrder in
            guard !favOrder.isEmpty else { return }
            var order = currentOrder
            guard !order.isEmpty else { return }
            let favSet = Set(favOrder)
            var favIdx = 0
            for i in order.indices where favSet.contains(order[i]) {
                if favIdx < favOrder.count {
                    order[i] = favOrder[favIdx]
                    favIdx += 1
                }
            }
            if order != currentOrder {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { liveOrder = order }
                orderRaw = DeviceLayoutPrefs.encodeOrder(order)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: layoutUI.newGroupForDevice)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: layoutUI.renamingGroupId)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: layoutUI.renamingDeviceId)
        .frame(width: Self.panelWidth, height: panelHeight)
        .onChange(of: skinRaw) { _, _ in syncMenuBarWindowSize() }
        .onChange(of: panelHeightRaw) { _, _ in syncMenuBarWindowSize() }
        // #53: remember a successful assistant action so "撤销上一步" outlives the banner.
        .onChange(of: store.assistantState) { _, state in
            if case .done = state {
                UndoAvailabilityTracker.shared.noteAssistantAction()
            }
        }
        // #45: the only place that sees every error toast is the panel root.
        .onChange(of: store.toastNotice?.id) { _, _ in
            AppDiagnosticsLog.shared.record(store.toastNotice)
        }
        // Open animation: drop in from the menu bar with a slight scale and fade.
        .scaleEffect(isPresented || reduceMotion ? 1 : 0.94, anchor: .top)
        .offset(y: isPresented || reduceMotion ? 0 : -10)
        .opacity(isPresented ? 1 : 0)
        .blur(radius: isPresented || reduceMotion ? 0 : 6)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard !isPresented else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { isPresented = true }
        }
        // Reset only when the panel is really hidden. Resigning key also happens when a context
        // menu opens, and resetting then left the panel at opacity 0 (a blank window).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let w = note.object as? NSWindow, w.className.contains("MenuBarExtra") else { return }
            if !w.occlusionState.contains(.visible) { isPresented = false }
            else if !isPresented { withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { isPresented = true } }
        }
        .onAppear {
            SettingsWindowOpener.shared.open = { openSettings() }
            syncMenuBarWindowSize()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { isPresented = true }
        }
        // Mi cloud polls every 6 s only while the panel is on screen (#26).
        .onChange(of: isPresented) { _, visible in store.setPanelVisible(visible) }
        .onDisappear { store.setPanelVisible(false) }
        .environment(\.isEditingLayout, isEditingLayout)
        .skinRoot(skin)
        .task {
            await store.checkForUpdatesIfNeeded()
        }
    }

    private func syncMenuBarWindowSize() {
        let target = NSSize(width: Self.panelWidth, height: panelHeight)
        guard let window = NSApp.windows.first(where: { $0.className.contains("MenuBarExtra") }) else { return }
        let oldFrame = window.frame
        let newRect = window.frameRect(forContentRect: NSRect(origin: .zero, size: target))
        guard abs(oldFrame.width - newRect.width) > 0.5 || abs(oldFrame.height - newRect.height) > 0.5 else { return }
        let newOrigin = NSPoint(
            x: (oldFrame.midX - newRect.width / 2).rounded(),
            y: oldFrame.maxY - newRect.height
        )
        window.setFrame(NSRect(origin: newOrigin, size: newRect.size), display: true, animate: false)
    }

    // MARK: - Main Dashboard

    private var mainDashboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            topHeroHeader
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if store.isShowingAssistantBar {
                AssistantCommandBar(store: store)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(AppleMotion.drawerTransition)
            }

            if store.showQuickActionsBar {
                quickActionsAndScenesBar
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            if let suggestion = store.pendingHAAddressSuggestion {
                haAddressSuggestionBanner(suggestion)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(AppleMotion.drawerTransition)
            }

            roomFilterBar
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            Divider()
                .overlay(Color.primary.opacity(0.07))

            ScrollView(.vertical, showsIndicators: false) {
                let sections = pageSections
                let quickIndexMap = Dictionary(
                    uniqueKeysWithValues: sections.flatMap(\.devices).prefix(9).enumerated().map { ($1.id, $0 + 1) }
                )

                VStack(alignment: .leading, spacing: 11) {
                    if store.filteredDevices.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(sections) { section in
                            if section.title != nil {
                                groupHeader(section)
                            }
                            if !collapsedGroups.contains(collapseKey(section)) {
                                deviceCollectionView(
                                    devices: section.devices,
                                    showRoomBadge: store.selectedRoomId == nil,
                                    quickIndexMap: quickIndexMap
                                )
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: -8)),
                                    removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                                ))
                            }
                        }
                    }
                }
                .coordinateSpace(name: TileSpace.name)
                // Cards stop hit-testing in edit mode; the container must still catch the press.
                .contentShape(Rectangle())
                .simultaneousGesture(tileDragGesture)
                .onPreferenceChange(TileFramesKey.self) { frames in
                    if frames != tileFrames { tileFrames = frames }
                }
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, store.undoBanner != nil || store.toastNotice != nil ? 48 : 12)
            }
            .frame(maxHeight: .infinity)

            Divider()
                .overlay(Color.primary.opacity(0.07))

            footerBar
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .animation(AppleMotion.snappySpring, value: store.isShowingAssistantBar)
    }

    // MARK: - Layout Editing

    private func editable(_ device: SmartDevice) -> LayoutEditable {
        LayoutEditable(
            deviceId: device.id,
            size: tileSize(device),
            isDragging: draggingId == device.id,
            dragOffset: dragOffset(for: device.id),
            onCycleSize: { cycleSize(device) }
        )
    }

    // MARK: - Page Sections (favorites, custom groups, ungrouped)

    private struct PageSection: Identifiable {
        let id: String
        let title: String?
        let devices: [SmartDevice]
        /// Custom group id when the section is a user group (enables rename / reorder / delete).
        let groupId: String?
    }

    private var groups: [DeviceGroup] { GroupPrefs.groups(groupsRaw) }
    private var groupMap: [String: String] { liveGroupMap ?? GroupPrefs.map(groupMapRaw) }
    private var collapsedGroups: Set<String> { GroupPrefs.set(collapsedRaw) }

    /// Collapse state is per page: folding "更多设备" in All must not hide "其他" in a room.
    private func collapseKey(_ section: PageSection) -> String { "\(layoutScope)|\(section.id)" }

    /// "All": 常用 first, then each custom group, then the rest. A room: custom groups then 其他;
    /// without any group in the room it is one untitled section, as before.
    private var pageSections: [PageSection] {
        let known = Set(groups.map(\.id))
        let map = groupMap.filter { known.contains($0.value) }
        let order = currentOrder
        var sections: [PageSection] = []
        let pool: [SmartDevice]
        if store.selectedRoomId == nil {
            if !store.favoriteDevices.isEmpty {
                let orderedFavs = DeviceLayoutPrefs.apply(order: order, to: store.favoriteDevices)
                sections.append(PageSection(id: "fav", title: L10n.tr("常用控制", "Favorites"), devices: orderedFavs, groupId: nil))
            }
            pool = store.nonFavoriteDevices
        } else {
            pool = store.filteredDevices
        }
        for group in groups {
            let members = DeviceLayoutPrefs.apply(order: order, to: pool.filter { map[$0.id] == group.id })
            if !members.isEmpty {
                sections.append(PageSection(id: group.id, title: group.name, devices: members, groupId: group.id))
            }
        }
        let rest = DeviceLayoutPrefs.apply(order: order, to: pool.filter { map[$0.id] == nil })
        if !rest.isEmpty {
            let titled = !sections.isEmpty
            let title: String? = store.selectedRoomId == nil
                ? (sections.isEmpty ? L10n.tr("全屋设备", "All Devices") : L10n.tr("更多设备", "More Devices"))
                : (titled ? L10n.tr("其他", "Other") : nil)
            sections.append(PageSection(id: "rest", title: title, devices: rest, groupId: nil))
        }
        return sections
    }

    /// Section key used to detect a drag into a different section.
    private func sectionKey(of id: String) -> String {
        if store.selectedRoomId == nil, store.favoriteDeviceIds.contains(id) { return "fav" }
        let known = Set(groups.map(\.id))
        if let g = groupMap[id], known.contains(g) { return g }
        return "rest"
    }

    /// Files `dragged` into `target`'s section (favorites and/or custom group).
    private func adoptSection(of target: String, for dragged: String) {
        let from = sectionKey(of: dragged), to = sectionKey(of: target)
        guard from != to else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if store.selectedRoomId == nil, (from == "fav") != (to == "fav") {
                store.toggleFavorite(dragged)
            }
            if to != "fav" {
                var map = groupMap
                map[dragged] = to == "rest" ? nil : to
                liveGroupMap = map
                groupMapRaw = GroupPrefs.encode(map)
            }
        }
    }

    @State private var hoveredHeader: String?

    private func groupHeader(_ section: PageSection) -> some View {
        let collapsed = collapsedGroups.contains(collapseKey(section))
        let accent = skin.isClassic ? Color.accentColor : skin.palette.accent
        return Button {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                var set = collapsedGroups
                if collapsed { set.remove(collapseKey(section)) } else { set.insert(collapseKey(section)) }
                collapsedRaw = GroupPrefs.encode(set)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .foregroundStyle(hoveredHeader == section.id ? accent : Color.secondary)
                Text(section.title ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hoveredHeader == section.id ? accent : Color.secondary)
                Text("\(section.devices.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(section.devices.count)))
                    .foregroundStyle(.secondary.opacity(0.8))
                if section.groupId != nil {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(hoveredHeader == section.id ? 0.35 : 0.18))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredHeader = $0 ? section.id : (hoveredHeader == section.id ? nil : hoveredHeader) }
        .animation(.easeOut(duration: 0.15), value: hoveredHeader)
        .contextMenu {
            if let gid = section.groupId {
                Button { layoutUI.renamingGroupId = gid } label: { Label(L10n.tr("重命名", "Rename"), systemImage: "pencil") }
                Button { moveGroup(gid, by: -1) } label: { Label(L10n.tr("上移分组", "Move Up"), systemImage: "arrow.up") }
                Button { moveGroup(gid, by: 1) } label: { Label(L10n.tr("下移分组", "Move Down"), systemImage: "arrow.down") }
                Divider()
                Button(role: .destructive) { deleteGroup(gid) } label: { Label(L10n.tr("删除分组", "Delete Group"), systemImage: "trash") }
            }
        }
        .padding(.bottom, -3)
    }

    private func moveGroup(_ id: String, by delta: Int) {
        var list = groups
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard list.indices.contains(j) else { return }
        list.swapAt(i, j)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { groupsRaw = GroupPrefs.encode(list) }
    }

    private func deleteGroup(_ id: String) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
            groupsRaw = GroupPrefs.encode(groups.filter { $0.id != id })
            let map = groupMap.filter { $0.value != id }
            liveGroupMap = map
            groupMapRaw = GroupPrefs.encode(map)
        }
    }

    /// Name prompt overlay for creating (and filing a device into) or renaming a group.
    @ViewBuilder
    private var groupPromptOverlay: some View {
        if let deviceId = layoutUI.newGroupForDevice {
            promptBackdrop {
                GroupNamePrompt(title: L10n.tr("新建分组", "New Group"), name: "") { name in
                    let group = DeviceGroup(id: UUID().uuidString, name: name)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        groupsRaw = GroupPrefs.encode(groups + [group])
                        var map = groupMap
                        map[deviceId] = group.id
                        liveGroupMap = map
                        groupMapRaw = GroupPrefs.encode(map)
                        layoutUI.newGroupForDevice = nil
                    }
                } onCancel: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { layoutUI.newGroupForDevice = nil }
                }
            }
        } else if let did = layoutUI.renamingDeviceId, let dev = store.devices.first(where: { $0.id == did }) {
            let currentAliases = GroupPrefs.map(aliasesRaw)
            let originalName = store.originalDeviceName(for: did) ?? dev.name
            promptBackdrop {
                GroupNamePrompt(
                    title: L10n.tr("重命名设备", "Rename Device"),
                    name: currentAliases[did] ?? dev.name,
                    placeholder: originalName,
                    onReset: currentAliases[did] != nil ? {
                        var aliases = GroupPrefs.map(aliasesRaw)
                        aliases.removeValue(forKey: did)
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            aliasesRaw = GroupPrefs.encode(aliases)
                            store.applyDeviceAliases(aliases)
                            layoutUI.renamingDeviceId = nil
                        }
                    } : nil
                ) { name in
                    var aliases = GroupPrefs.map(aliasesRaw)
                    // Saving the original Mi Home name clears the alias.
                    aliases[did] = name == originalName ? nil : name
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        aliasesRaw = GroupPrefs.encode(aliases)
                        store.applyDeviceAliases(aliases)
                        layoutUI.renamingDeviceId = nil
                    }
                } onCancel: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { layoutUI.renamingDeviceId = nil }
                }
            }
        } else if let gid = layoutUI.renamingGroupId, let group = groups.first(where: { $0.id == gid }) {
            promptBackdrop {
                GroupNamePrompt(title: L10n.tr("重命名分组", "Rename Group"), name: group.name) { name in
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        groupsRaw = GroupPrefs.encode(groups.map { $0.id == gid ? DeviceGroup(id: gid, name: name) : $0 })
                        layoutUI.renamingGroupId = nil
                    }
                } onCancel: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { layoutUI.renamingGroupId = nil }
                }
            }
        }
    }

    private func promptBackdrop<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        layoutUI.newGroupForDevice = nil
                        layoutUI.renamingGroupId = nil
                        layoutUI.renamingDeviceId = nil
                    }
                }
                .transition(.opacity)
            content()
                .transition(.scale(scale: 0.88).combined(with: .opacity))
        }
    }

    // MARK: - Container Drag (survives card reordering)

    /// Lives on the tile container, not on a card: a card's own gesture is cancelled the moment the
    /// card moves to a new slot, which froze the drag right after each swap.
    private var tileDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(TileSpace.name))
            .onChanged { d in
                let moved = hypot(d.translation.width, d.translation.height)
                if draggingId == nil {
                    if isEditingLayout {
                        if moved > 3, let id = cardId(at: d.startLocation) { beginDrag(id, at: d.startLocation) }
                    } else if pressTask == nil, !pressCancelled, let id = cardId(at: d.startLocation) {
                        let start = d.startLocation
                        pressTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            guard !Task.isCancelled else { return }
                            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                store.expandedDeviceId = nil
                                isEditingLayout = true
                            }
                            beginDrag(id, at: start)
                        }
                    } else if moved > 8 {
                        // Moving before the hold completes is an ordinary drag (e.g. dimming).
                        pressTask?.cancel()
                        pressCancelled = true
                    }
                }
                if let id = draggingId {
                    dragLocation = d.location
                    swapIfNeeded(dragged: id, at: d.location)
                }
            }
            .onEnded { _ in
                pressTask?.cancel()
                pressTask = nil
                pressCancelled = false
                lastSwapTarget = nil
                guard draggingId != nil else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    draggingId = nil
                    dragLocation = nil
                }
            }
    }

    private func cardId(at point: CGPoint) -> String? {
        tileFrames.first { $0.value.contains(point) }?.key
    }

    private func beginDrag(_ id: String, at start: CGPoint) {
        let origin = tileFrames[id]?.origin ?? start
        grabOffset = CGSize(width: start.x - origin.x, height: start.y - origin.y)
        dragLocation = start
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { draggingId = id }
    }

    /// Decides where the dragged card should go: before or after the card under the pointer (top
    /// half / left half means before), or first when the pointer is above every card. The same
    /// slot never fires twice in a row and swaps are at least 0.25s apart, since frames animate
    /// after each move and could otherwise ping-pong.
    private func swapIfNeeded(dragged: String, at location: CGPoint) {
        guard Date().timeIntervalSince(lastSwapAt) > 0.25 else { return }
        let others = tileFrames.filter { $0.key != dragged }
        guard !others.isEmpty else { return }

        let target: String
        let after: Bool
        if let top = others.min(by: { $0.value.minY < $1.value.minY }), location.y < top.value.minY {
            target = top.key
            after = false
        } else if let hit = others.first(where: { $0.value.contains(location) }) {
            let f = hit.value
            target = hit.key
            if location.y < f.minY + f.height * 0.3 {
                after = false
            } else if location.y > f.maxY - f.height * 0.3 {
                after = true
            } else {
                after = location.x > f.midX
            }
        } else {
            return
        }

        let slot = "\(target)|\(after)"
        guard slot != lastSwapTarget else { return }
        lastSwapTarget = slot
        lastSwapAt = Date()
        // Dropping onto a card in another section (常用 / a group / ungrouped) moves the card into it.
        adoptSection(of: target, for: dragged)
        moveDevice(dragged, relativeTo: target, after: after)
    }

    /// Offset that keeps the picked-up card under the pointer even after its slot moves.
    private func dragOffset(for id: String) -> CGSize {
        guard draggingId == id, let loc = dragLocation, let frame = tileFrames[id] else { return .zero }
        return CGSize(width: loc.x - grabOffset.width - frame.minX, height: loc.y - grabOffset.height - frame.minY)
    }

    /// Moves `dragged` to `target`'s slot in the saved order (seeded from the full device list).
    private var currentOrder: [String] { liveOrder ?? DeviceLayoutPrefs.decodeOrder(orderRaw) }

    private func moveDevice(_ dragged: String, relativeTo target: String, after: Bool) {
        var order = currentOrder
        for id in store.devices.map(\.id) where !order.contains(id) { order.append(id) }
        guard order.contains(dragged), order.contains(target) else { return }
        order.removeAll { $0 == dragged }
        guard let t = order.firstIndex(of: target) else { return }
        order.insert(dragged, at: after ? t + 1 : t)
        guard order != currentOrder else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            liveOrder = order
            if store.favoriteDeviceIds.contains(dragged) {
                store.favoriteOrder = order.filter { store.favoriteDeviceIds.contains($0) }
            }
        }
        orderRaw = DeviceLayoutPrefs.encodeOrder(order)
    }

    private func cycleSize(_ device: SmartDevice) {
        let next: TileSize
        switch tileSize(device) {
        case .half: next = .full
        case .full: next = .panel
        case .panel, .auto: next = .half
        }
        var sizes = liveSizes ?? DeviceLayoutPrefs.decode(tileSizesRaw)
        sizes[DeviceLayoutPrefs.scopedKey(id: device.id, scope: layoutScope)] = next
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { liveSizes = sizes }
        tileSizesRaw = DeviceLayoutPrefs.encode(sizes)
    }

    private var doneEditingButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isEditingLayout = false
                draggingId = nil
            }
        } label: {
            Text(L10n.tr("完成", "Done")).font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(PillActionButtonStyle(isSelected: true))
        .keyboardShortcut(.defaultAction)
    }

    private func usesClimatePanel(_ device: SmartDevice) -> Bool {
        tileSize(device) != .half
    }

    /// The device's card size with `.auto` resolved; full and panel sizes take a whole row.
    private func tileSize(_ device: SmartDevice) -> TileSize {
        DeviceLayoutPrefs.resolved(
            liveSizes.map { DeviceLayoutPrefs.lookup($0, id: device.id, scope: layoutScope) }
                ?? DeviceLayoutPrefs.cachedSize(raw: tileSizesRaw, id: device.id, scope: layoutScope),
            device: device,
            compactGrid: store.isCompactGridMode,
            climatePanel: climatePanelModule
        )
    }

    // MARK: - Device Collection (flow layout with per-card spans)

    /// Column span out of 6 for each device: half = 3, full/panel = 6; Bento alternates 4+2 and 2+2+2.
    private func spans(for devices: [SmartDevice]) -> [String: Int] {
        var result: [String: Int] = [:]
        if skin == .bento && store.isCompactGridMode {
            var pattern: [Int] = []
            for dev in devices {
                if store.expandedDeviceId == dev.id || usesClimatePanel(dev) {
                    result[dev.id] = 6
                    pattern = []
                    continue
                }
                if pattern.isEmpty { pattern = result.count % 2 == 0 ? [4, 2] : [2, 2, 2] }
                result[dev.id] = pattern.removeFirst()
            }
            return result
        }
        for dev in devices {
            let size = tileSize(dev)
            result[dev.id] = (size == .half && store.expandedDeviceId != dev.id) ? 3 : 6
        }
        return result
    }

    @ViewBuilder
    private func deviceCollectionView(
        devices: [SmartDevice],
        showRoomBadge: Bool,
        quickIndexMap: [String: Int]
    ) -> some View {
        let aliases = GroupPrefs.map(aliasesRaw)
        let ordered = DeviceLayoutPrefs.apply(order: currentOrder, to: devices).map { dev -> SmartDevice in
            guard let alias = aliases[dev.id] else { return dev }
            var d = dev
            d.name = alias
            return d
        }
        let spanMap = spans(for: ordered)
        let bento = skin == .bento && store.isCompactGridMode
        // Every card is its own child keyed by device id, so a reorder slides cards instead of rebuilding rows.
        TileFlowLayout(spacing: 7) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, dev in
                let span = spanMap[dev.id] ?? 6
                DeviceCardView(
                    device: dev,
                    store: store,
                    showRoomBadge: showRoomBadge,
                    isCompactTile: span < 6,
                    quickIndex: quickIndexMap[dev.id],
                    isBentoTile: bento && span < 6
                )
                .frame(height: bento && span < 6 ? 92 : nil)
                .frame(maxHeight: .infinity, alignment: .top)
                .modifier(editable(dev))
                // Measured outside the jiggle/drag effects: those transforms would otherwise change the
                // reported frame every animation frame and re-layout the whole panel continuously.
                .background {
                    GeometryReader { geo in
                        let f = geo.frame(in: .named(TileSpace.name))
                        Color.clear.preference(
                            key: TileFramesKey.self,
                            value: [dev.id: CGRect(x: f.minX.rounded(), y: f.minY.rounded(), width: f.width.rounded(), height: f.height.rounded())]
                        )
                    }
                }
                .staggerIn(index)
                .layoutValue(key: TileSpanKey.self, value: span)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: ordered.map { "\($0.id):\(spanMap[$0.id] ?? 6)" })
        .id(skin.isClassic ? "rows" : "rows_\(store.selectedRoomId ?? "all")")
    }

    // MARK: - 1. Hero Header & Live Environment Chips

    private var topHeroHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if skin.isClassic {
                            Image(systemName: store.activeDeviceCount > 0 ? "house.fill" : "house")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(
                                    store.activeDeviceCount > 0
                                        ? (skin.isClassic ? (colorScheme == .dark ? Color.orange : Color(red: 0.86, green: 0.42, blue: 0.04)) : skin.palette.accent)
                                        : Color.secondary
                                )
                        }

                        homeTitle

                        if store.homeBackend == .demo {
                            Text(L10n.tr("演示模式", "Demo"))
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.16), in: Capsule(style: .continuous))
                                .skinHelp(L10n.tr(
                                    "正在使用内置虚拟设备，完全离线，不联网。可在设置里切回真实账号。",
                                    "Using built-in virtual devices, fully offline. Switch back to a real account in Settings."
                                ))
                        }
                    }

                    Text(statusSummaryText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                Button {
                    withAnimation(AppleMotion.snappySpring) {
                        store.presentAssistantBar(startVoice: true)
                    }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.78))
                        .frame(width: 26, height: 24)
                        .adaptiveGlass(in: Capsule(style: .continuous), interactive: true)
                        .listeningPulse(SpeechInputController.shared.isListening, color: skin.isClassic ? .accentColor : skin.palette.accent)
                }
                .buttonStyle(.plain)
                .skinHelp(L10n.tr("语音指令：点击直接说话控制设备（快捷键 V）", "Voice command: click to speak (shortcut V)"))

                Button {
                    withAnimation(AppleMotion.snappySpring) {
                        if store.isShowingAssistantBar {
                            store.dismissAssistantBar()
                        } else {
                            store.presentAssistantBar()
                        }
                    }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(store.isShowingAssistantBar ? skinOnAccent : Color.primary.opacity(0.78))
                        .frame(width: 26, height: 24)
                        .background {
                            if store.isShowingAssistantBar {
                                Capsule(style: .continuous)
                                    .fill(skinAccentFill)
                                    .shadowIf(!skin.isClassic && (skin.palette.neumorphic || skin.palette.glow), color: skin.palette.accent.opacity(0.32), radius: 4, y: 1.5)
                            }
                        }
                        .modifier(
                            SkinChipSurface(
                                shape: Capsule(style: .continuous),
                                tint: store.isShowingAssistantBar ? .accentColor.opacity(0.45) : nil,
                                interactive: true,
                                clear: false,
                                isHidden: !skin.isClassic && store.isShowingAssistantBar
                            )
                        )
                }
                .buttonStyle(.plain)
                .skinHelp(L10n.tr("AI 指令：用一句话控制设备（快捷键 /）", "AI command: control devices with natural language (shortcut /)"))

                if isEditingLayout {
                    doneEditingButton
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else if !store.allOffTargets.isEmpty {
                    // Every skin asks for a 0.6 s hold, and the label says what will be switched off (#23).
                    let count = store.allOffTargets.count
                    HoldToConfirmButton(
                        title: store.allOffRoomName.map { L10n.tr("全关·\($0)", "All Off · \($0)") } ?? L10n.tr("全关", "All Off"),
                        count: count,
                        onConfirm: {
                            withAnimation(AppleMotion.snappySpring) { store.turnAllOff() }
                        },
                        onTap: {
                            store.showToast(
                                L10n.tr("按住 0.6 秒关闭这 \(count) 台（插座、扫地机默认不参与）", "Hold 0.6s to turn off these \(count) (plugs and vacuums are left out by default)"),
                                isError: false
                            )
                        }
                    )
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }

            if !store.environmentReadings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    AdaptiveGlassContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(store.environmentReadings) { env in
                                environmentChip(env)
                            }
                            if store.totalPowerWatts >= 1 {
                                powerChip(watts: store.totalPowerWatts)
                            }
                        }
                    }
                    .padding(6)
                }
                .padding(-6)
            }
        }
    }

    /// Dashboard title; with several Mi Homes it becomes a menu that switches between them.
    @ViewBuilder
    private var homeTitle: some View {
        if store.homes.count > 1 {
            Menu {
                Button {
                    store.selectMiHome(nil)
                } label: {
                    Label(L10n.tr("全部家庭", "All Homes"), systemImage: store.selectedMiHomeId == nil ? "checkmark" : "")
                }
                Divider()
                ForEach(store.homes) { home in
                    Button {
                        store.selectMiHome(home.id)
                    } label: {
                        Label(
                            "\(home.name)  ·  \(home.deviceCount)",
                            systemImage: store.selectedMiHomeId == home.id ? "checkmark" : ""
                        )
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedHomeTitle)
                        .font(.system(size: skin.isClassic ? 15 : 17, weight: .bold))
                        .tracking(-0.2)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .skinHelp(L10n.tr("切换家庭", "Switch home"))
        } else {
            Text(store.homeName)
                .font(.system(size: skin.isClassic ? 15 : 17, weight: .bold))
                .tracking(-0.2)
        }
    }

    private var selectedHomeTitle: String {
        if let id = store.selectedMiHomeId, let home = store.homes.first(where: { $0.id == id }) {
            return home.name
        }
        return store.homeName
    }

    private func powerChip(watts: Double) -> some View {
        let capsule = Capsule(style: .continuous)
        return HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? Color.green : Color(red: 0.08, green: 0.54, blue: 0.22))

            Text(String(format: "%.0fW", watts))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .adaptiveGlass(in: capsule)
        .overlay {
            if skin.isClassic {
                capsule
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.48), lineWidth: 0.7)
            }
        }
    }

    private func environmentChip(_ env: EnvironmentReading) -> some View {
        let capsule = Capsule(style: .continuous)
        return HStack(spacing: 5) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? Color.teal : Color(red: 0.04, green: 0.48, blue: 0.52))

            Text(L10n.displayRoomName(env.label))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.88))

            if let t = env.temperature {
                Text(String(format: "%.1f°", t))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }

            if let h = env.humidity {
                Text(String(format: "· %.0f%%", h))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.68))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 9.5)
        .padding(.vertical, 4.5)
        .adaptiveGlass(in: capsule)
        .overlay {
            if skin.isClassic {
                capsule
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.48), lineWidth: 0.7)
            }
        }
    }

    private var statusSummaryText: String {
        if isEditingLayout {
            return L10n.tr("拖动卡片排序 · 点角标改大小", "Drag to reorder · tap badge to resize")
        }
        if store.activeDeviceCount > 0 {
            return L10n.tr(
                "\(store.activeDeviceCount) 台设备开启中 · 共 \(store.onlineDeviceCount) 台在线",
                "\(store.activeDeviceCount) active · \(store.onlineDeviceCount) online"
            )
        }
        return L10n.tr(
            "全屋设备待机 · \(store.onlineDeviceCount) 台实时在线",
            "All standby · \(store.onlineDeviceCount) online"
        )
    }

    // MARK: - 1B. Quick Actions & HA Scenes Strip

    private var quickActionsAndScenesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            AdaptiveGlassContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(QuickAction.allCases) { action in
                        Button {
                            withAnimation(AppleMotion.snappySpring) {
                                store.executeQuickAction(action)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: action.sfSymbolName)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(
                                        colorScheme == .dark
                                            ? Color.orange
                                            : Color(red: 0.82, green: 0.38, blue: 0.04)
                                    )
                                Text(action.title)
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .buttonStyle(PillActionButtonStyle())
                    }

                    if !store.scenes.isEmpty {
                        Divider()
                            .frame(height: 14)
                            .padding(.horizontal, 2)

                        ForEach(store.scenes) { scene in
                            Button {
                                withAnimation(AppleMotion.snappySpring) {
                                    store.triggerScene(scene)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: scene.iconName)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                    Text(scene.name)
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .buttonStyle(PillActionButtonStyle())
                        }
                    }
                }
            }
            .padding(6)
        }
        .padding(-6)
    }

    // MARK: - 2. Room Filter Strip & Grid Toggle

    private var roomPillsRow: some View {
        HStack(spacing: 5) {
            roomPill(title: L10n.tr("全部", "All"), roomId: nil)
            ForEach(store.rooms) { room in
                roomPill(title: L10n.displayRoomName(room.name), roomId: room.id)
                    .id(room.id)
            }
        }
    }

    private var roomFilterBar: some View {
        HStack(spacing: 6) {
            if skin.isClassic {
                ScrollView(.horizontal, showsIndicators: false) {
                    AdaptiveGlassContainer(spacing: 5) {
                        roomPillsRow
                            .padding(.trailing, 10)
                            .padding(.leading, 6)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.leading, -6)
                .padding(.vertical, -6)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.91),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            } else {
                // The track sits outside the scroll view and clips it, so the first pill's rounded
                // edge can never be cut by the scroll view's own bounds or offset.
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 0, height: 1).id("roomsStart")
                            // Extra side inset keeps the end pills clear of the track's curved ends.
                            roomPillsRow.padding(.vertical, 3).padding(.horizontal, 6)
                        }
                    }
                    .defaultScrollAnchor(.leading)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    // The menu-bar window restores a stale horizontal offset on reopen; snap back to
                    // the start (or the selected room) so the first pill is not half scrolled out.
                    // Only on a real reopen: any window becoming key (menus, submenus) used to rerun this
                    // and re-layout the strip while a context menu was open.
                    .onChange(of: isPresented) { _, shown in
                        guard shown else { return }
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) {
                            // Selected room goes to the middle, never under the faded left edge.
                            if let id = store.selectedRoomId { proxy.scrollTo(id, anchor: .center) } else { proxy.scrollTo("roomsStart", anchor: .leading) }
                        }
                    }
                    .onAppear { proxy.scrollTo("roomsStart", anchor: .leading) }
                    // Keep the chosen room fully visible; tapping a half-hidden one slides it in.
                    .onChange(of: store.selectedRoomId) { _, id in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            proxy.scrollTo(id ?? "roomsStart", anchor: .center)
                        }
                    }
                    // Soft fade at both ends instead of letters being sliced by the track edge.
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.0), location: 0.0),
                                .init(color: .black, location: 0.035),
                                .init(color: .black, location: 0.86),
                                .init(color: .black.opacity(0.0), location: 1.0)
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                }
                .clipShape(Capsule(style: .continuous))
                .background(Capsule(style: .continuous).fill(skin.palette.chip))
                .overlay(Capsule(style: .continuous).stroke(skin.palette.line, lineWidth: 0.8))
            }

            AdaptiveGlassContainer(spacing: 5) {
                HStack(spacing: 5) {
                    Button {
                        withAnimation(AppleMotion.snappySpring) {
                            store.isCompactGridMode.toggle()
                        }
                    } label: {
                        Image(systemName: store.isCompactGridMode ? "rectangle.grid.2x2.fill" : "rectangle.grid.1x2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(store.isCompactGridMode ? skinOnAccent : Color.primary.opacity(0.78))
                            .frame(width: 26, height: 24)
                            .background {
                                if store.isCompactGridMode {
                                    Capsule(style: .continuous)
                                        .fill(skinAccentFill)
                                        .shadowIf(!skin.isClassic && (skin.palette.neumorphic || skin.palette.glow), color: skin.palette.accent.opacity(0.32), radius: 4, y: 1.5)
                                }
                            }
                            .modifier(
                                SkinChipSurface(
                                    shape: Capsule(style: .continuous),
                                    tint: store.isCompactGridMode ? .accentColor.opacity(0.45) : nil,
                                    interactive: true,
                                    clear: false,
                                    isHidden: !skin.isClassic && store.isCompactGridMode
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .skinHelp(
                        store.isCompactGridMode
                            ? L10n.tr("当前：双列紧凑磁贴（点击切换单列）", "2-column compact tiles (click for single column)")
                            : L10n.tr("点击切换双列紧凑磁贴视图", "Switch to 2-column compact tiles")
                    )

                    Button {
                        withAnimation(AppleMotion.snappySpring) {
                            store.hideOfflineDevices.toggle()
                        }
                    } label: {
                        Image(systemName: store.hideOfflineDevices ? "wifi" : "wifi.slash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(store.hideOfflineDevices ? skinOnAccent : Color.primary.opacity(0.78))
                            .frame(width: 26, height: 24)
                            .background {
                                if store.hideOfflineDevices {
                                    Capsule(style: .continuous)
                                        .fill(skinAccentFill)
                                        .shadowIf(!skin.isClassic && (skin.palette.neumorphic || skin.palette.glow), color: skin.palette.accent.opacity(0.32), radius: 4, y: 1.5)
                                }
                            }
                            .modifier(
                                SkinChipSurface(
                                    shape: Capsule(style: .continuous),
                                    tint: store.hideOfflineDevices ? .accentColor.opacity(0.45) : nil,
                                    interactive: true,
                                    clear: false,
                                    isHidden: !skin.isClassic && store.hideOfflineDevices
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .skinHelp(
                        store.hideOfflineDevices
                            ? L10n.tr("当前只显示在线设备（点击显示全部）", "Showing online devices only (click to show all)")
                            : L10n.tr("点击隐藏未通电/离线设备", "Hide offline/unplugged devices")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func roomPill(title: String, roomId: String?) -> some View {
        let isSelected = (store.selectedRoomId == roomId)
        if skin.isClassic {
            classicRoomPill(title: title, roomId: roomId, isSelected: isSelected)
        } else {
            let p = skin.palette
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                    store.selectedRoomId = roomId
                }
            } label: {
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? p.onAccent : p.muted)
                    .padding(.horizontal, 10.5)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            Capsule(style: .continuous)
                                .fill(p.accentGradient)
                                .matchedGeometryEffect(id: "roomPill", in: roomPillNamespace)
                        }
                    }
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(PressableCardButtonStyle(scaleAmount: 0.94))
        }
    }

    private func classicRoomPill(title: String, roomId: String?, isSelected: Bool) -> some View {
        Button(title) {
            withAnimation(AppleMotion.snappySpring) {
                store.selectedRoomId = roomId
            }
        }
        .buttonStyle(PillActionButtonStyle(isSelected: isSelected, tintColor: .accentColor))
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.80))
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 3)
        .padding(.bottom, -3)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            if case .disconnected = store.connectionStatus {
                Text(
                    store.homeBackend == .xiaomiCloud
                        ? L10n.tr("尚未登录米家云端账号", "Not signed in to Xiaomi Cloud")
                        : L10n.tr("尚未连接到 Home Assistant", "Not connected to Home Assistant")
                )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(
                    store.homeBackend == .xiaomiCloud
                        ? L10n.tr("无需额外部署服务器，使用手机「米家」App 扫码即可同步设备", "Scan with the Mi Home app on your phone to sync devices without a server")
                        : L10n.tr("点击下方按钮配置服务器地址与令牌，或切换为手机米家扫码直连", "Configure your server URL and token below, or switch to Xiaomi Cloud QR login")
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Button(L10n.tr("打开新手引导", "Setup Guide")) {
                        withAnimation(AppleMotion.snappySpring) {
                            store.reopenOnboarding()
                        }
                    }
                    .buttonStyle(PillActionButtonStyle(isSelected: true, tintColor: .accentColor))

                    Button {
                        presentSettingsWindow()
                    } label: {
                        Text(L10n.tr("偏好设置", "Preferences"))
                    }
                    .buttonStyle(PillActionButtonStyle())
                }
                .padding(.top, 2)
            } else {
                Text(
                    store.hideOfflineDevices
                        ? L10n.tr("该房间暂无通电在线的设备", "No online devices in this room")
                        : L10n.tr("正在同步设备列表…", "Syncing devices…")
                )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                if store.hideOfflineDevices {
                    Button(L10n.tr("显示离线设备", "Show Offline Devices")) {
                        withAnimation(AppleMotion.snappySpring) {
                            store.hideOfflineDevices = false
                        }
                    }
                    .buttonStyle(PillActionButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Home Assistant Address Question (#18)

    /// The app never moves the token to a new address by itself; it asks here first.
    private func haAddressSuggestionBanner(_ instance: HADiscoveredInstance) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let place = instance.locationName.isEmpty || instance.locationName == "Home Assistant"
            ? instance.hostAndPort
            : "\(instance.locationName)（\(instance.hostAndPort)）"
        return VStack(alignment: .leading, spacing: 6) {
            Label(
                L10n.tr("连不上 Home Assistant。发现了 \(place)，要切换过去吗？", "Can't reach Home Assistant. Found \(place). Switch to it?"),
                systemImage: "questionmark.circle.fill"
            )
            .font(.system(size: 11.5, weight: .medium))
            Text(L10n.tr(
                "切换后会把访问令牌发给这个地址。不认识这个地址就点「不切换」。",
                "Switching sends your access token to this address. If you don't recognize it, choose Don't Switch."
            ))
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(L10n.tr("切换", "Switch")) {
                    withAnimation(AppleMotion.snappySpring) { store.acceptHAAddressSuggestion() }
                }
                .buttonStyle(PillActionButtonStyle(isSelected: true, tintColor: .accentColor))
                Button(L10n.tr("不切换", "Don't Switch")) {
                    withAnimation(AppleMotion.snappySpring) { store.dismissHAAddressSuggestion() }
                }
                .buttonStyle(PillActionButtonStyle())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(in: shape)
    }

    // MARK: - 3. Floating Undo & Toast Banner

    @ViewBuilder
    private var overlayNotifications: some View {
        if let banner = store.undoBanner {
            let bannerShape = RoundedRectangle(cornerRadius: 13, style: .continuous)
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))

                Text(banner.title)
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Button(L10n.tr("撤销", "Undo")) {
                    withAnimation(AppleMotion.snappySpring) {
                        store.undoTurnAllOff()
                    }
                }
                .buttonStyle(PillActionButtonStyle(isSelected: true, tintColor: Color(red: 0.90, green: 0.44, blue: 0.08)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .adaptiveGlass(in: bannerShape)
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 14)
            .padding(.bottom, 42)
            // #53: reading the banner must not cost the undo. Leaving restarts the full window.
            .onHover { hovering in
                if hovering {
                    store.pauseUndoBannerCountdown()
                } else {
                    store.resumeUndoBannerCountdown()
                }
            }
            .transition(AppleMotion.drawerTransition)
        } else if let toast = store.toastNotice {
            let toastShape = Capsule(style: .continuous)
            HStack(spacing: 6) {
                Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(toast.isError ? .orange : .green)
                    .font(.system(size: 11.5))

                Text(toast.message)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .adaptiveGlass(in: toastShape)
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
            .padding(.bottom, 42)
            .transition(AppleMotion.drawerTransition)
        }
    }

    // MARK: - 4. Footer Status Bar

    private var footerBar: some View {
        HStack(spacing: 8) {
            BreathingDot(
                color: skin.isClassic ? statusDotColor : (statusDotColor == .green ? skin.palette.ok : statusDotColor),
                animate: !skin.isClassic && statusDotColor == .green
            )
            .id(statusDotColor)

            Text(statusFooterLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if let release = store.updateState.badgeRelease {
                Button {
                    if store.updateState.isReadyToRelaunch {
                        withAnimation(AppleMotion.snappySpring) {
                            store.confirmRelaunchForUpdate()
                        }
                    } else {
                        presentSettingsWindow()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(
                            systemName: store.updateState.isReadyToRelaunch
                                ? "arrow.triangle.2.circlepath.circle.fill"
                                : "arrow.down.circle.fill"
                        )
                        .font(.system(size: 10.5, weight: .semibold))
                        Text(
                            store.updateState.isReadyToRelaunch
                                ? L10n.tr("重启更新 v\(release.version)", "Relaunch v\(release.version)")
                                : "v\(release.version)"
                        )
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                    }
                }
                .buttonStyle(
                    PillActionButtonStyle(
                        isSelected: true,
                        tintColor: store.updateState.isReadyToRelaunch ? .green : .accentColor
                    )
                )
                .skinHelp(
                    store.updateState.isReadyToRelaunch
                        ? L10n.tr("点击立即重启并完成 v\(release.version) 更新", "Click to relaunch and finish updating to v\(release.version)")
                        : L10n.tr("发现新版本 v\(release.version)，点击前往更新", "New version v\(release.version) available")
                )
            }

            // #53: once the banner is gone the assistant action is still undoable for ten minutes.
            if store.undoBanner == nil,
               !store.isShowingAssistantBar,
               UndoAvailabilityTracker.shared.isAvailable {
                Button {
                    store.presentAssistantBar()
                    Task { await UndoAvailabilityTracker.shared.performUndo(store: store) }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.72))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .skinHelp(L10n.tr("撤销上一步（10 分钟内有效）", "Undo the last assistant action (valid for 10 minutes)"))
            }

            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .skinHelp(L10n.tr("立即同步最新状态", "Refresh device states now"))

            Button {
                presentSettingsWindow()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .skinHelp(L10n.tr("偏好设置与连接配置（⌘,）", "Preferences & connection settings (⌘,)"))
        }
    }

    /// `openSettings` is the supported way to reveal the Settings scene from a MenuBarExtra.
    private func presentSettingsWindow() {
        SettingsWindowOpener.shared.show()
    }

    private var statusDotColor: Color {
        switch store.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        }
    }

    private var statusFooterLabel: String {
        switch store.connectionStatus {
        case .connected:
            if store.homeBackend == .demo {
                return L10n.tr("演示模式 · 内置虚拟设备（完全离线）", "Demo Mode · Built-in virtual devices (offline)")
            }
            if store.homeBackend == .xiaomiCloud {
                return L10n.tr("\(store.serverHostSummary) · Miot 直连", "\(store.serverHostSummary) · MIoT Direct")
            }
            return L10n.tr("HA 实时连接 (\(store.serverHostSummary))", "HA Live (\(store.serverHostSummary))")
        case .connecting:
            return L10n.tr("正在连接 (\(store.serverHostSummary))…", "Connecting (\(store.serverHostSummary))…")
        case .disconnected(let reason):
            return L10n.tr("未连接：\(reason)", "Disconnected: \(reason)")
        }
    }
}
