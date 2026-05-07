import AVFoundation
import Speech
import SwiftUI

public enum TeleprompterKitStrings {
    public static var title: String {
        teleprompterLocalized("teleprompter")
    }

    public static func string(_ key: String) -> String {
        teleprompterLocalized(key)
    }
}

@available(iOS 14.0, macOS 11.0, *)
public struct TeleprompterView: View {
    private let text: String
    private let ticker = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    @StateObject private var speechController = TeleprompterSpeechController()
    @State private var mode: TeleprompterScrollMode = .auto
    @State private var isPlaying = false
    @State private var showControls = true
    @State private var progress: CGFloat = 0
    @State private var fontSize: CGFloat
    @State private var lineSpacing: CGFloat
    @State private var readingWidth: CGFloat
    @State private var durationMinutes: Double
    @State private var unitsPerMinute: Double
    @State private var isMirrored = false
    @State private var isLooping = false
    @State private var isDarkMode = true
    @State private var textContentHeight: CGFloat = 1
    @State private var lastTick = Date()
    @State private var dragStartProgress: CGFloat?
    @State private var controlsHideTask: DispatchWorkItem?

    public init(text: String) {
        self.text = text
        let defaults = TeleprompterDefaults.make(for: text)
        _fontSize = State(initialValue: defaults.fontSize)
        _lineSpacing = State(initialValue: defaults.lineSpacing)
        _readingWidth = State(initialValue: defaults.readingWidth)
        _durationMinutes = State(initialValue: defaults.durationMinutes)
        _unitsPerMinute = State(initialValue: defaults.unitsPerMinute)
    }

    public var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            GeometryReader { proxy in
                let viewportHeight = max(proxy.size.height, 1)
                let targetWidth = min(proxy.size.width * readingWidth, 760)
                let topInset = viewportHeight * 0.28
                let bottomInset = viewportHeight * 0.72
                let contentHeight = topInset + max(textContentHeight, 1) + bottomInset
                let maxOffset = max(contentHeight - viewportHeight, 1)

                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: topInset)

                        Text(displayText)
                            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                            .foregroundColor(primaryTextColor)
                            .lineSpacing(lineSpacing)
                            .multilineTextAlignment(.leading)
                            .frame(width: targetWidth, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .scaleEffect(x: isMirrored ? -1 : 1, y: 1, anchor: .center)
                            .background(
                                GeometryReader { reader in
                                    Color.clear.preference(key: TeleprompterTextHeightKey.self, value: reader.size.height)
                                }
                            )

                        Spacer().frame(height: bottomInset)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(y: -progress * maxOffset)
                }
                .clipped()
                .contentShape(Rectangle())
                .gesture(dragGesture(maxOffset: maxOffset))
                .onTapGesture {
                    revealControls()
                }
            }

            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }

            if isPlaying && !showControls {
                passivePlaybackProgress
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(TeleprompterTextHeightKey.self) { height in
            textContentHeight = max(height, 1)
        }
        .onReceive(ticker) { now in
            let delta = now.timeIntervalSince(lastTick)
            lastTick = now
            guard isPlaying else { return }
            advance(delta: max(0, min(delta, 0.2)))
        }
        .onChange(of: mode) { newMode in
            if isPlaying {
                speechController.stop()
                if newMode == .auto {
                    speechController.start()
                }
            }
        }
        .onDisappear {
            controlsHideTask?.cancel()
            speechController.stop()
        }
    }

    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? teleprompterLocalized("teleprompter_empty") : trimmed
    }

    private var totalUnits: Int {
        max(TeleprompterTextCounter.countUnits(in: displayText), 1)
    }

    private var backgroundColor: Color {
        isDarkMode ? Color(red: 0.02, green: 0.02, blue: 0.025) : Color(red: 0.95, green: 0.94, blue: 0.9)
    }

    private var panelColor: Color {
        isDarkMode ? Color(red: 0.07, green: 0.075, blue: 0.085).opacity(0.84) : Color.white.opacity(0.88)
    }

    private var primaryTextColor: Color {
        isDarkMode ? Color.white : Color(red: 0.08, green: 0.08, blue: 0.09)
    }

    private var secondaryTextColor: Color {
        isDarkMode ? Color.white.opacity(0.68) : Color.black.opacity(0.58)
    }

    private var accentColor: Color {
        Color(red: 0.98, green: 0.46, blue: 0.12)
    }

    private var controlFillColor: Color {
        isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var panelStrokeColor: Color {
        isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    private var controlsOverlay: some View {
        VStack(spacing: 12) {
            settingsPanel
                .frame(maxWidth: 520)
                .padding(.top, 114)

            Spacer(minLength: 12)

            playbackBar
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
    }

    private var passivePlaybackProgress: some View {
        VStack {
            Spacer()

            GeometryReader { proxy in
                let width = max(proxy.size.width * progress, 2)
                let lineColor = isDarkMode ? Color.white : Color.black

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(lineColor.opacity(0.12))

                    Capsule()
                        .fill(lineColor.opacity(0.34))
                        .frame(width: width)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .allowsHitTesting(false)
    }

    private var settingsPanel: some View {
        VStack(spacing: 10) {
            modeSelector

            VStack(spacing: 8) {
                if mode == .timed {
                    sliderRow(
                        title: teleprompterLocalized("teleprompter_duration"),
                        valueText: "\(Int(durationMinutes)) \(teleprompterLocalized("teleprompter_minutes"))",
                        value: $durationMinutes,
                        range: 1...180,
                        step: 1
                    )
                }

                if mode != .timed {
                    sliderRow(
                        title: teleprompterLocalized("teleprompter_units_per_minute"),
                        valueText: "\(Int(unitsPerMinute))",
                        value: $unitsPerMinute,
                        range: 60...420,
                        step: 10
                    )
                }

                sliderRow(
                    title: teleprompterLocalized("teleprompter_font_size"),
                    valueText: "\(Int(fontSize))",
                    value: $fontSize,
                    range: 26...86,
                    step: 1
                )

                sliderRow(
                    title: teleprompterLocalized("teleprompter_line_spacing"),
                    valueText: "\(Int(lineSpacing))",
                    value: $lineSpacing,
                    range: 4...32,
                    step: 1
                )

                sliderRow(
                    title: teleprompterLocalized("teleprompter_reading_width"),
                    valueText: "\(Int(readingWidth * 100))%",
                    value: $readingWidth,
                    range: 0.45...0.9,
                    step: 0.01
                )
            }

            HStack(spacing: 10) {
                compactToggle(title: teleprompterLocalized("teleprompter_mirror"), isOn: $isMirrored, systemName: "rectangle.righthalf.inset.filled")
                compactToggle(title: teleprompterLocalized("teleprompter_loop"), isOn: $isLooping, systemName: "repeat")

                Button(action: { isDarkMode.toggle() }) {
                    Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                        .frame(width: 40, height: 34)
                        .background(Capsule().fill(controlFillColor))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(panelColor)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(panelStrokeColor, lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(isDarkMode ? 0.34 : 0.12), radius: 20, x: 0, y: 8)
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(TeleprompterScrollMode.allCases) { option in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        mode = option
                    }
                }) {
                    Text(teleprompterLocalized(option.localizationKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(mode == option ? Color.white : primaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(mode == option ? accentColor : Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(controlFillColor))
    }

    private var playbackBar: some View {
        HStack(spacing: 14) {
            iconButton(systemName: "backward.end.fill") {
                resetPlayback()
            }

            iconButton(systemName: isPlaying ? "pause.fill" : "play.fill", highlighted: true) {
                togglePlayback()
            }

            ProgressView(value: Double(progress))
                .accentColor(accentColor)
                .frame(maxWidth: .infinity)

            Text("\(Int(progress * 100))%")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(secondaryTextColor)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(panelColor))
        .shadow(color: Color.black.opacity(isDarkMode ? 0.34 : 0.12), radius: 18, x: 0, y: 8)
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 8)

                Text(valueText)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
            }

            Slider(value: value, in: range, step: step)
                .accentColor(accentColor)
        }
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat
    ) -> some View {
        sliderRow(
            title: title,
            valueText: valueText,
            value: Binding<Double>(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = CGFloat($0) }
            ),
            range: Double(range.lowerBound)...Double(range.upperBound),
            step: Double(step)
        )
    }

    private func compactToggle(title: String, isOn: Binding<Bool>, systemName: String) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: 7) {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(isOn.wrappedValue ? Color.white : primaryTextColor)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Capsule().fill(isOn.wrappedValue ? accentColor : controlFillColor))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func iconButton(systemName: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(highlighted ? Color.white : primaryTextColor)
                .frame(width: highlighted ? 50 : 42, height: highlighted ? 50 : 42)
                .background(Circle().fill(highlighted ? accentColor : controlFillColor))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func dragGesture(maxOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStartProgress == nil {
                    dragStartProgress = progress
                    pausePlayback(showPanel: true)
                }
                let start = dragStartProgress ?? progress
                progress = clamped(start - value.translation.height / max(maxOffset, 1))
            }
            .onEnded { _ in
                dragStartProgress = nil
                scheduleControlHideIfNeeded()
            }
    }

    private func togglePlayback() {
        isPlaying ? pausePlayback(showPanel: true) : startPlayback()
    }

    private func startPlayback() {
        lastTick = Date()
        isPlaying = true
        controlsHideTask?.cancel()
        if mode == .auto {
            speechController.start()
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            showControls = false
        }
    }

    private func pausePlayback(showPanel: Bool) {
        isPlaying = false
        speechController.stop()
        controlsHideTask?.cancel()
        if showPanel {
            withAnimation(.easeInOut(duration: 0.18)) {
                showControls = true
            }
        }
    }

    private func resetPlayback() {
        pausePlayback(showPanel: true)
        speechController.reset()
        withAnimation(.easeOut(duration: 0.2)) {
            progress = 0
        }
    }

    private func advance(delta: TimeInterval) {
        var next = progress
        let total = CGFloat(totalUnits)

        switch mode {
        case .auto:
            let speechProgress = CGFloat(speechController.spokenUnitCount) / total
            let speakingMultiplier = speechController.autoScrollMultiplier
            next += CGFloat(delta) * CGFloat(unitsPerMinute / 60.0) / total * speakingMultiplier
            if speechProgress > next {
                next = min(speechProgress, next + max(CGFloat(delta) * 0.18, CGFloat(delta) * CGFloat(unitsPerMinute / 60.0) / total * 2.5))
            }
        case .timed:
            next += CGFloat(delta / max(durationMinutes * 60, 1))
        case .unitsPerMinute:
            next += CGFloat(delta) * CGFloat(unitsPerMinute / 60.0) / total
        }

        if next >= 1 {
            if isLooping {
                progress = 0
                speechController.reset()
            } else {
                progress = 1
                pausePlayback(showPanel: true)
            }
        } else {
            progress = clamped(next)
        }
    }

    private func revealControls() {
        if isPlaying {
            pausePlayback(showPanel: true)
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            showControls = true
        }
        scheduleControlHideIfNeeded()
    }

    private func scheduleControlHideIfNeeded() {
        controlsHideTask?.cancel()
        guard isPlaying else { return }
        let task = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = false
            }
        }
        controlsHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

private enum TeleprompterScrollMode: String, CaseIterable, Identifiable {
    case auto
    case timed
    case unitsPerMinute

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .auto: return "teleprompter_auto"
        case .timed: return "teleprompter_timed"
        case .unitsPerMinute: return "teleprompter_wpm"
        }
    }
}

private struct TeleprompterDefaults {
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let readingWidth: CGFloat
    let durationMinutes: Double
    let unitsPerMinute: Double

    static func make(for text: String) -> TeleprompterDefaults {
        let unitsPerMinute = TeleprompterTextCounter.defaultUnitsPerMinute(in: text)
        let units = max(TeleprompterTextCounter.countUnits(in: text), 1)
        let estimatedMinutes = Double(units) / max(unitsPerMinute, 1)
        let durationMinutes = min(max(ceil(estimatedMinutes), 1), 180)

        return TeleprompterDefaults(
            fontSize: 44,
            lineSpacing: 16,
            readingWidth: 0.62,
            durationMinutes: durationMinutes,
            unitsPerMinute: unitsPerMinute
        )
    }
}

private final class TeleprompterSpeechController: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var authorizationDenied = false
    @Published var spokenUnitCount = 0
    @Published var audioLevel: Float = 0
    @Published var lastVoiceActivityAt: Date = .distantPast

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    var isActivelySpeaking: Bool {
        audioLevel > 0.035
    }

    var autoScrollMultiplier: CGFloat {
        if authorizationDenied {
            return 0.82
        }

        guard isListening else {
            return spokenUnitCount > 0 ? 0.18 : 0.1
        }

        let silenceDuration = Date().timeIntervalSince(lastVoiceActivityAt)
        if silenceDuration < 0.65 {
            return 1.06
        }
        if silenceDuration < 1.5 {
            return 0.55
        }
        if silenceDuration < 3.2 {
            return 0.18
        }
        return 0.04
    }

    func start() {
        guard !isListening else { return }
        authorizationDenied = false

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            guard let self = self else { return }
#if os(iOS)
            AVAudioSession.sharedInstance().requestRecordPermission { micAllowed in
                DispatchQueue.main.async {
                    guard speechStatus == .authorized, micAllowed else {
                        self.authorizationDenied = true
                        self.isListening = false
                        return
                    }
                    self.beginRecognition()
                }
            }
#else
            DispatchQueue.main.async {
                guard speechStatus == .authorized else {
                    self.authorizationDenied = true
                    self.isListening = false
                    return
                }
                self.beginRecognition()
            }
#endif
        }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        isListening = false
        audioLevel = 0
    }

    func reset() {
        spokenUnitCount = 0
        lastVoiceActivityAt = .distantPast
    }

    private func beginRecognition() {
        stop()

        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
        guard let recognizer = recognizer, recognizer.isAvailable else {
            authorizationDenied = true
            return
        }
        speechRecognizer = recognizer

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        do {
#if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
#endif

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                self?.updateAudioLevel(from: buffer)
            }

            engine.prepare()
            try engine.start()

            audioEngine = engine
            recognitionRequest = request
            isListening = true
            authorizationDenied = false

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                if let result = result {
                    let count = TeleprompterTextCounter.countUnits(in: result.bestTranscription.formattedString)
                    DispatchQueue.main.async {
                        self.spokenUnitCount = max(self.spokenUnitCount, count)
                    }
                }
                if error != nil || result?.isFinal == true {
                    DispatchQueue.main.async {
                        self.stop()
                    }
                }
            }
        } catch {
            authorizationDenied = true
            isListening = false
        }
    }

    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var total: Float = 0
        for index in 0..<frameLength {
            let sample = channelData[index]
            total += sample * sample
        }
        let rms = sqrt(total / Float(frameLength))
        let normalized = min(max(rms * 18, 0), 1)
        DispatchQueue.main.async {
            self.audioLevel = normalized
            if normalized > 0.035 {
                self.lastVoiceActivityAt = Date()
            }
        }
    }
}

private enum TeleprompterTextCounter {
    private enum CountingStyle {
        case character
        case word
    }

    static func countUnits(in text: String) -> Int {
        let cjkCount = text.unicodeScalars.filter { scalar in
            isCJK(scalar.value) || isKana(scalar.value) || isHangul(scalar.value)
        }.count

        let meaningfulScalarCount = text.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar) && !CharacterSet.punctuationCharacters.contains(scalar)
        }.count

        if cjkCount > 0 {
            let nonCJKWordCount = text
                .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                .filter { token in
                    token.unicodeScalars.contains { scalar in
                        !(isCJK(scalar.value) || isKana(scalar.value) || isHangul(scalar.value))
                    }
                }
                .count
            return max(cjkCount + nonCJKWordCount, 1)
        }

        let words = text.split { character in
            character.isWhitespace || character.isNewline || character.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
        }
        return max(words.count, meaningfulScalarCount > 0 ? 1 : 0)
    }

    static func defaultUnitsPerMinute(in text: String) -> Double {
        switch countingStyle(in: text) {
        case .character:
            return 220
        case .word:
            return 140
        }
    }

    private static func countingStyle(in text: String) -> CountingStyle {
        let cjkCount = text.unicodeScalars.filter { scalar in
            isCJK(scalar.value) || isKana(scalar.value) || isHangul(scalar.value)
        }.count
        return cjkCount > 0 ? .character : .word
    }

    private static func isCJK(_ value: UInt32) -> Bool {
        (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value)
    }

    private static func isKana(_ value: UInt32) -> Bool {
        (0x3040...0x30FF).contains(value)
    }

    private static func isHangul(_ value: UInt32) -> Bool {
        (0xAC00...0xD7AF).contains(value)
    }
}

private struct TeleprompterTextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private func teleprompterLocalized(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .module, value: key, comment: "")
}
