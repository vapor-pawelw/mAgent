import Cocoa
import MagentCore

private enum PromptTOCNavigationError: Error {
    case promptUnavailable
}

private struct PromptPaneCandidate {
    let startLineIndex: Int
    let endLineIndex: Int
    let displayText: String
    let fullText: String
}

private struct PromptPaneLine {
    let rawText: String
    let plainText: String
    let styledCharacters: [PromptPaneStyledCharacter]
}

private struct PromptPaneStyledCharacter {
    let character: Character
    let style: PromptANSIStyle
}

private struct PromptANSIStyle: Equatable {
    var isDim = false
    var foreground: PromptANSIForeground = .default
    var background: PromptANSIForeground = .default
}

private enum PromptANSIForeground: Equatable {
    case `default`
    case indexed(Int)
    case rgb(Int, Int, Int)

    var isGrayLike: Bool {
        switch self {
        case .default:
            return false
        case .indexed(let value):
            return value == 8 || (240...250).contains(value)
        case .rgb(let red, let green, let blue):
            let minChannel = min(red, min(green, blue))
            let maxChannel = max(red, max(green, blue))
            // Exclude very bright colors (near-white): rgb(255,255,255) is normal
            // terminal text, not placeholder text, even though all channels match.
            return maxChannel - minChannel <= 18 && maxChannel < 220
        }
    }
}

extension ThreadDetailViewController {

    func setupPromptTOCOverlay() {
        let tocView = PromptTableOfContentsView()
        tocView.translatesAutoresizingMaskIntoConstraints = false
        tocView.isHidden = true
        tocView.onSelectEntry = { [weak self] entryIndex in
            self?.handlePromptTOCSelection(entryIndex: entryIndex)
        }
        tocView.onRenameFromEntry = { [weak self] entryIndex in
            self?.handlePromptTOCRenameFromEntry(entryIndex: entryIndex)
        }
        tocView.onDragGesture = { [weak self] gesture in
            self?.handlePromptTOCDrag(gesture)
        }
        tocView.onResizeGesture = { [weak self] gesture, corner in
            self?.handlePromptTOCResize(gesture, corner: corner)
        }
        tocView.onPinnedResizeGesture = { [weak self] gesture in
            self?.handlePromptTOCPinnedResize(gesture)
        }
        tocView.onPinToggle = { [weak self] in
            guard let self else { return }
            self.setPromptTOCPinned(!self.isPromptTOCPinned)
        }

        terminalContainer.addSubview(tocView)
        tocView.onHoverStateChanged = { [weak self] expanded in
            self?.handleTOCHoverStateChanged(expanded)
        }
        tocView.onCollapseCompleted = { [weak self] in
            guard let self else { return }
            // Guard against re-hover that arrived before the animation finished.
            guard !(self.promptTOCView?.isExpanded ?? false) else { return }
            let cw = Self.promptTOCCollapsedWidth
            let ch = Self.promptTOCCollapsedHeight
            NSAnimationContext.runAnimationGroup { [weak self] ctx in
                guard let self else { return }
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                ctx.allowsImplicitAnimation = true
                self.promptTOCWidthConstraint?.constant = cw
                self.promptTOCHeightConstraint?.constant = ch
                self.terminalContainer.layoutSubtreeIfNeeded()
            }
        }

        promptTOCView = tocView
        installFloatingPromptTOCConstraints()
        bringPromptTOCOverlayToFront()
    }

    private func installFloatingPromptTOCConstraints() {
        guard let tocView = promptTOCView else { return }
        let top = tocView.topAnchor.constraint(equalTo: terminalContainer.topAnchor, constant: 12)
        let trailing = tocView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor, constant: -12)
        let width = tocView.widthAnchor.constraint(equalToConstant: Self.promptTOCCollapsedWidth)
        let height = tocView.heightAnchor.constraint(equalToConstant: Self.promptTOCCollapsedHeight)
        promptTOCTopConstraint = top
        promptTOCTrailingConstraint = trailing
        promptTOCWidthConstraint = width
        promptTOCHeightConstraint = height
        promptTOCFloatingConstraints = [top, trailing, width, height]
        NSLayoutConstraint.activate(promptTOCFloatingConstraints)
    }

    func restorePromptTOCPinnedState() {
        setPromptTOCPinned(
            UserDefaults.standard.bool(forKey: Self.promptTOCPinnedDefaultsKey),
            persist: false
        )
    }

    private func setPromptTOCPinned(_ pinned: Bool, persist: Bool = true) {
        guard let tocView = promptTOCView else { return }
        isPromptTOCPinned = pinned
        if persist {
            UserDefaults.standard.set(pinned, forKey: Self.promptTOCPinnedDefaultsKey)
        }

        NSLayoutConstraint.deactivate(promptTOCFloatingConstraints)
        NSLayoutConstraint.deactivate(promptTOCPinnedConstraints)
        terminalTrailingToPromptTOCConstraint?.isActive = false
        promptTOCFloatingConstraints.removeAll()
        promptTOCPinnedConstraints.removeAll()
        tocView.removeFromSuperview()

        if pinned {
            tocView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tocView, positioned: .above, relativeTo: terminalContainer)

            let pinnedWidth = PromptTOCPresentationState.pinnedWidth(
                requestedWidth: promptTOCExpandedSize.width,
                availableWidth: view.bounds.width,
                minimumTOCWidth: Self.promptTOCMinimumWidth,
                minimumContentWidth: 320
            )
            promptTOCExpandedSize.width = pinnedWidth

            let width = tocView.widthAnchor.constraint(equalToConstant: pinnedWidth)
            promptTOCPinnedWidthConstraint = width
            promptTOCPinnedConstraints = [
                tocView.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
                tocView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                tocView.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
                width,
            ]
            NSLayoutConstraint.activate(promptTOCPinnedConstraints)

            let contentTrailing = terminalContainer.trailingAnchor.constraint(equalTo: tocView.leadingAnchor)
            terminalTrailingToPromptTOCConstraint = contentTrailing
        } else {
            promptTOCPinnedWidthConstraint = nil
            terminalTrailingToPromptTOCConstraint = nil
            tocView.translatesAutoresizingMaskIntoConstraints = false
            terminalContainer.addSubview(tocView)
            installFloatingPromptTOCConstraints()
            if let sessionName = promptTOCSessionName {
                restorePromptTOCPosition(for: sessionName)
            }
        }

        tocView.setPinned(pinned)
        applyPromptTOCVisibility(restoringPosition: !pinned)
    }

    func schedulePromptTOCRefresh(after delay: TimeInterval = 0) {
        promptTOCRefreshTask?.cancel()
        promptTOCRefreshTask = Task { [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await refreshPromptTOC()
        }
    }

    func startPeriodicPromptTOCRefresh() {
        promptTOCPeriodicRefreshTask?.cancel()
        promptTOCPeriodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(PromptTOCRefreshPolicy.periodicInterval * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }
                self?.performPeriodicPromptTOCRefresh()
            }
        }
    }

    func preparePromptTOCRefreshForSessionReturn(_ sessionName: String) {
        promptTOCEmptyCaptureRetryAttemptedSessions.remove(sessionName)
    }

    func schedulePromptTOCRefreshAfterEscape() {
        if let sessionName = currentSessionName() {
            promptTOCEmptyCaptureRetryAttemptedSessions.remove(sessionName)
        }
        schedulePromptTOCRefresh(after: 0.35)
    }

    private func performPeriodicPromptTOCRefresh() {
        guard view.window != nil,
              showPromptTOCOverlay,
              let sessionName = currentSessionName(),
              thread.agentTmuxSessions.contains(sessionName) else { return }
        schedulePromptTOCRefresh()
    }

    @MainActor
    func refreshPromptTOC() async {
        guard let sessionName = currentSessionName() else {
            promptTOCSessionName = nil
            promptTOCEntries = []
            promptTOCCanShowForCurrentTab = false
            applyPromptTOCVisibility()
            return
        }
        guard thread.agentTmuxSessions.contains(sessionName) else {
            promptTOCSessionName = nil
            promptTOCEntries = []
            promptTOCCanShowForCurrentTab = false
            applyPromptTOCVisibility()
            return
        }

        let agentType = threadManager.agentType(for: thread, sessionName: sessionName)
        let previousSessionName = promptTOCSessionName
        let previousEntryCount = promptTOCSessionName == sessionName ? promptTOCEntries.count : 0
        let hasVisibleEntries = previousSessionName == sessionName && !promptTOCEntries.isEmpty
        let persistedPromptCount = (
            threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
        ).submittedPromptsBySession[sessionName]?.count ?? 0
        let knownPromptCount = max(previousEntryCount, persistedPromptCount)
        let shouldRetryEmptyEntries = PromptTOCRefreshPolicy.shouldRetryEmptyEntries(
            knownPromptCount: knownPromptCount
        ) &&
            !promptTOCEmptyCaptureRetryAttemptedSessions.contains(sessionName)
        promptTOCCanShowForCurrentTab = true
        applyPromptTOCVisibility()
        if !hasVisibleEntries {
            promptTOCView?.setLoading(agentType: agentType)
        }

        guard let capturedEntries = await capturePromptEntries(
            sessionName: sessionName,
            agentType: agentType,
            retryEmptyEntries: shouldRetryEmptyEntries
        ) else {
            if !Task.isCancelled, currentSessionName() == sessionName, knownPromptCount > 0 {
                promptTOCEmptyCaptureRetryAttemptedSessions.insert(sessionName)
            }
            return
        }
        guard !Task.isCancelled else { return }
        guard currentSessionName() == sessionName else { return }
        if capturedEntries.isEmpty, knownPromptCount > 0 {
            promptTOCEmptyCaptureRetryAttemptedSessions.insert(sessionName)
            return
        }
        promptTOCEmptyCaptureRetryAttemptedSessions.remove(sessionName)

        let currentThread = threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
        let entries = PromptTOCTimingResolver.attaching(
            currentThread.submittedPromptTimingsBySession[sessionName] ?? [],
            to: capturedEntries
        )
        threadManager.replaceSubmittedPromptHistory(
            threadId: thread.id,
            sessionName: sessionName,
            prompts: entries.map(\.fullText)
        )
        promptTOCSessionName = sessionName
        promptTOCEntries = entries

        if !thread.didAutoRenameFromFirstPrompt, entries.count > previousEntryCount {
            // Pass ALL accumulated prompts so the AI has full context even when the
            // first prompt was rate-limited and the user followed up with "continue".
            let threadId = thread.id
            let prompt = entries.map(\.fullText).joined(separator: "\n")
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Only rename when an agent process is actually running in the session.
                // This prevents terminal commands typed at a ❯-themed shell prompt from
                // triggering auto-rename when the agent is not active.
                guard await self.threadManager.detectedAgentTypeInSession(sessionName) != nil else { return }
                let previousThread = self.thread
                _ = await self.threadManager.autoRenameThreadAfterFirstPromptIfNeeded(
                    threadId: threadId,
                    sessionName: sessionName,
                    prompt: prompt
                )
                guard let updated = self.threadManager.threads.first(where: { $0.id == threadId }) else { return }
                if updated.name != previousThread.name || updated.worktreePath != previousThread.worktreePath {
                    self.handleRename(updated)
                } else if updated.didAutoRenameFromFirstPrompt, !previousThread.didAutoRenameFromFirstPrompt {
                    // No rename but flag changed (e.g., custom branch skip) — sync the flag to
                    // prevent this auto-rename task from being spawned again on every refresh.
                    self.thread = updated
                }
            }
        }
        promptTOCView?.setEntries(
            entries,
            agentType: agentType
        )
        if previousSessionName != sessionName {
            restorePromptTOCSize(for: sessionName)
            restorePromptTOCPosition(for: sessionName)
        }
        applyPromptTOCVisibility(restoringPosition: previousSessionName != sessionName)
        bringPromptTOCOverlayToFront()
        // Force layout so tocView.frame is up-to-date before clamping.
        terminalContainer.layoutSubtreeIfNeeded()
        clampPromptTOCPositionIfNeeded()
    }

    private func capturePromptEntries(
        sessionName: String,
        agentType: AgentType?,
        retryEmptyEntries: Bool
    ) async -> [PromptTOCEntry]? {
        for delay in PromptTOCRefreshPolicy.emptyCaptureRetryDelays {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return nil }

            guard let paneContent = await TmuxService.shared.captureFullPane(
                sessionName: sessionName,
                includeAttributes: true
            ) else {
                continue
            }
            guard !Task.isCancelled else { return nil }

            var entries = parsePromptEntries(from: paneContent, agentType: agentType)
            if entries.isEmpty, agentType != nil {
                entries = parsePromptEntries(from: paneContent, agentType: nil)
            }
            if !entries.isEmpty || !retryEmptyEntries {
                return entries
            }
        }
        return nil
    }

    private func parsePromptEntries(
        from paneContent: String,
        agentType: AgentType?
    ) -> [PromptTOCEntry] {
        let (candidates, lines) = parsePromptCandidates(from: paneContent, agentType: agentType)
        if candidates.isEmpty { return [] }

        let candidateOccupiedLineIndexes = Set(
            candidates.flatMap { Array($0.startLineIndex...$0.endLineIndex) }
        )
        let cutoff = activeBottomClusterStartIndex(
            in: lines,
            candidateOccupiedLineIndexes: candidateOccupiedLineIndexes
        )
        let confirmedCandidates = candidates.filter {
            $0.endLineIndex < cutoff &&
            hasConfirmedOutput(
                after: $0,
                in: lines,
                candidateOccupiedLineIndexes: candidateOccupiedLineIndexes,
                cutoff: cutoff
            )
        }
        return entriesFromCandidates(confirmedCandidates)
    }

    private func parsePromptCandidates(from paneContent: String, agentType: AgentType?) -> ([PromptPaneCandidate], [PromptPaneLine]) {
        let codexPromptMarker = "\u{203A}" // ›
        let claudePromptMarker = "\u{276F}" // ❯

        let markers: [String] = switch agentType {
        case .codex: [codexPromptMarker]
        case .claude: [claudePromptMarker]
        default: [codexPromptMarker, claudePromptMarker]
        }

        var candidates: [PromptPaneCandidate] = []
        let lines = promptPaneLines(from: paneContent)

        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let leftTrimmedCharacters = line.styledCharacters.drop(while: { $0.character.isWhitespace })
            let leftTrimmedText = String(leftTrimmedCharacters.map(\.character))
            guard let marker = markers.first(where: { leftTrimmedText.hasPrefix($0) }) else {
                lineIndex += 1
                continue
            }

            let promptCharacters = promptCharacters(after: marker, in: Array(leftTrimmedCharacters))
            let firstPromptLine = String(promptCharacters.map(\.character))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !firstPromptLine.isEmpty else {
                lineIndex += 1
                continue
            }

            let promptTextStyleLooksPlaceholderLike = promptTextLooksLikePlaceholder(
                promptCharacters,
                agentType: agentType
            )
            let codexPromptStyleLooksLikeUserInput = marker != codexPromptMarker ||
                codexPromptTextLooksLikeUserInput(promptCharacters)
            var promptLines = [firstPromptLine]
            var endLineIndex = lineIndex
            var continuationIndex = lineIndex + 1

            while continuationIndex < lines.count {
                let contLine = lines[continuationIndex]
                if let continuation = promptContinuationText(from: contLine, markers: markers) {
                    promptLines.append(continuation)
                    endLineIndex = continuationIndex
                    continuationIndex += 1
                } else if contLine.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Blank line between paragraphs — look ahead: keep going only if the next
                    // non-blank line would still be a valid continuation (2+ spaces, no marker).
                    let peekIndex = continuationIndex + 1
                    if peekIndex < lines.count,
                       promptContinuationText(from: lines[peekIndex], markers: markers) != nil {
                        promptLines.append("")
                        endLineIndex = continuationIndex
                        continuationIndex += 1
                    } else {
                        break
                    }
                } else {
                    break
                }
            }

            let displayPromptText = promptLines.filter { !$0.isEmpty }.joined(separator: " ")
            guard !displayPromptText.isEmpty else {
                lineIndex = continuationIndex
                continue
            }
            let fullPromptText = promptLines.joined(separator: "\n")

            // Skip interactive selector rows (for example: "❯ 1. Continue").
            if displayPromptText.range(of: #"^\d+\."#, options: .regularExpression) != nil {
                lineIndex = continuationIndex
                continue
            }
            let lowerPrompt = displayPromptText.lowercased()
            if lowerPrompt == "yes" || lowerPrompt == "no" {
                lineIndex = continuationIndex
                continue
            }
            // Skip agent-emitted system status lines (for example: "❯ Tool loaded.").
            if lowerPrompt == "tool loaded." || lowerPrompt == "tools loaded." {
                lineIndex = continuationIndex
                continue
            }
            // For Codex, keep only prompt rows whose text largely matches the
            // starting ANSI style right after `›` (user-input style), and reject
            // secondary-status style rows.
            if !codexPromptStyleLooksLikeUserInput {
                lineIndex = continuationIndex
                continue
            }
            // Exclude generic suggestion templates (for example: "Implement {feature}")
            // that can appear in the composer area but were not actually submitted.
            if promptTextStyleLooksPlaceholderLike || isPlaceholderSuggestionPrompt(displayPromptText) {
                lineIndex = continuationIndex
                continue
            }

            candidates.append(
                PromptPaneCandidate(
                    startLineIndex: lineIndex,
                    endLineIndex: endLineIndex,
                    displayText: displayPromptText,
                    fullText: fullPromptText
                )
            )
            lineIndex = continuationIndex
            continue
        }

        return (candidates, lines)
    }

    private func entriesFromCandidates(_ candidates: [PromptPaneCandidate]) -> [PromptTOCEntry] {
        var entries = candidates.map { candidate in
            PromptTOCEntry(
                lineIndex: candidate.startLineIndex,
                displayText: candidate.displayText,
                fullText: candidate.fullText
            )
        }
        if entries.count > 250 {
            entries = Array(entries.suffix(250))
        }
        return entries
    }

    private func activeBottomClusterStartIndex(
        in lines: [PromptPaneLine],
        candidateOccupiedLineIndexes: Set<Int>
    ) -> Int {
        guard !lines.isEmpty else { return 0 }

        var cutoff = lines.count
        var sawBottomClusterContent = false

        for lineIndex in stride(from: lines.count - 1, through: 0, by: -1) {
            let trimmed = lines[lineIndex].plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if sawBottomClusterContent {
                    cutoff = lineIndex
                }
                continue
            }

            let isCandidateLine = candidateOccupiedLineIndexes.contains(lineIndex)
            let isBottomAuxiliary = isBottomPinnedAuxiliaryLine(trimmed)

            if isCandidateLine || isBottomAuxiliary {
                sawBottomClusterContent = true
                cutoff = lineIndex
                continue
            }

            break
        }
        return cutoff
    }

    private func hasConfirmedOutput(
        after candidate: PromptPaneCandidate,
        in lines: [PromptPaneLine],
        candidateOccupiedLineIndexes: Set<Int>,
        cutoff: Int
    ) -> Bool {
        guard candidate.endLineIndex + 1 < cutoff else { return false }

        for lineIndex in (candidate.endLineIndex + 1)..<cutoff {
            let trimmed = lines[lineIndex].plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || isBottomPinnedAuxiliaryLine(trimmed) {
                continue
            }
            if candidateOccupiedLineIndexes.contains(lineIndex) {
                return false
            }
            return true
        }

        return false
    }

    private func isPlaceholderSuggestionPrompt(_ promptText: String) -> Bool {
        let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholder = extractTemplatePlaceholder(from: trimmed)?.lowercased() ?? ""
        guard !placeholder.isEmpty else { return false }
        guard placeholder.range(of: #"^[a-z][a-z0-9 _/\-]{1,24}$"#, options: .regularExpression) != nil else { return false }

        guard let prefix = templatePlaceholderPrefix(from: trimmed), !prefix.isEmpty else { return false }
        let prefixWordCount = prefix.split(whereSeparator: \.isWhitespace).count
        guard (1...4).contains(prefixWordCount) else { return false }

        switch placeholder {
        case "feature", "bug", "fix", "refactor", "improvement", "task", "issue",
             "test", "tests", "doc", "docs", "documentation", "ui", "ux", "api":
            return true
        default:
            return false
        }
    }

    private func isBottomPinnedAuxiliaryLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if isPromptFooterDividerLine(trimmed) || isBarePromptInputLine(trimmed) {
            return true
        }

        let lower = trimmed.lowercased()
        if lower.contains("tab to cycle")
            || lower.contains("enter to submit")
            || lower.contains("shift+tab")
            || lower.contains("ctrl+c to stop")
            || lower.contains("esc to interrupt") {
            return true
        }

        let isModelStatusLine = trimmed.range(
            of: #"^(gpt|o[1-9]|claude|codex)[a-z0-9 .\-]*\s+·\s+.*\bleft\b.*(?:~/|/Users/|/[A-Za-z0-9._-]+/)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if isModelStatusLine {
            return true
        }

        return false
    }

    private func promptPaneLines(from paneContent: String) -> [PromptPaneLine] {
        paneContent
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
            .map(parsePromptPaneLine)
    }

    private func parsePromptPaneLine(_ rawLine: String) -> PromptPaneLine {
        var styledCharacters: [PromptPaneStyledCharacter] = []
        var currentStyle = PromptANSIStyle()
        var index = rawLine.startIndex

        while index < rawLine.endIndex {
            let character = rawLine[index]
            if character == "\u{001B}" {
                let nextIndex = rawLine.index(after: index)
                guard nextIndex < rawLine.endIndex else { break }
                let nextCharacter = rawLine[nextIndex]

                if nextCharacter == "[" {
                    var sequenceEnd = rawLine.index(after: nextIndex)
                    while sequenceEnd < rawLine.endIndex {
                        let scalar = rawLine[sequenceEnd].unicodeScalars.first?.value ?? 0
                        if (0x40...0x7E).contains(scalar) { break }
                        sequenceEnd = rawLine.index(after: sequenceEnd)
                    }
                    guard sequenceEnd < rawLine.endIndex else { break }
                    if rawLine[sequenceEnd] == "m" {
                        let paramsText = String(rawLine[rawLine.index(after: nextIndex)..<sequenceEnd])
                        applySGRParameters(
                            paramsText
                                .split(separator: ";", omittingEmptySubsequences: false)
                                .compactMap { $0.isEmpty ? 0 : Int($0) },
                            to: &currentStyle
                        )
                    }
                    index = rawLine.index(after: sequenceEnd)
                    continue
                }

                if nextCharacter == "]" {
                    var sequenceEnd = rawLine.index(after: nextIndex)
                    while sequenceEnd < rawLine.endIndex {
                        let current = rawLine[sequenceEnd]
                        if current == "\u{0007}" {
                            sequenceEnd = rawLine.index(after: sequenceEnd)
                            break
                        }
                        if current == "\u{001B}" {
                            let terminatorIndex = rawLine.index(after: sequenceEnd)
                            if terminatorIndex < rawLine.endIndex, rawLine[terminatorIndex] == "\\" {
                                sequenceEnd = rawLine.index(after: terminatorIndex)
                                break
                            }
                        }
                        sequenceEnd = rawLine.index(after: sequenceEnd)
                    }
                    index = sequenceEnd
                    continue
                }

                index = rawLine.index(after: nextIndex)
                continue
            }

            let scalar = character.unicodeScalars.first?.value ?? 0
            if (0x80...0x9F).contains(scalar) || scalar == 0x0E || scalar == 0x0F {
                index = rawLine.index(after: index)
                continue
            }

            styledCharacters.append(
                PromptPaneStyledCharacter(
                    character: character,
                    style: currentStyle
                )
            )
            index = rawLine.index(after: index)
        }

        return PromptPaneLine(
            rawText: rawLine,
            plainText: String(styledCharacters.map(\.character)),
            styledCharacters: styledCharacters
        )
    }

    private func applySGRParameters(_ params: [Int], to style: inout PromptANSIStyle) {
        let normalizedParams = params.isEmpty ? [0] : params
        var index = 0

        while index < normalizedParams.count {
            let value = normalizedParams[index]
            switch value {
            case 0:
                style = PromptANSIStyle()
            case 2:
                style.isDim = true
            case 22:
                style.isDim = false
            case 30...37:
                style.foreground = .indexed(value - 30)
            case 38:
                if index + 2 < normalizedParams.count, normalizedParams[index + 1] == 5 {
                    style.foreground = .indexed(normalizedParams[index + 2])
                    index += 2
                } else if index + 4 < normalizedParams.count, normalizedParams[index + 1] == 2 {
                    style.foreground = .rgb(
                        normalizedParams[index + 2],
                        normalizedParams[index + 3],
                        normalizedParams[index + 4]
                    )
                    index += 4
                }
            case 40...47:
                style.background = .indexed(value - 40)
            case 48:
                if index + 2 < normalizedParams.count, normalizedParams[index + 1] == 5 {
                    style.background = .indexed(normalizedParams[index + 2])
                    index += 2
                } else if index + 4 < normalizedParams.count, normalizedParams[index + 1] == 2 {
                    style.background = .rgb(
                        normalizedParams[index + 2],
                        normalizedParams[index + 3],
                        normalizedParams[index + 4]
                    )
                    index += 4
                }
            case 39:
                style.foreground = .default
            case 49:
                style.background = .default
            case 90...97:
                style.foreground = .indexed(value - 90 + 8)
            case 100...107:
                style.background = .indexed(value - 100 + 8)
            default:
                break
            }
            index += 1
        }
    }

    private func promptCharacters(
        after marker: String,
        in characters: [PromptPaneStyledCharacter]
    ) -> [PromptPaneStyledCharacter] {
        var index = 0
        while index < characters.count, characters[index].character.isWhitespace {
            index += 1
        }

        for markerCharacter in marker {
            guard index < characters.count, characters[index].character == markerCharacter else {
                return []
            }
            index += 1
        }

        while index < characters.count, characters[index].character.isWhitespace {
            index += 1
        }

        return Array(characters[index...])
    }

    private func promptTextLooksLikePlaceholder(
        _ characters: [PromptPaneStyledCharacter],
        agentType: AgentType?
    ) -> Bool {
        let visibleCharacters = characters.filter { !$0.character.isWhitespace }
        guard !visibleCharacters.isEmpty else { return false }

        let highlightedBackgroundCount = visibleCharacters.reduce(into: 0) { count, character in
            if character.style.background != .default {
                count += 1
            }
        }

        let placeholderLikeCount = visibleCharacters.reduce(into: 0) { count, character in
            let looksPlaceholderLike: Bool = switch agentType {
            case .claude:
                // Current Claude Code renders real submitted prompts as dim white text,
                // and submitted prompts currently use a distinct non-default background.
                // Use the background as a positive signal and avoid treating dimness
                // alone as placeholder content for Claude.
                character.style.foreground.isGrayLike
            default:
                character.style.isDim || character.style.foreground.isGrayLike
            }
            if looksPlaceholderLike {
                count += 1
            }
        }

        if agentType == .claude,
           highlightedBackgroundCount * 100 >= visibleCharacters.count * 80 {
            return false
        }

        return placeholderLikeCount * 100 >= visibleCharacters.count * 80
    }

    private func codexPromptTextLooksLikeUserInput(
        _ characters: [PromptPaneStyledCharacter]
    ) -> Bool {
        let visibleCharacters = characters.filter { !$0.character.isWhitespace }
        guard !visibleCharacters.isEmpty else { return false }

        guard let anchorStyle = visibleCharacters.first?.style else { return false }
        if anchorStyle.isDim || anchorStyle.foreground.isGrayLike {
            return false
        }

        let anchorStyleCount = visibleCharacters.reduce(into: 0) { count, character in
            if character.style == anchorStyle {
                count += 1
            }
        }

        // Keep only rows where the line is mostly rendered in the same style as the
        // first prompt character after `›`.
        return anchorStyleCount * 100 >= visibleCharacters.count * 80
    }

    private func isPromptFooterDividerLine(_ line: String) -> Bool {
        let allowedScalars = CharacterSet(charactersIn: "-_=~|:;.,*+·•▪▫◦●○◆◇■□▲△▼▽▶▷◀◁─━│┆┄┅┈┉")
        var sawDividerGlyph = false

        for scalar in line.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }
            guard allowedScalars.contains(scalar) else { return false }
            sawDividerGlyph = true
        }

        return sawDividerGlyph
    }

    private func isBarePromptInputLine(_ line: String) -> Bool {
        let nonWhitespace = line.filter { !$0.isWhitespace }
        return nonWhitespace == "❯" || nonWhitespace == "›"
    }

    private func promptContinuationText(
        from line: PromptPaneLine,
        markers: [String]
    ) -> String? {
        let plainText = line.plainText
        let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !isBottomPinnedAuxiliaryLine(trimmed) else { return nil }

        let leftTrimmed = plainText.drop(while: { $0.isWhitespace })
        let leftTrimmedText = String(leftTrimmed)
        guard markers.allSatisfy({ !leftTrimmedText.hasPrefix($0) }) else { return nil }

        let leadingWhitespaceCount = plainText.prefix(while: { $0.isWhitespace }).count
        guard leadingWhitespaceCount >= 2 else { return nil }

        return trimmed
    }

    private func templatePlaceholderPrefix(from promptText: String) -> String? {
        for (open, close) in [("(", ")"), ("{", "}"), ("[", "]"), ("<", ">")] {
            guard let openCharacter = open.first,
                  promptText.hasSuffix(close),
                  let openIndex = promptText.lastIndex(of: openCharacter) else { continue }
            let prefix = promptText[..<openIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                return prefix
            }
        }
        return nil
    }

    private func extractTemplatePlaceholder(from promptText: String) -> String? {
        for (open, close) in [("(", ")"), ("{", "}"), ("[", "]"), ("<", ">")] {
            guard let openCharacter = open.first,
                  promptText.hasSuffix(close),
                  let openIndex = promptText.lastIndex(of: openCharacter) else { continue }
            let placeholderStart = promptText.index(after: openIndex)
            let placeholderEnd = promptText.index(before: promptText.endIndex)
            guard placeholderStart < placeholderEnd else { continue }
            let placeholder = promptText[placeholderStart..<placeholderEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !placeholder.isEmpty {
                return placeholder
            }
        }
        return nil
    }

    private func handlePromptTOCSelection(entryIndex: Int) {
        guard let target = PromptTOCNavigationTarget(
            entryIndex: entryIndex,
            entries: promptTOCEntries
        ) else { return }
        guard let sessionName = currentSessionName() else { return }
        guard promptTOCSessionName == sessionName else { return }

        let agentType = threadManager.agentType(for: thread, sessionName: sessionName)
        let previousNavigationTask = promptTOCNavigationTask
        previousNavigationTask?.cancel()
        let navigationGeneration = UUID()
        promptTOCNavigationGeneration = navigationGeneration
        promptTOCNavigationTask = Task { @MainActor [weak self] in
            if let previousNavigationTask {
                await previousNavigationTask.value
            }
            guard let self else { return }
            do {
                guard let refreshedEntries = await self.capturePromptEntries(
                    sessionName: sessionName,
                    agentType: agentType,
                    retryEmptyEntries: true
                ),
                !Task.isCancelled,
                self.promptTOCNavigationGeneration == navigationGeneration,
                self.currentSessionName() == sessionName,
                let entry = target.resolve(in: refreshedEntries) else {
                    throw PromptTOCNavigationError.promptUnavailable
                }
                try await TmuxService.shared.scrollHistoryLineToTop(sessionName: sessionName, lineIndex: entry.lineIndex)
                self.scheduleScrollFABVisibilityRefresh()
            } catch {
                guard !Task.isCancelled else { return }
                BannerManager.shared.show(
                    message: "Could not jump to prompt in \(self.thread.displayName(for: sessionName, at: self.currentTabIndex)).",
                    style: .error
                )
            }
        }
    }

    private func handlePromptTOCRenameFromEntry(entryIndex: Int) {
        guard entryIndex >= 0, entryIndex < promptTOCEntries.count else { return }
        guard let parentWindow = view.window else { return }
        let entry = promptTOCEntries[entryIndex]
        let thread = self.thread

        let recentPrompts = ThreadListViewController.collectRecentPrompts(for: thread, limit: 10)
        let config = AIRenameSheetConfig(
            thread: thread,
            recentPrompts: recentPrompts,
            prefillPrompt: entry.fullText,
            allowsIconRename: PersistenceService.shared.loadSettings().autoSetThreadIconFromWorkType
        )

        let sheet = AIRenameSheetController(config: config)
        sheet.present(for: parentWindow) { [weak self] result in
            guard let self, let result else { return }
            Task {
                do {
                    _ = try await self.threadManager.renameThreadFromPrompt(
                        thread,
                        prompt: result.prompt,
                        renameBranch: result.renameBranch,
                        renameDescription: result.renameDescription,
                        renameIcon: result.renameIcon
                    )
                } catch {
                    await MainActor.run {
                        BannerManager.shared.show(
                            message: "AI Rename failed: \(error.localizedDescription)",
                            style: .error
                        )
                    }
                }
            }
        }
    }

    private func handlePromptTOCDrag(_ gesture: NSPanGestureRecognizer) {
        guard !isPromptTOCPinned else { return }
        guard let tocView = promptTOCView else { return }

        switch gesture.state {
        case .began:
            promptTOCDragStartOrigin = tocView.frame.origin
        case .changed:
            let translation = gesture.translation(in: terminalContainer)
            var newOrigin = NSPoint(
                x: promptTOCDragStartOrigin.x + translation.x,
                y: promptTOCDragStartOrigin.y + translation.y
            )

            let maxX = max(0, terminalContainer.bounds.width - tocView.frame.width)
            let maxY = max(0, terminalContainer.bounds.height - tocView.frame.height)
            newOrigin.x = min(max(0, newOrigin.x), maxX)
            newOrigin.y = min(max(0, newOrigin.y), maxY)

            let top = terminalContainer.bounds.height - (newOrigin.y + tocView.frame.height)
            let trailing = newOrigin.x + tocView.frame.width - terminalContainer.bounds.width
            promptTOCTopConstraint?.constant = top
            promptTOCTrailingConstraint?.constant = trailing
            terminalContainer.layoutSubtreeIfNeeded()
        case .ended, .cancelled:
            clampPromptTOCPositionIfNeeded()
            if let sessionName = promptTOCSessionName {
                savePromptTOCPosition(for: sessionName)
            }
        default:
            break
        }
    }

    private func handlePromptTOCResize(_ gesture: NSPanGestureRecognizer, corner: TOCResizeCorner) {
        guard !isPromptTOCPinned else { return }
        guard promptTOCView != nil else { return }
        guard let widthConstraint = promptTOCWidthConstraint,
              let heightConstraint = promptTOCHeightConstraint,
              let topConstraint = promptTOCTopConstraint,
              let trailingConstraint = promptTOCTrailingConstraint else { return }

        switch gesture.state {
        case .began:
            promptTOCResizeStartSize = NSSize(width: widthConstraint.constant, height: heightConstraint.constant)
            promptTOCResizeStartTop = topConstraint.constant
            promptTOCResizeStartTrailing = trailingConstraint.constant
        case .changed:
            let dx = gesture.translation(in: terminalContainer).x
            let dy = gesture.translation(in: terminalContainer).y
            let minimumWidth = Self.promptTOCMinimumWidth
            let minimumHeight = Self.promptTOCMinimumHeight
            let maxWidth = max(minimumWidth, terminalContainer.bounds.width - 8)
            let maxHeight = max(minimumHeight, terminalContainer.bounds.height - 8)

            // Compute proposed dimensions and position changes per corner.
            // Right corners grow width with +dx; left corners grow with -dx.
            // Bottom corners grow height with -dy (AppKit y-up: drag down = negative dy).
            // Top corners grow height with +dy and move top edge up.
            let rawWidth: CGFloat
            let rawHeight: CGFloat
            let movesRightEdge: Bool  // true for corners where dragging changes the right edge
            let movesTopEdge: Bool    // true for corners where dragging changes the top edge

            switch corner {
            case .bottomRight:
                rawWidth = promptTOCResizeStartSize.width + dx
                rawHeight = promptTOCResizeStartSize.height - dy
                movesRightEdge = true
                movesTopEdge = false
            case .bottomLeft:
                rawWidth = promptTOCResizeStartSize.width - dx
                rawHeight = promptTOCResizeStartSize.height - dy
                movesRightEdge = false
                movesTopEdge = false
            case .topRight:
                rawWidth = promptTOCResizeStartSize.width + dx
                rawHeight = promptTOCResizeStartSize.height + dy
                movesRightEdge = true
                movesTopEdge = true
            case .topLeft:
                rawWidth = promptTOCResizeStartSize.width - dx
                rawHeight = promptTOCResizeStartSize.height + dy
                movesRightEdge = false
                movesTopEdge = true
            }

            let clampedWidth = min(max(minimumWidth, rawWidth), maxWidth)
            let clampedHeight = min(max(minimumHeight, rawHeight), maxHeight)

            // Adjust position constraints to keep the fixed edge anchored.
            // Use actual (clamped) deltas so the fixed edge doesn't drift at min/max limits.
            let actualWidthDelta = clampedWidth - promptTOCResizeStartSize.width
            let actualHeightDelta = clampedHeight - promptTOCResizeStartSize.height

            widthConstraint.constant = clampedWidth
            heightConstraint.constant = clampedHeight

            // Right-edge corners: update trailing so right edge tracks the drag.
            if movesRightEdge {
                trailingConstraint.constant = promptTOCResizeStartTrailing + actualWidthDelta
            }
            // Top-edge corners: update top so top edge tracks the drag.
            if movesTopEdge {
                topConstraint.constant = promptTOCResizeStartTop - actualHeightDelta
            }

            terminalContainer.layoutSubtreeIfNeeded()
            clampPromptTOCPositionIfNeeded()
        case .ended, .cancelled:
            // Capture final expanded size after user resizes.
            if let w = promptTOCWidthConstraint, let h = promptTOCHeightConstraint {
                promptTOCExpandedSize = NSSize(width: w.constant, height: h.constant)
            }
            clampPromptTOCPositionIfNeeded()
            if let sessionName = promptTOCSessionName {
                savePromptTOCSize(for: sessionName)
                savePromptTOCPosition(for: sessionName)
            }
        default:
            break
        }
    }

    private func handlePromptTOCPinnedResize(_ gesture: NSPanGestureRecognizer) {
        guard isPromptTOCPinned,
              let widthConstraint = promptTOCPinnedWidthConstraint else { return }

        switch gesture.state {
        case .began:
            promptTOCPinnedResizeStartWidth = widthConstraint.constant
        case .changed:
            let translation = gesture.translation(in: view)
            widthConstraint.constant = PromptTOCPresentationState.pinnedWidth(
                requestedWidth: promptTOCPinnedResizeStartWidth - translation.x,
                availableWidth: view.bounds.width,
                minimumTOCWidth: Self.promptTOCMinimumWidth,
                minimumContentWidth: 320
            )
            promptTOCExpandedSize.width = widthConstraint.constant
            view.layoutSubtreeIfNeeded()
        case .ended, .cancelled:
            promptTOCExpandedSize.width = widthConstraint.constant
            if let sessionName = promptTOCSessionName {
                savePromptTOCSize(for: sessionName)
            }
        default:
            break
        }
    }

    func clampPromptTOCPositionIfNeeded() {
        guard !isPromptTOCPinned else { return }
        // Skip clamping while the diff viewer is open — terminalContainer is shorter
        // during that time, and clamping would shift the TOC to a position that
        // persists incorrectly once the diff viewer is closed.
        guard diffVC == nil else { return }
        guard let tocView = promptTOCView, !tocView.isHidden else { return }
        guard let top = promptTOCTopConstraint, let trailing = promptTOCTrailingConstraint else { return }
        guard tocView.frame.width > 0, tocView.frame.height > 0 else { return }

        var origin = NSPoint(
            x: terminalContainer.bounds.width - tocView.frame.width + trailing.constant,
            y: terminalContainer.bounds.height - tocView.frame.height - top.constant
        )
        let maxX = max(0, terminalContainer.bounds.width - tocView.frame.width)
        let maxY = max(0, terminalContainer.bounds.height - tocView.frame.height)
        origin.x = min(max(0, origin.x), maxX)
        origin.y = min(max(0, origin.y), maxY)

        top.constant = terminalContainer.bounds.height - (origin.y + tocView.frame.height)
        trailing.constant = origin.x + tocView.frame.width - terminalContainer.bounds.width
    }

    private func handleTOCHoverStateChanged(_ expanded: Bool) {
        guard !isPromptTOCPinned else { return }
        guard let widthConstraint = promptTOCWidthConstraint,
              let heightConstraint = promptTOCHeightConstraint else { return }
        if expanded {
            let w = promptTOCExpandedSize.width
            let h = promptTOCExpandedSize.height
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                widthConstraint.constant = w
                heightConstraint.constant = h
                terminalContainer.layoutSubtreeIfNeeded()
            }, completionHandler: { [weak self] in
                self?.clampPromptTOCPositionIfNeeded()
            })
        } else {
            // Capture current expanded size; the actual frame shrink happens in onCollapseCompleted
            // (after the fade-out animation finishes) so content isn't clipped mid-animation.
            promptTOCExpandedSize = NSSize(width: widthConstraint.constant, height: heightConstraint.constant)
        }
    }

    func updatePromptTOCToggleButtonState(canShow: Bool) {
        // The toggle button is no longer in the toolbar — the TOC is always-on as a floating
        // capsule. Users can disable it via Settings. Keep the button hidden.
        togglePromptTOCButton.isHidden = true
    }

    func applyPromptTOCVisibility(restoringPosition: Bool = false) {
        let canShow = promptTOCCanShowForCurrentTab && showPromptTOCOverlay
        updatePromptTOCToggleButtonState(canShow: canShow)

        // The manual-hide toggle was removed in v1.2.2 (no close button/toolbar toggle).
        // Clear any stale UserDefaults flag so updated installs aren't permanently stuck hidden.
        if UserDefaults.standard.object(forKey: Self.promptTOCVisibilityDefaultsKey) != nil {
            UserDefaults.standard.removeObject(forKey: Self.promptTOCVisibilityDefaultsKey)
        }

        promptTOCView?.isHidden = !canShow
        updatePromptTOCContentLayout(isTOCVisible: canShow)

        guard canShow else { return }

        bringPromptTOCOverlayToFront()
        if restoringPosition, let sessionName = promptTOCSessionName {
            restorePromptTOCPosition(for: sessionName)
        }
        clampPromptTOCPositionIfNeeded()
    }

    private func updatePromptTOCContentLayout(isTOCVisible: Bool) {
        let mode = PromptTOCContentWidthMode.resolve(
            isPinned: isPromptTOCPinned,
            isTOCVisible: isTOCVisible
        )
        terminalTrailingToPromptTOCConstraint?.isActive = mode == .reservesTrailingTOC
        terminalTrailingToViewConstraint?.isActive = mode == .fullWidth
        view.layoutSubtreeIfNeeded()
        terminalContainer.layoutSubtreeIfNeeded()
        currentTerminalView()?.synchronizeSurfaceGeometry()
    }

    func togglePromptTOCVisibility() {
        // No-op: manual toggle UI was removed in v1.2.2. TOC visibility is controlled via Settings only.
    }

    @objc func handlePromptTOCVisibilityChanged(_ notification: Notification) {
        applyPromptTOCVisibility(restoringPosition: true)
    }

    private func savePromptTOCPosition(for sessionName: String) {
        guard !isPromptTOCPinned else { return }
        // Don't persist position while diff viewer is open — bounds are reduced and
        // the saved normalized values would be wrong relative to the full container.
        guard diffVC == nil else { return }
        guard promptTOCView != nil else { return }
        // Always normalize relative to the expanded size so drag-while-collapsed
        // produces consistent restored positions.
        let expandedWidth = promptTOCExpandedSize.width
        let expandedHeight = promptTOCExpandedSize.height
        let availableWidth = max(1, terminalContainer.bounds.width - expandedWidth)
        let availableHeight = max(1, terminalContainer.bounds.height - expandedHeight)

        let x = terminalContainer.bounds.width - expandedWidth + (promptTOCTrailingConstraint?.constant ?? 0)
        let y = terminalContainer.bounds.height - expandedHeight - (promptTOCTopConstraint?.constant ?? 0)
        let normalizedX = min(max(0, x / availableWidth), 1)
        let normalizedY = min(max(0, y / availableHeight), 1)

        UserDefaults.standard.set(
            [normalizedX, normalizedY],
            forKey: promptTOCPositionDefaultsKey(for: sessionName)
        )
    }

    private func savePromptTOCSize(for sessionName: String) {
        let storedWidth = max(Self.promptTOCMinimumWidth, promptTOCExpandedSize.width)
        let storedHeight = max(Self.promptTOCMinimumHeight, promptTOCExpandedSize.height)
        UserDefaults.standard.set(
            [storedWidth, storedHeight],
            forKey: promptTOCSizeDefaultsKey(for: sessionName)
        )
    }

    private func restorePromptTOCPosition(for sessionName: String) {
        guard !isPromptTOCPinned else { return }
        guard let values = UserDefaults.standard.array(forKey: promptTOCPositionDefaultsKey(for: sessionName)) as? [Double],
              values.count == 2,
              let top = promptTOCTopConstraint,
              let trailing = promptTOCTrailingConstraint else {
            // Default to bottom-right with generous bottom padding so the TOC
            // stays clear of the prompt / status bar area at the bottom.
            let expandedHeight = promptTOCExpandedSize.height
            let bottomPadding: CGFloat = 120
            let topConstant = terminalContainer.bounds.height - expandedHeight - bottomPadding
            promptTOCTopConstraint?.constant = max(12, topConstant)
            promptTOCTrailingConstraint?.constant = -12
            return
        }

        // Position is normalized relative to the expanded size so it remains consistent
        // regardless of whether the TOC is currently collapsed or expanded.
        let normalizedX = min(max(0, values[0]), 1)
        let normalizedY = min(max(0, values[1]), 1)
        let expandedWidth = promptTOCExpandedSize.width
        let expandedHeight = promptTOCExpandedSize.height
        let availableWidth = max(0, terminalContainer.bounds.width - expandedWidth)
        let availableHeight = max(0, terminalContainer.bounds.height - expandedHeight)
        let originX = availableWidth * normalizedX
        let originY = availableHeight * normalizedY

        top.constant = terminalContainer.bounds.height - (originY + expandedHeight)
        trailing.constant = originX + expandedWidth - terminalContainer.bounds.width
    }

    private func restorePromptTOCSize(for sessionName: String) {
        guard let values = UserDefaults.standard.array(forKey: promptTOCSizeDefaultsKey(for: sessionName)) as? [Double],
              values.count == 2 else {
            promptTOCExpandedSize = NSSize(width: Self.promptTOCMinimumWidth, height: Self.promptTOCMinimumHeight)
            promptTOCPinnedWidthConstraint?.constant = promptTOCExpandedSize.width
            return
        }

        let minimumWidth = Self.promptTOCMinimumWidth
        let minimumHeight = Self.promptTOCMinimumHeight
        let maxWidth = isPromptTOCPinned
            ? max(minimumWidth, view.bounds.width - 320)
            : max(minimumWidth, terminalContainer.bounds.width - 8)
        let maxHeight = max(minimumHeight, terminalContainer.bounds.height - 8)
        promptTOCExpandedSize = NSSize(
            width: min(max(minimumWidth, values[0]), maxWidth),
            height: min(max(minimumHeight, values[1]), maxHeight)
        )
        promptTOCPinnedWidthConstraint?.constant = promptTOCExpandedSize.width
    }

    private func promptTOCPositionDefaultsKey(for sessionName: String) -> String {
        return Self.promptTOCPositionDefaultsPrefix
    }

    private func promptTOCSizeDefaultsKey(for sessionName: String) -> String {
        return Self.promptTOCSizeDefaultsPrefix
    }

    func bringPromptTOCOverlayToFront() {
        guard let tocView = promptTOCView else { return }
        if tocView.superview === terminalContainer {
            terminalContainer.addSubview(tocView, positioned: .above, relativeTo: nil)
        } else if tocView.superview === view {
            view.addSubview(tocView, positioned: .above, relativeTo: terminalContainer)
        }
    }

    private func sanitizedDefaultsKeySegment(_ text: String) -> String {
        text.map { char in
            char.isLetter || char.isNumber ? char : "_"
        }.reduce(into: "") { $0.append($1) }
    }
}

private final class PromptTOCFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class PromptTOCLabel: NSTextField {
    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class PromptTOCNonInteractiveView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct PromptTOCTimingPresentation {
    let startText: String
    let workedText: String?
    let toolTip: String
}

private enum PromptTOCTimingFormatter {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .short
        return formatter
    }()

    static func presentation(
        for state: PromptTOCTimingPresentationState?,
        now: Date = Date()
    ) -> PromptTOCTimingPresentation? {
        guard let state else { return nil }

        let startText: String
        if let components = state.relativeStartComponents(now: now) {
            startText = relativeFormatter.localizedString(from: components)
        } else {
            startText = String(localized: .ThreadStrings.promptTOCTimingJustNow)
        }

        let exactStartFormatter = state.exactStartIncludesDate(now: now)
            ? dateTimeFormatter
            : timeFormatter
        let startToolTip = String(
            localized: .ThreadStrings.promptTOCTimingStartToolTip(
                exactStartFormatter.string(from: state.sentAt)
            )
        )
        guard let workedDuration = state.workedDuration,
              let formattedDuration = durationFormatter.string(from: workedDuration) else {
            return PromptTOCTimingPresentation(
                startText: startText,
                workedText: nil,
                toolTip: startToolTip
            )
        }

        let workedText = String(
            localized: .ThreadStrings.promptTOCTimingWorkedFor(formattedDuration)
        )
        return PromptTOCTimingPresentation(
            startText: startText,
            workedText: workedText,
            toolTip: "\(startToolTip)\n\(workedText)"
        )
    }
}

private final class PromptTOCEntryRowView: NSView {
    private static let timingSpacing: CGFloat = 8

    let entryIndex: Int
    private let ordinalBadgeView = PromptTOCNonInteractiveView()
    private let ordinalLabel: PromptTOCLabel
    private let label: PromptTOCLabel
    private let startLabel = PromptTOCLabel(labelWithString: "")
    private let workedLabel = PromptTOCLabel(labelWithString: "")
    private let timingView = PromptTOCNonInteractiveView()
    private let textStack = NSStackView()
    private var ordinalBadgeWidthConstraint: NSLayoutConstraint!
    private var timingSeparationConstraint: NSLayoutConstraint!
    private var showsAlternateBackground = false
    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    var onRightClick: ((Int, NSEvent) -> Void)?

    init(
        entryIndex: Int,
        promptText: String,
        timingPresentation: PromptTOCTimingPresentation?,
        isPinned: Bool
    ) {
        self.entryIndex = entryIndex
        self.ordinalLabel = PromptTOCLabel(labelWithString: "\(entryIndex + 1)")
        self.label = PromptTOCLabel(wrappingLabelWithString: promptText)
        super.init(frame: .zero)
        setupUI(timingPresentation: timingPresentation)
        setPinnedPresentation(isPinned)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(entryIndex, event)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateWorkedLabelVisibility()
    }

    func setAlternateBackgroundVisible(_ isVisible: Bool) {
        showsAlternateBackground = isVisible
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func refreshPrimaryColor() {
        updateAppearance()
    }

    func setPinnedPresentation(_ isPinned: Bool) {
        applyPresentation(PromptTOCRowPresentation(
            entryIndex: entryIndex,
            promptText: label.stringValue,
            isPinned: isPinned
        ))
    }

    private func setupUI(timingPresentation: PromptTOCTimingPresentation?) {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = timingPresentation?.toolTip

        ordinalBadgeView.translatesAutoresizingMaskIntoConstraints = false
        ordinalBadgeView.wantsLayer = true
        ordinalBadgeView.layer?.cornerRadius = PromptTOCOrdinalBadgeStyle.height / 2
        ordinalBadgeView.layer?.borderWidth = 0

        ordinalLabel.translatesAutoresizingMaskIntoConstraints = false
        ordinalLabel.font = .systemFont(
            ofSize: PromptTOCOrdinalBadgeStyle.fontSize,
            weight: .semibold
        )
        ordinalLabel.alignment = .center
        ordinalLabel.isSelectable = false
        ordinalLabel.isEditable = false
        ordinalLabel.focusRingType = .none
        ordinalLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        ordinalBadgeView.addSubview(ordinalLabel)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = NSColor(resource: .textPrimary)
        label.isSelectable = false
        label.isEditable = false
        label.allowsEditingTextAttributes = false
        label.focusRingType = .none
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.cell?.usesSingleLineMode = false
        label.cell?.truncatesLastVisibleLine = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        timingView.translatesAutoresizingMaskIntoConstraints = false
        timingView.isHidden = timingPresentation == nil

        startLabel.stringValue = timingPresentation?.startText ?? ""
        startLabel.translatesAutoresizingMaskIntoConstraints = false
        startLabel.textColor = .secondaryLabelColor
        startLabel.lineBreakMode = .byTruncatingTail
        startLabel.maximumNumberOfLines = 1
        startLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        workedLabel.stringValue = timingPresentation?.workedText ?? ""
        workedLabel.translatesAutoresizingMaskIntoConstraints = false
        workedLabel.textColor = .secondaryLabelColor
        workedLabel.lineBreakMode = .byClipping
        workedLabel.maximumNumberOfLines = 1
        workedLabel.isHidden = timingPresentation?.workedText == nil
        workedLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        timingView.addSubview(startLabel)
        timingView.addSubview(workedLabel)
        timingSeparationConstraint = startLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: workedLabel.leadingAnchor,
            constant: -Self.timingSpacing
        )
        NSLayoutConstraint.activate([
            startLabel.topAnchor.constraint(equalTo: timingView.topAnchor),
            startLabel.leadingAnchor.constraint(equalTo: timingView.leadingAnchor),
            startLabel.bottomAnchor.constraint(equalTo: timingView.bottomAnchor),
            startLabel.trailingAnchor.constraint(lessThanOrEqualTo: timingView.trailingAnchor),
            workedLabel.topAnchor.constraint(equalTo: timingView.topAnchor),
            workedLabel.trailingAnchor.constraint(equalTo: timingView.trailingAnchor),
            workedLabel.bottomAnchor.constraint(equalTo: timingView.bottomAnchor),
        ])

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.addArrangedSubview(label)
        textStack.addArrangedSubview(timingView)

        addSubview(ordinalBadgeView)
        addSubview(textStack)
        ordinalBadgeWidthConstraint = ordinalBadgeView.widthAnchor.constraint(
            equalToConstant: PromptTOCOrdinalBadgeStyle.height
        )
        NSLayoutConstraint.activate([
            ordinalBadgeView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            ordinalBadgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            ordinalBadgeWidthConstraint,
            ordinalBadgeView.heightAnchor.constraint(equalToConstant: PromptTOCOrdinalBadgeStyle.height),
            ordinalBadgeView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),

            ordinalLabel.centerXAnchor.constraint(equalTo: ordinalBadgeView.centerXAnchor),
            ordinalLabel.centerYAnchor.constraint(equalTo: ordinalBadgeView.centerYAnchor),
            ordinalLabel.leadingAnchor.constraint(greaterThanOrEqualTo: ordinalBadgeView.leadingAnchor, constant: 2),
            ordinalLabel.trailingAnchor.constraint(lessThanOrEqualTo: ordinalBadgeView.trailingAnchor, constant: -2),

            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            textStack.leadingAnchor.constraint(equalTo: ordinalBadgeView.trailingAnchor, constant: 6),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            label.widthAnchor.constraint(equalTo: textStack.widthAnchor),
            timingView.widthAnchor.constraint(equalTo: textStack.widthAnchor),
        ])

        updateAppearance()
    }

    private func applyPresentation(_ presentation: PromptTOCRowPresentation) {
        ordinalLabel.stringValue = presentation.ordinalText
        label.stringValue = presentation.promptText
        label.font = .monospacedSystemFont(ofSize: presentation.promptFontSize, weight: .regular)
        label.maximumNumberOfLines = presentation.maximumPromptLines
        let timingFont = NSFont.systemFont(ofSize: presentation.promptFontSize - 2, weight: .regular)
        startLabel.font = timingFont
        workedLabel.font = timingFont
        ordinalBadgeWidthConstraint.constant = presentation.ordinalBadgeWidth
        label.invalidateIntrinsicContentSize()
        startLabel.invalidateIntrinsicContentSize()
        workedLabel.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        superview?.invalidateIntrinsicContentSize()
        superview?.needsLayout = true
        needsLayout = true
    }

    private func updateWorkedLabelVisibility() {
        guard !workedLabel.stringValue.isEmpty else {
            workedLabel.isHidden = true
            timingSeparationConstraint.isActive = false
            return
        }

        let shouldShow = PromptTOCTimingPresentationState.shouldShowWorkedDuration(
            availableWidth: timingView.bounds.width,
            startWidth: startLabel.intrinsicContentSize.width,
            durationWidth: workedLabel.intrinsicContentSize.width,
            spacing: Self.timingSpacing
        )
        if workedLabel.isHidden == shouldShow {
            workedLabel.isHidden = !shouldShow
        }
        if timingSeparationConstraint.isActive != shouldShow {
            timingSeparationConstraint.isActive = shouldShow
        }
    }

    private func updateAppearance() {
        guard let layer else { return }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.borderWidth = 1
            ordinalBadgeView.layer?.backgroundColor = (
                isSelected
                    ? NSColor.appPrimary.withAlphaComponent(0.22)
                    : NSColor.labelColor.withAlphaComponent(0.14)
            ).cgColor
            ordinalBadgeView.layer?.borderWidth = 0
            let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ordinalLabel.textColor = PromptTOCOrdinalBadgeStyle.numberColor(
                isDarkAppearance: isDark
            )

            if isSelected {
                layer.backgroundColor = NSColor.appPrimary.withAlphaComponent(0.18).cgColor
                layer.borderColor = NSColor.appPrimary.withAlphaComponent(0.55).cgColor
                return
            }

            layer.borderColor = NSColor.clear.cgColor
            layer.backgroundColor = showsAlternateBackground
                ? NSColor.separatorColor.withAlphaComponent(isDark ? 0.08 : 0.14).cgColor
                : NSColor.clear.cgColor
        }
    }
}

enum TOCResizeCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

final class PromptTOCPinnedResizeHandleView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        PromptTOCPinnedResizeStyle.dividerColor.setFill()
        PromptTOCPinnedResizeStyle.dividerRect(in: bounds).fill()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: PromptTOCPinnedResizeStyle.cursor)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

final class PromptTableOfContentsView: NSView {
    var onSelectEntry: ((Int) -> Void)?
    var onRenameFromEntry: ((Int) -> Void)?
    var onDragGesture: ((NSPanGestureRecognizer) -> Void)?
    var onResizeGesture: ((NSPanGestureRecognizer, TOCResizeCorner) -> Void)?
    var onHoverStateChanged: ((Bool) -> Void)?
    var onCollapseCompleted: (() -> Void)?
    var onPinnedResizeGesture: ((NSPanGestureRecognizer) -> Void)?
    var onPinToggle: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Table of Contents")
    private let countBadgeView = NSView()
    private let countLabel = NSTextField(labelWithString: "0")
    private let rowsStack = NSStackView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No prompts yet")
    private let spinner = NSProgressIndicator()
    private let headerBackgroundView = NSView()
    private let headerIcon = NSImageView()
    private let pinButton = NSButton()
    private let pinnedResizeHandle = PromptTOCPinnedResizeHandleView()
    private var resizeHandleIconView: NSImageView?
    private var cornerHandleViews: [NSView] = []
    private var countBadgeWidthConstraint: NSLayoutConstraint?
    private var scrollBottomConstraint: NSLayoutConstraint!
    private var scrollViewCollapseConstraint: NSLayoutConstraint!
    private var rowViews: [PromptTOCEntryRowView] = []
    private var selectedEntryIndex: Int?
    private var tocEntries: [PromptTOCEntry] = []
    private var presentationState = PromptTOCPresentationState(isPinned: false, isHovered: false)
    private(set) var isExpanded = false
    private var shouldRestoreScrollToTopAfterReload = true
    private var preservedScrollOffsetY: CGFloat = 0
    private var previouslyNewestEntry: PromptTOCEntry?

    private static let normalAlpha: CGFloat = 0.55
    private static let hoverAlpha: CGFloat = 0.95
    private static let topAutoScrollTolerance: CGFloat = 24

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLoading(agentType: AgentType?) {
        preservedScrollOffsetY = currentScrollOffsetY()
        shouldRestoreScrollToTopAfterReload = isScrolledToTopOrNearTop()
        previouslyNewestEntry = tocEntries.last
        updateCountLabel("…")
        spinner.isHidden = false
        spinner.startAnimation(nil)
        emptyLabel.isHidden = true
        clearRows()
    }

    func setEntries(
        _ entries: [PromptTOCEntry],
        agentType: AgentType?
    ) {
        let previousSelection = selectedEntryIndex
        let previousNewestEntry = tocEntries.last
        let previousEntryCount = tocEntries.count
        let previousNewestEntryIndex = previousNewestEntry.flatMap { previous in
            entries.lastIndex {
                $0.lineIndex == previous.lineIndex && $0.fullText == previous.fullText
            }
        }
        let didAppendNewestEntry = PromptTOCListPresentation.didAppendNewestEntry(
            previousEntryCount: previousEntryCount,
            currentEntryCount: entries.count,
            previousNewestEntryIndex: previousNewestEntryIndex
        )
        let shouldScrollToTop = shouldRestoreScrollToTopAfterReload
        tocEntries = entries
        updateCountLabel("\(entries.count)")
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        clearRows()

        guard !entries.isEmpty else {
            selectedEntryIndex = nil
            emptyLabel.stringValue = "No prompts yet"
            emptyLabel.isHidden = false
            shouldRestoreScrollToTopAfterReload = false
            previouslyNewestEntry = nil
            return
        }

        emptyLabel.isHidden = true
        for (displayIndex, entryIndex) in PromptTOCListPresentation
            .displayEntryIndexes(entryCount: entries.count)
            .enumerated() {
            let entry = entries[entryIndex]
            let row = PromptTOCEntryRowView(
                entryIndex: entryIndex,
                promptText: entry.displayText,
                timingPresentation: PromptTOCTimingFormatter.presentation(
                    for: PromptTOCTimingPresentationState(timing: entry.timing)
                ),
                isPinned: presentationState.isPinned
            )
            row.setAlternateBackgroundVisible(!displayIndex.isMultiple(of: 2))

            let tap = NSClickGestureRecognizer(target: self, action: #selector(handleEntryRowTap(_:)))
            row.addGestureRecognizer(tap)
            row.onRightClick = { [weak self] index, event in
                self?.showRenameContextMenu(for: index, event: event)
            }

            rowsStack.addArrangedSubview(row)
            rowViews.append(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: rowsStack.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: rowsStack.trailingAnchor),
            ])
        }

        if let selection = PromptTOCListPresentation.selectedEntryIndex(
            previousSelection: previousSelection,
            entryCount: entries.count,
            didAppendNewestEntry: didAppendNewestEntry
        ) {
            updateSelection(for: selection)
        }

        layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        if shouldScrollToTop {
            scrollToTop()
        } else {
            restoreScrollOffset(entries: entries)
        }
        shouldRestoreScrollToTopAfterReload = false
        previouslyNewestEntry = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func refreshPrimaryColor() {
        updateAppearance()
        rowViews.forEach { $0.refreshPrimaryColor() }
    }

    func setPinned(_ pinned: Bool) {
        presentationState.isPinned = pinned
        isExpanded = presentationState.isExpanded
        headerBackgroundView.layer?.cornerRadius = pinned ? 0 : 8
        headerBackgroundView.layer?.maskedCorners = pinned
            ? []
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        updatePinButton()
        pinnedResizeHandle.isHidden = !pinned
        rowViews.forEach { $0.setPinnedPresentation(pinned) }
        rowsStack.invalidateIntrinsicContentSize()
        rowsStack.needsLayout = true
        scrollView.documentView?.needsLayout = true
        layoutSubtreeIfNeeded()

        if pinned {
            alphaValue = Self.hoverAlpha
            setCollapsedState(false, animated: false)
        } else {
            updateBackground(animated: false)
            setCollapsedState(!presentationState.isExpanded, animated: false)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        presentationState.isHovered = true
        isExpanded = presentationState.isExpanded
        updatePinButton()
        updateBackground(animated: true)
        guard !presentationState.isPinned else { return }
        setCollapsedState(false, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        presentationState.isHovered = false
        isExpanded = presentationState.isExpanded
        updatePinButton()
        updateBackground(animated: true)
        guard !presentationState.isPinned else { return }
        setCollapsedState(true, animated: true)
    }

    private func updateBackground(animated: Bool) {
        let target = presentationState.isExpanded ? Self.hoverAlpha : Self.normalAlpha
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = presentationState.isExpanded ? 0.15 : 0.22
                self.animator().alphaValue = target
            }
        } else {
            alphaValue = target
        }
    }

    private func setupUI() {
        wantsLayer = true
        // Keep TOC above terminal surfaces that are added later.
        layer?.zPosition = 10
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        alphaValue = Self.normalAlpha
        layer?.borderWidth = 0

        headerBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        headerBackgroundView.wantsLayer = true
        headerBackgroundView.layer?.cornerRadius = 8
        headerBackgroundView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        headerIcon.image = NSImage(systemSymbolName: "list.bullet.rectangle.portrait", accessibilityDescription: nil)
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        headerIcon.widthAnchor.constraint(equalToConstant: 12).isActive = true
        headerIcon.heightAnchor.constraint(equalToConstant: 12).isActive = true

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = NSColor(resource: .textPrimary)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countLabel.font = PromptTOCHeaderLayout.countFont
        countLabel.textColor = NSColor(resource: .textPrimary)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.lineBreakMode = .byClipping
        countLabel.cell?.truncatesLastVisibleLine = false
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentHuggingPriority(.required, for: .vertical)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        countBadgeView.translatesAutoresizingMaskIntoConstraints = false
        countBadgeView.wantsLayer = true
        countBadgeView.layer?.cornerRadius = 10
        countBadgeView.layer?.masksToBounds = true
        countBadgeView.setContentHuggingPriority(.required, for: .horizontal)
        countBadgeView.setContentHuggingPriority(.required, for: .vertical)
        countBadgeView.setContentCompressionResistancePriority(.required, for: .horizontal)
        countBadgeView.setContentCompressionResistancePriority(.required, for: .vertical)
        countBadgeView.addSubview(countLabel)
        let countBadgeWidthConstraint = countBadgeView.widthAnchor.constraint(
            equalToConstant: PromptTOCHeaderLayout.countBadgeWidth(for: countLabel.stringValue)
        )
        self.countBadgeWidthConstraint = countBadgeWidthConstraint
        NSLayoutConstraint.activate([
            countBadgeView.heightAnchor.constraint(equalToConstant: 20),
            countBadgeWidthConstraint,
            countLabel.centerYAnchor.constraint(equalTo: countBadgeView.centerYAnchor),
            countLabel.leadingAnchor.constraint(
                equalTo: countBadgeView.leadingAnchor,
                constant: PromptTOCHeaderLayout.countLabelHorizontalInset
            ),
            countLabel.trailingAnchor.constraint(
                equalTo: countBadgeView.trailingAnchor,
                constant: -PromptTOCHeaderLayout.countLabelHorizontalInset
            ),
        ])

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        spinner.setContentHuggingPriority(.required, for: .horizontal)
        spinner.setContentCompressionResistancePriority(.required, for: .horizontal)

        pinButton.bezelStyle = .inline
        pinButton.isBordered = false
        pinButton.imagePosition = .imageOnly
        pinButton.translatesAutoresizingMaskIntoConstraints = false
        pinButton.target = self
        pinButton.action = #selector(handlePinToggle)
        pinButton.setContentHuggingPriority(.required, for: .horizontal)
        pinButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            pinButton.widthAnchor.constraint(equalToConstant: 20),
            pinButton.heightAnchor.constraint(equalToConstant: 20),
        ])
        updatePinButton()

        let flexibleSpacer = NSView()
        flexibleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        flexibleSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let headerStack = NSStackView(
            views: [headerIcon, titleLabel, flexibleSpacer, countBadgeView, spinner, pinButton]
        )
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 5
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        headerStack.addGestureRecognizer(pan)

        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 2
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        let rowsContainer = PromptTOCFlippedView()
        rowsContainer.translatesAutoresizingMaskIntoConstraints = false
        rowsContainer.addSubview(rowsStack)

        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: rowsContainer.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: rowsContainer.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: rowsContainer.trailingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: rowsContainer.bottomAnchor),
            rowsStack.widthAnchor.constraint(equalTo: rowsContainer.widthAnchor),
        ])

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = rowsContainer
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        rowsContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true

        emptyLabel.font = .systemFont(ofSize: 11, weight: .regular)
        emptyLabel.textColor = NSColor(resource: .textSecondary)
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        let cornerSize: CGFloat = 18
        let cornerHandles = makeCornerHandles(size: cornerSize)
        cornerHandleViews = cornerHandles

        pinnedResizeHandle.translatesAutoresizingMaskIntoConstraints = false
        pinnedResizeHandle.isHidden = true
        let pinnedResizePan = NSPanGestureRecognizer(target: self, action: #selector(handlePinnedResize(_:)))
        pinnedResizeHandle.addGestureRecognizer(pinnedResizePan)

        addSubview(headerBackgroundView)
        addSubview(headerStack)
        addSubview(scrollView)
        addSubview(emptyLabel)
        for handle in cornerHandles { addSubview(handle) }
        addSubview(pinnedResizeHandle)

        scrollBottomConstraint = scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        scrollViewCollapseConstraint = scrollView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            headerBackgroundView.topAnchor.constraint(equalTo: topAnchor),
            headerBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBackgroundView.bottomAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),

            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollBottomConstraint,

            emptyLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            // Corner handles — placed at the 4 corners, layered above scroll content.
            cornerHandles[0].widthAnchor.constraint(equalToConstant: cornerSize),
            cornerHandles[0].heightAnchor.constraint(equalToConstant: cornerSize),
            cornerHandles[0].leadingAnchor.constraint(equalTo: leadingAnchor),
            cornerHandles[0].topAnchor.constraint(equalTo: topAnchor),

            cornerHandles[1].widthAnchor.constraint(equalToConstant: cornerSize),
            cornerHandles[1].heightAnchor.constraint(equalToConstant: cornerSize),
            cornerHandles[1].trailingAnchor.constraint(equalTo: trailingAnchor),
            cornerHandles[1].topAnchor.constraint(equalTo: topAnchor),

            cornerHandles[2].widthAnchor.constraint(equalToConstant: cornerSize),
            cornerHandles[2].heightAnchor.constraint(equalToConstant: cornerSize),
            cornerHandles[2].leadingAnchor.constraint(equalTo: leadingAnchor),
            cornerHandles[2].bottomAnchor.constraint(equalTo: bottomAnchor),

            cornerHandles[3].widthAnchor.constraint(equalToConstant: cornerSize),
            cornerHandles[3].heightAnchor.constraint(equalToConstant: cornerSize),
            cornerHandles[3].trailingAnchor.constraint(equalTo: trailingAnchor),
            cornerHandles[3].bottomAnchor.constraint(equalTo: bottomAnchor),

            pinnedResizeHandle.topAnchor.constraint(equalTo: topAnchor),
            pinnedResizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
            pinnedResizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            pinnedResizeHandle.widthAnchor.constraint(equalToConstant: 8),
        ])

        updateAppearance()
        setCollapsedState(true, animated: false)
    }

    private func applyScrollConstraints(collapsed: Bool) {
        scrollViewCollapseConstraint.isActive = collapsed
        scrollBottomConstraint.isActive = !collapsed
    }

    private func setCollapsedState(_ collapsed: Bool, animated: Bool) {
        let targetRadius: CGFloat = presentationState.isPinned ? 0 : (collapsed ? 18 : 8)

        if animated {
            // Animate corner radius via CABasicAnimation (not covered by NSAnimationContext).
            let anim = CABasicAnimation(keyPath: "cornerRadius")
            anim.fromValue = layer?.cornerRadius
            anim.toValue = targetRadius
            anim.duration = collapsed ? 0.15 : 0.22
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(anim, forKey: "tocCornerRadius")

            if !collapsed {
                // Start header background animation at the same time as frame expand (0.22s) + content delay (0.20s) + fade (0.14s) = 0.56s total
                let targetColor = NSColor.separatorColor.withAlphaComponent(0.14)
                let headerBgAnim = CABasicAnimation(keyPath: "backgroundColor")
                headerBgAnim.fromValue = NSColor.clear.cgColor
                headerBgAnim.toValue = targetColor.cgColor
                headerBgAnim.duration = 0.56
                headerBgAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                headerBgAnim.fillMode = .forwards
                headerBgAnim.isRemovedOnCompletion = false
                headerBackgroundView.layer?.add(headerBgAnim, forKey: "headerBgExpand")
                headerBackgroundView.layer?.backgroundColor = targetColor.cgColor
            }

            if !collapsed {
                // Expanding: swap constraints so scroll content is laid out inside the growing
                // frame, then notify the controller to start the frame animation.
                applyScrollConstraints(collapsed: false)
                onHoverStateChanged?(true)

                // Delay content reveal until AFTER the frame has finished expanding so rows
                // don't appear to clip/slide in from the top while the panel is growing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
                    guard let self, self.isExpanded else { return }
                    self.scrollView.alphaValue = 0
                    self.scrollView.isHidden = false
                    self.headerBackgroundView.alphaValue = 0
                    self.headerBackgroundView.isHidden = false
                    self.cornerHandleViews.forEach {
                        $0.alphaValue = 0
                        $0.isHidden = !self.presentationState.showsCornerResizeHandles
                    }

                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.14
                        self.scrollView.animator().alphaValue = 1
                        self.headerBackgroundView.animator().alphaValue = 1
                        self.cornerHandleViews.forEach { $0.animator().alphaValue = 1 }
                    }
                }
            } else {
                // Collapsing: notify controller to capture the expanded size, then fade out.
                onHoverStateChanged?(false)
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.13
                    scrollView.animator().alphaValue = 0
                    headerBackgroundView.animator().alphaValue = 0
                    cornerHandleViews.forEach { $0.animator().alphaValue = 0 }
                }, completionHandler: { [weak self] in
                    guard let self else { return }
                    // Guard against re-hover: if the user entered before this completion fired,
                    // skip the constraint swap and content hide — the expand path already owns them.
                    guard !self.isExpanded else { return }
                    self.scrollView.isHidden = true
                    self.headerBackgroundView.isHidden = true
                    self.emptyLabel.isHidden = true
                    self.cornerHandleViews.forEach { $0.isHidden = true }
                    self.scrollView.alphaValue = 1
                    self.headerBackgroundView.alphaValue = 1
                    self.cornerHandleViews.forEach { $0.alphaValue = 1 }
                    self.applyScrollConstraints(collapsed: true)
                    self.onCollapseCompleted?()
                })
            }
        } else {
            applyScrollConstraints(collapsed: collapsed)
            scrollView.isHidden = collapsed
            headerBackgroundView.isHidden = collapsed
            if collapsed { emptyLabel.isHidden = true }
            cornerHandleViews.forEach { $0.isHidden = !presentationState.showsCornerResizeHandles }
        }

        layer?.cornerRadius = targetRadius
    }

    private func clearRows() {
        rowViews.removeAll()
        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func updateCountLabel(_ text: String) {
        countLabel.stringValue = text
        countBadgeWidthConstraint?.constant = PromptTOCHeaderLayout.countBadgeWidth(for: text)
    }

    private func currentScrollOffsetY() -> CGFloat {
        scrollView.contentView.bounds.origin.y
    }

    private func isScrolledToTopOrNearTop() -> Bool {
        PromptTOCListPresentation.isAtNewestEdge(
            offsetY: currentScrollOffsetY(),
            tolerance: Self.topAutoScrollTolerance
        )
    }

    private func scrollToTop() {
        let contentView = scrollView.contentView
        contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(contentView)
    }

    private func restoreScrollOffset(entries: [PromptTOCEntry]) {
        guard let documentView = scrollView.documentView else { return }
        let contentView = scrollView.contentView
        let maxOffsetY = max(0, documentView.frame.height - contentView.bounds.height)
        let insertedContentHeight = previouslyNewestEntry
            .flatMap { previousNewestEntryIndex($0, in: entries) }
            .flatMap { entryIndex in
                rowViews.first(where: { $0.entryIndex == entryIndex })
            }
            .map { row in
                row.convert(row.bounds, to: documentView).minY
            } ?? 0
        let preservedOffset = PromptTOCListPresentation.preservedOlderOffset(
            previousOffsetY: preservedScrollOffsetY,
            insertedContentHeight: insertedContentHeight
        )
        let targetOffsetY = min(max(0, preservedOffset), maxOffsetY)
        contentView.scroll(to: NSPoint(x: 0, y: targetOffsetY))
        scrollView.reflectScrolledClipView(contentView)
    }

    private func previousNewestEntryIndex(
        _ previousNewestEntry: PromptTOCEntry,
        in entries: [PromptTOCEntry]
    ) -> Int? {
        entries.lastIndex {
            $0.lineIndex == previousNewestEntry.lineIndex &&
                $0.fullText == previousNewestEntry.fullText
        } ?? entries.lastIndex {
            $0.fullText == previousNewestEntry.fullText
        }
    }

    @objc private func handleEntryRowTap(_ gesture: NSClickGestureRecognizer) {
        guard let row = gesture.view as? PromptTOCEntryRowView else { return }
        updateSelection(for: row.entryIndex)
        onSelectEntry?(row.entryIndex)
    }

    private func showRenameContextMenu(for entryIndex: Int, event: NSEvent) {
        let menu = NSMenu()

        let copyItem = NSMenuItem(
            title: "Copy prompt",
            action: #selector(handleCopyPromptFromContextMenu(_:)),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyItem.representedObject = NSNumber(value: entryIndex)
        menu.addItem(copyItem)

        menu.addItem(.separator())

        let renameItem = NSMenuItem(
            title: "AI Rename…",
            action: #selector(handleRenameFromContextMenu(_:)),
            keyEquivalent: ""
        )
        renameItem.target = self
        renameItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
        renameItem.representedObject = NSNumber(value: entryIndex)
        menu.addItem(renameItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func handleCopyPromptFromContextMenu(_ sender: NSMenuItem) {
        guard let index = (sender.representedObject as? NSNumber)?.intValue,
              index < tocEntries.count else { return }
        let text = tocEntries[index].fullText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func handleRenameFromContextMenu(_ sender: NSMenuItem) {
        guard let index = (sender.representedObject as? NSNumber)?.intValue else { return }
        onRenameFromEntry?(index)
    }

    @objc private func handleDrag(_ gesture: NSPanGestureRecognizer) {
        guard !presentationState.isPinned else { return }
        onDragGesture?(gesture)
    }

    @objc private func handlePinnedResize(_ gesture: NSPanGestureRecognizer) {
        onPinnedResizeGesture?(gesture)
    }

    @objc private func handlePinToggle() {
        onPinToggle?()
    }

    private func updatePinButton() {
        let title = presentationState.isPinned
            ? String(localized: .CommonStrings.commonUnpin)
            : String(localized: .CommonStrings.commonPin)
        let symbolName = presentationState.isPinned ? "pin.slash" : "pin"
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        pinButton.toolTip = title
        pinButton.isHidden = !presentationState.showsPinButton
    }

    @objc private func handleResizeTopLeft(_ gesture: NSPanGestureRecognizer) {
        onResizeGesture?(gesture, .topLeft)
    }

    @objc private func handleResizeTopRight(_ gesture: NSPanGestureRecognizer) {
        onResizeGesture?(gesture, .topRight)
    }

    @objc private func handleResizeBottomLeft(_ gesture: NSPanGestureRecognizer) {
        onResizeGesture?(gesture, .bottomLeft)
    }

    @objc private func handleResizeBottomRight(_ gesture: NSPanGestureRecognizer) {
        onResizeGesture?(gesture, .bottomRight)
    }

    // Returns corner handles in order: [topLeft, topRight, bottomLeft, bottomRight].
    private func makeCornerHandles(size: CGFloat) -> [NSView] {
        let corners: [(TOCResizeCorner, Selector)] = [
            (.topLeft,     #selector(handleResizeTopLeft(_:))),
            (.topRight,    #selector(handleResizeTopRight(_:))),
            (.bottomLeft,  #selector(handleResizeBottomLeft(_:))),
            (.bottomRight, #selector(handleResizeBottomRight(_:))),
        ]
        return corners.map { corner, selector in
            let view = NSView()
            view.translatesAutoresizingMaskIntoConstraints = false
            let pan = NSPanGestureRecognizer(target: self, action: selector)
            view.addGestureRecognizer(pan)

            // Show the resize icon at the bottom-right corner only.
            if corner == .bottomRight {
                let icon = NSImageView()
                icon.image = NSImage(
                    systemSymbolName: "arrow.up.left.and.arrow.down.right",
                    accessibilityDescription: "Resize Table of Contents"
                )
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.toolTip = "Drag to resize"
                view.addSubview(icon)
                resizeHandleIconView = icon
                NSLayoutConstraint.activate([
                    icon.widthAnchor.constraint(equalToConstant: 12),
                    icon.heightAnchor.constraint(equalToConstant: 12),
                    icon.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
                    icon.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -3),
                ])
            }
            return view
        }
    }

    private func updateSelection(for entryIndex: Int) {
        selectedEntryIndex = entryIndex
        for row in rowViews {
            row.isSelected = row.entryIndex == entryIndex
        }
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let backgroundColor: NSColor
            if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                backgroundColor = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.14, alpha: 0.94)
            } else {
                backgroundColor = NSColor(srgbRed: 0.92, green: 0.92, blue: 0.93, alpha: 0.94)
            }
            layer?.backgroundColor = backgroundColor.cgColor

            headerBackgroundView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.14).cgColor

            headerIcon.contentTintColor = NSColor(resource: .textSecondary)
            pinButton.contentTintColor = NSColor(resource: .textSecondary)
            resizeHandleIconView?.contentTintColor = NSColor(resource: .textSecondary).withAlphaComponent(0.8)
            countBadgeView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
            countLabel.textColor = NSColor(resource: .textPrimary)
        }
    }
}
