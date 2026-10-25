import SwiftUI
import AVFoundation
import Speech
import MijiaCore

// MARK: - Nonisolated ObjC Callback Bridge (prevents Swift 6 @MainActor thunk traps on TCC/Audio threads)

private nonisolated enum SpeechRuntimeBridge {
    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static func installAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onEvent: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = (error != nil)
            onEvent(transcript, isFinal, hasError)
        }
    }
}

// MARK: - Live Speech Recognizer (macOS Speech + AVAudioEngine)

@Observable
@MainActor
public final class SpeechInputController {
    public static let shared = SpeechInputController()

    public var draft: String = ""
    public private(set) var isListening: Bool = false
    public private(set) var isHoldToTalk: Bool = false
    public private(set) var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimerTask: Task<Void, Never>?
    private var holdReleaseTask: Task<Void, Never>?
    private var hasCapturedSpeech: Bool = false
    private var isStarting: Bool = false

    public init() {}

    public func setPreviewState(isListening: Bool, isHoldToTalk: Bool, draft: String) {
        self.isListening = isListening
        self.isHoldToTalk = isHoldToTalk
        self.draft = draft
    }

    public var hasVoicePermissions: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    public func requestPermissions() async -> Bool {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        let micAllowed = await SpeechRuntimeBridge.requestMicrophoneAccess()
        guard micAllowed else { return false }
        let speechStatus = await SpeechRuntimeBridge.requestSpeechAuthorization()
        return speechStatus == .authorized
    }

    public func toggle(store: HomeStore) {
        if isListening {
            stop(andSubmit: hasCapturedSpeech, store: store)
        } else {
            Task { await start(holdMode: false, store: store) }
        }
    }

    public func startHoldToTalk(store: HomeStore) {
        holdReleaseTask?.cancel()
        holdReleaseTask = nil
        if isListening {
            isHoldToTalk = true
            silenceTimerTask?.cancel()
            silenceTimerTask = nil
            return
        }
        Task { await start(holdMode: true, store: store) }
    }

    public func finishHoldToTalk(store: HomeStore) {
        guard isHoldToTalk || isListening || isStarting else { return }
        holdReleaseTask?.cancel()
        holdReleaseTask = Task { @MainActor [weak self] in
            // Allow 320ms after mouse release for SFSpeechRecognizer to flush any syllables spoken while held.
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled, let self else { return }
            let hasText = self.hasCapturedSpeech || !self.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if self.isListening {
                if hasText {
                    // User spoke while holding the menu bar icon (Push-to-Talk): stop and execute immediately.
                    self.stop(andSubmit: true, store: store)
                } else {
                    // User long-pressed the menu bar icon to summon voice input and released before speaking:
                    // seamlessly transition to hands-free listening with 1.1s silence auto-submit.
                    self.isHoldToTalk = false
                }
            } else {
                self.isHoldToTalk = false
            }
        }
    }

    public func start(holdMode: Bool, store: HomeStore) async {
        guard !isListening, !isStarting else {
            if holdMode { isHoldToTalk = true }
            return
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            errorMessage = L10n.tr("语音识别仅在打包后的 App 中可用", "Speech recognition is only available in the packaged App")
            return
        }
        isStarting = true
        defer { isStarting = false }

        errorMessage = nil
        hasCapturedSpeech = false
        isHoldToTalk = holdMode
        if holdMode {
            draft = ""
        }

        let micAllowed = await SpeechRuntimeBridge.requestMicrophoneAccess()
        guard micAllowed else {
            isHoldToTalk = false
            errorMessage = L10n.tr(
                "请在「系统设置 → 隐私与安全性 → 麦克风」中允许 MenuBarMijia",
                "Please allow MenuBarMijia in System Settings → Privacy & Security → Microphone"
            )
            return
        }

        let speechStatus = await SpeechRuntimeBridge.requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            isHoldToTalk = false
            errorMessage = L10n.tr(
                "请在「系统设置 → 隐私与安全性 → 语音识别」中允许 MenuBarMijia",
                "Please allow MenuBarMijia in System Settings → Privacy & Security → Speech Recognition"
            )
            return
        }

        let preferredLocale = Locale(identifier: store.effectiveLanguage.speechLocaleIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: preferredLocale)
                ?? SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
                ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            isHoldToTalk = false
            errorMessage = L10n.tr("当前系统语音识别服务暂不可用", "System speech recognition is currently unavailable")
            return
        }

        stop(andSubmit: false, store: store)
        isHoldToTalk = holdMode && ((NSEvent.pressedMouseButtons & 0x3) != 0)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Privacy option: keep recognition on this Mac when the system supports it.
        if store.prefersOnDeviceSpeech && recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            isHoldToTalk = false
            errorMessage = L10n.tr("未检测到可用麦克风输入设备", "No available microphone input device detected")
            return
        }

        SpeechRuntimeBridge.installAudioTap(on: inputNode, format: format, request: request)

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            isHoldToTalk = false
            errorMessage = L10n.tr(
                "麦克风启动失败：\(error.localizedDescription)",
                "Microphone failed to start: \(error.localizedDescription)"
            )
            return
        }

        self.audioEngine = engine
        self.recognitionRequest = request
        self.isListening = true

        self.recognitionTask = SpeechRuntimeBridge.startRecognitionTask(
            recognizer: recognizer,
            request: request
        ) { [weak self, weak store] transcript, isFinal, hasError in
            Task { @MainActor [weak self, weak store] in
                guard let self, let store, self.isListening else { return }
                if let transcript {
                    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        self.hasCapturedSpeech = true
                        self.draft = trimmed
                        if !self.isHoldToTalk {
                            self.scheduleSilenceAutoSubmit(store: store)
                        }
                    }
                }
                if isFinal || hasError {
                    if !self.isHoldToTalk {
                        self.stop(andSubmit: self.hasCapturedSpeech, store: store)
                    }
                }
            }
        }
    }

    public func stop(andSubmit: Bool, store: HomeStore?) {
        silenceTimerTask?.cancel()
        silenceTimerTask = nil
        holdReleaseTask?.cancel()
        holdReleaseTask = nil

        let textToSubmit = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldSubmit = andSubmit && (hasCapturedSpeech || !textToSubmit.isEmpty)
        hasCapturedSpeech = false
        isListening = false
        isHoldToTalk = false

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        if shouldSubmit, let store {
            submit(store: store)
        }
    }

    public func submit(store: HomeStore) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, store.assistantState != .thinking else { return }
        Task { @MainActor in
            await store.runAssistantCommand(text)
            if case .done = store.assistantState {
                self.draft = ""
            }
        }
    }

    private func scheduleSilenceAutoSubmit(store: HomeStore) {
        silenceTimerTask?.cancel()
        // Wait 1.1s after the last recognized syllable before auto-submitting the command.
        silenceTimerTask = Task { @MainActor [weak self, weak store] in
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled, let self, let store, self.isListening, !self.isHoldToTalk, self.hasCapturedSpeech else { return }
            self.stop(andSubmit: true, store: store)
        }
    }
}

// MARK: - AI Command Bar (top of the main dashboard)

struct AssistantCommandBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let store: HomeStore

    @Bindable private var speech = SpeechInputController.shared
    @State private var lastHandledVoiceRequest: Int = 0
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let _ = store.effectiveLanguage
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: speech.isListening ? "waveform" : "sparkles")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(speech.isListening ? Color.red : Color.accentColor)
                    .symbolEffect(.variableColor.iterative, isActive: speech.isListening)
                    .symbolEffect(.pulse, isActive: store.assistantState == .thinking)

                TextField(
                    placeholderText,
                    text: $speech.draft
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .focused($isFieldFocused)
                .onSubmit {
                    if speech.isListening {
                        speech.stop(andSubmit: false, store: store)
                    }
                    speech.submit(store: store)
                }

                micButton

                trailingAccessory
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .adaptiveGlass(in: shape, interactive: true)
            .overlay(
                shape.strokeBorder(
                    speech.isListening
                        ? Color.red.opacity(0.65)
                        : Color.accentColor.opacity(isFieldFocused ? 0.55 : 0.18),
                    lineWidth: 0.8
                )
            )

            if let reply = replyLine {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: reply.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .foregroundStyle(reply.isError ? Color.red : Color.green)
                    Text(reply.text)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(2)
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !store.missedScheduledCommands.isEmpty {
                missedScheduledRow
            }

            if !store.scheduledCommands.isEmpty {
                scheduledRow
            }

            suggestionsRow
        }
        .help(L10n.tr(
            "长按顶部菜单栏温度图标可按住说话；或点击麦克风说话，打字回车执行",
            "Long-press the menu bar icon for Push-to-Talk, click the mic to speak, or type and press Return"
        ))
        .animation(AppleMotion.snappySpring, value: store.assistantState)
        .animation(AppleMotion.snappySpring, value: store.assistantSuggestions)
        .animation(AppleMotion.snappySpring, value: store.missedScheduledCommands)
        .animation(AppleMotion.snappySpring, value: store.scheduledCommands)
        .animation(AppleMotion.snappySpring, value: speech.isListening)
        .onAppear {
            if store.assistantVoiceRequest != lastHandledVoiceRequest {
                lastHandledVoiceRequest = store.assistantVoiceRequest
                Task { await speech.start(holdMode: false, store: store) }
            } else if !speech.isListening {
                isFieldFocused = true
            }
        }
        .onChange(of: store.assistantFocusRequest) { _, _ in
            if !speech.isListening {
                isFieldFocused = true
            }
        }
        .onChange(of: store.assistantVoiceRequest) { _, newValue in
            lastHandledVoiceRequest = newValue
            speech.toggle(store: store)
        }
    }

    /// Timers that expired while the app was closed; user can run or dismiss each one.
    private var missedScheduledRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(store.missedScheduledCommands) { entry in
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.clock.fill")
                        .foregroundStyle(Color.orange)
                    Text(L10n.tr("已错过：\(entry.reply)", "Missed: \(entry.reply)"))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(L10n.tr("立即执行", "Run Now")) {
                        Task { await store.runMissedScheduledCommand(id: entry.id) }
                    }
                    .buttonStyle(PillActionButtonStyle(isSelected: true, tintColor: .orange))
                    Button {
                        store.dismissMissedScheduledCommand(id: entry.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("忽略这个已错过的定时", "Dismiss this missed timer"))
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 4)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Pending "10 分钟后关灯" commands with a live countdown and a cancel button.
    private var scheduledRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(store.scheduledCommands) { entry in
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .foregroundStyle(Color.orange)
                    Text(entry.reply)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(entry.fireDate, style: .timer)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button {
                        store.cancelScheduledCommands(id: entry.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("取消这个定时", "Cancel this timer"))
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 4)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var suggestionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    Task { await store.requestProactiveJevSuggestions() }
                } label: {
                    HStack(spacing: 3.5) {
                        if store.isProactiveRecommending {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.65)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(L10n.tr("Jev 猜你想做", "Jev Suggests"))
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.isProactiveRecommending)
                .help(L10n.tr(
                    "让 Jev 结合当前室温、时间段与你的个人习惯，实时推演最可能执行的设备操作",
                    "Let Jev infer your most likely device actions based on room temperature, time of day, and habits"
                ))

                ForEach(store.assistantSuggestions) { suggestion in
                    Button {
                        Task { await store.applyAssistantSuggestion(suggestion) }
                    } label: {
                        HStack(spacing: 3.5) {
                            Image(systemName: suggestion.confidencePercent != nil ? "sparkle" : "clock.arrow.circlepath")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(suggestion.confidencePercent != nil ? Color.orange : Color.secondary)
                            Text(suggestion.title)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.88))
                            if let pct = suggestion.confidencePercent {
                                Text("\(pct)%")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.orange)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(
                        suggestion.confidencePercent != nil
                            ? L10n.tr("Jev 概率分布推演建议（点击立即执行）", "Jev probability-based suggestion (click to execute)")
                            : L10n.tr("你在当前时间段的常用习惯（点击立即执行）", "Your frequent habit in this time slot (click to execute)")
                    )
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var placeholderText: String {
        if speech.isHoldToTalk {
            return L10n.tr(
                "按住菜单栏说话，松开立即执行（如：准备写代码、书房灯月光模式）",
                "Hold menu bar to speak, release to run (e.g. turn on study light, moonlight mode)"
            )
        }
        if speech.isListening {
            return L10n.tr(
                "正在聆听…说完自动执行（如：准备写代码、书房灯月光模式）",
                "Listening… auto-runs when done (e.g. turn on study light, moonlight mode)"
            )
        }
        return L10n.tr(
            "支持模糊情境与习惯（如：准备写代码、有点闷热、书房灯月光模式）",
            "Type or speak a command (e.g. turn on study light, AC 24 degrees, moonlight mode)"
        )
    }

    private var micButton: some View {
        Button {
            speech.toggle(store: store)
        } label: {
            Image(systemName: speech.isListening ? "stop.circle.fill" : "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(speech.isListening ? Color.red : Color.accentColor)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(speech.isListening
              ? L10n.tr("停止聆听并执行", "Stop listening and run")
              : L10n.tr("语音输入（快捷键 V，或长按菜单栏图标）", "Voice input (Shortcut V, or long-press menu bar icon)"))
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if store.assistantState == .thinking {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
        } else {
            Button {
                speech.stop(andSubmit: false, store: store)
                withAnimation(AppleMotion.snappySpring) {
                    store.dismissAssistantBar()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("关闭 (Esc)", "Close (Esc)"))
        }
    }

    private var replyLine: (text: String, isError: Bool)? {
        if let speechError = speech.errorMessage {
            return (speechError, true)
        }
        switch store.assistantState {
        case .done(let text): return (text.isEmpty ? L10n.tr("已执行", "Done") : text, false)
        case .failed(let message): return (message, true)
        case .idle, .thinking: return nil
        }
    }
}

// MARK: - Settings: AI 指令

struct AssistantSettingsSection: View {
    let store: HomeStore

    @State private var baseURLDraft: String = ""
    @State private var modelDraft: String = ""
    @State private var apiKeyDraft: String = ""
    @State private var isShowingHabits = false
    /// Habit memory lives in UserDefaults (not observed), so bump this to redraw after edits.
    @State private var habitRevision = 0

    var body: some View {
        let _ = store.effectiveLanguage
        let _ = habitRevision
        let habitItems = store.userHabitMemory.readableItems(devices: store.devices, scenes: store.scenes)
        let habitCount = habitItems.count
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L10n.tr("AI 决策与习惯记忆 (Jev)", "AI Decision & Habit Memory (Jev)"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if AssistantConfig.loadCodexBarOpenRouterKey() != nil {
                    Text(L10n.tr("● 已自动接入 CodexBar", "● Linked via CodexBar"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.green)
                } else if !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.tr("● 已配置 API Key", "● API Key Configured"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Text(L10n.tr("● 未配置 Key（常规指令本地可用）", "● No Key (Local Rules Active)"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            labeledField(L10n.tr(
                "服务地址 (默认 OpenRouter /v1，支持 System One 决策协议)",
                "Endpoint URL (Default OpenRouter /v1, System One Protocol)"
            )) {
                TextField(AssistantConfig.defaultBaseURL, text: $baseURLDraft)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField(L10n.tr(
                "模型 (默认 ~typesafe/jev-latest，支持全屋多头并行概率决策)",
                "Model (Default ~typesafe/jev-latest, Multi-Head Probabilistic Decision)"
            )) {
                TextField(AssistantConfig.defaultModel, text: $modelDraft)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField(L10n.tr(
                "API Key (留空将自动读取 CodexBar 的 OpenRouter Key)",
                "API Key (Leave blank to auto-read OpenRouter Key from CodexBar)"
            )) {
                SecureField(
                    L10n.tr("留空自动读取 CodexBar，或手动输入存入钥匙串", "Auto-read CodexBar or enter manually (stored in Keychain)"),
                    text: $apiKeyDraft
                )
                .textFieldStyle(.roundedBorder)
            }

            privacySection(habitItems: habitItems, habitCount: habitCount)

            HStack {
                Button(L10n.tr("恢复 Jev 默认", "Restore Defaults")) {
                    baseURLDraft = AssistantConfig.defaultBaseURL
                    modelDraft = AssistantConfig.defaultModel
                }
                .buttonStyle(PillActionButtonStyle())

                Spacer()

                Button(L10n.tr("保存 AI 配置", "Save AI Config")) {
                    store.assistantConfig = AssistantConfig(
                        baseURL: baseURLDraft,
                        model: modelDraft,
                        apiKey: apiKeyDraft
                    )
                    store.showToast(L10n.tr("已保存 AI 指令配置", "Saved AI configuration"))
                }
                .buttonStyle(PillActionButtonStyle(isSelected: true, tintColor: .accentColor))
            }
            .padding(.top, 2)
        }
        .padding(12)
        .glassTile(isActive: false, accent: .accentColor, cornerRadius: 12)
        .onAppear {
            let config = store.assistantConfig
            baseURLDraft = config.baseURL
            modelDraft = config.model
            apiKeyDraft = config.apiKey
        }
    }

    @ViewBuilder
    private func privacySection(habitItems: [UserHabitMemory.ReadableItem], habitCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { store.isHabitLearningEnabled },
                set: { store.isHabitLearningEnabled = $0 }
            )) {
                Text(L10n.tr("学习我的使用习惯（用于猜你想做）", "Learn my usage habits (for proactive suggestions)"))
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Toggle(isOn: Binding(
                get: { store.prefersOnDeviceSpeech },
                set: { store.prefersOnDeviceSpeech = $0 }
            )) {
                Text(L10n.tr("语音只在本机识别（不把声音发给苹果，系统支持时生效）", "On-device speech recognition only (when supported by macOS)"))
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack {
                Button(isShowingHabits
                       ? L10n.tr("收起已学习的习惯", "Hide learned habits")
                       : L10n.tr("查看已学习的习惯（\(habitCount) 条）", "View learned habits (\(habitCount))")) {
                    isShowingHabits.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .disabled(habitCount == 0)
                Spacer()
                if habitCount > 0 {
                    Button(L10n.tr("清空记忆", "Clear Memory")) {
                        store.userHabitMemory = UserHabitMemory()
                        habitRevision &+= 1
                        store.showToast(L10n.tr("已清空个人习惯记忆", "Cleared personal habit memory"))
                    }
                    .buttonStyle(PillActionButtonStyle())
                }
            }

            if isShowingHabits {
                ForEach(habitItems) { item in
                    HStack(spacing: 6) {
                        Text(item.text)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Button {
                            var memory = store.userHabitMemory
                            memory.forget(itemId: item.id)
                            store.userHabitMemory = memory
                            habitRevision &+= 1
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.tr("忘掉这一条", "Forget this habit"))
                    }
                }
            }

            Text(L10n.tr(
                "发给 AI 的内容：你说的那句话、设备名称/房间/当前状态、时间段、室温\(store.isHabitLearningEnabled ? "、习惯摘要" : "")。只有本机解析不了的指令才会发送。API Key 和米家登录信息只存在本机钥匙串，不会发送。",
                "Sent to AI only when local parsing cannot resolve: your command text, device names/rooms/states, time slot, room temperature\(store.isHabitLearningEnabled ? ", and habit summary" : ""). API keys and Xiaomi credentials stay in your local Keychain."
            ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labeledField<Field: View>(_ title: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            field()
                .controlSize(.small)
                .font(.system(size: 11.5, design: .monospaced))
        }
    }
}
