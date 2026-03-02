import AppKit
import Foundation

extension ThreadManager {

    // MARK: - Rate-Limit Detection

    func checkForRateLimitedSessions() async {
        let now = Date()
        var changedThreadIds = Set<UUID>()
        var didChangeGlobalCache = pruneExpiredGlobalRateLimits(now: now, changedThreadIds: &changedThreadIds)

        for i in threads.indices {
            guard !threads[i].isArchived else { continue }
            let thread = threads[i]
            var updatedRateLimits = thread.rateLimitedSessions
            let validSessions = Set(thread.tmuxSessionNames)

            for sessionName in thread.tmuxSessionNames {
                guard thread.agentTmuxSessions.contains(sessionName) else {
                    if updatedRateLimits.removeValue(forKey: sessionName) != nil {
                        changedThreadIds.insert(thread.id)
                    }
                    continue
                }

                guard let sessionAgent = agentType(for: thread, sessionName: sessionName),
                      isRateLimitTrackable(agent: sessionAgent) else {
                    if updatedRateLimits.removeValue(forKey: sessionName) != nil {
                        changedThreadIds.insert(thread.id)
                    }
                    continue
                }

                let cachedGlobalInfo = activeGlobalRateLimit(for: sessionAgent, now: now)
                if let cachedGlobalInfo, updatedRateLimits[sessionName] != cachedGlobalInfo {
                    updatedRateLimits[sessionName] = cachedGlobalInfo
                    changedThreadIds.insert(thread.id)
                }

                guard let paneContent = await tmux.capturePane(sessionName: sessionName, lastLines: 120),
                      var info = rateLimitInfo(from: paneContent, now: now) else {
                    if cachedGlobalInfo == nil, updatedRateLimits.removeValue(forKey: sessionName) != nil {
                        changedThreadIds.insert(thread.id)
                    }
                    continue
                }

                // If the visible message hasn't changed, keep the previously parsed reset date.
                // This avoids drifting reset times for static phrases like "try again in 35m".
                if let existing = updatedRateLimits[sessionName],
                   existing.resetDescription == info.resetDescription,
                   let existingResetAt = existing.resetAt,
                   existingResetAt > now {
                    info.resetAt = existingResetAt
                }

                if info.resetAt.map({ $0 <= now }) ?? false {
                    if cachedGlobalInfo == nil, updatedRateLimits.removeValue(forKey: sessionName) != nil {
                        changedThreadIds.insert(thread.id)
                    }
                    continue
                }

                if updatedRateLimits[sessionName] != info {
                    updatedRateLimits[sessionName] = info
                    changedThreadIds.insert(thread.id)
                }
                if globalAgentRateLimits[sessionAgent] != info {
                    globalAgentRateLimits[sessionAgent] = info
                    didChangeGlobalCache = true
                }
            }

            for sessionName in Array(updatedRateLimits.keys) where !validSessions.contains(sessionName) {
                updatedRateLimits.removeValue(forKey: sessionName)
                changedThreadIds.insert(thread.id)
            }

            if updatedRateLimits != thread.rateLimitedSessions {
                threads[i].rateLimitedSessions = updatedRateLimits
                changedThreadIds.insert(thread.id)
            }
        }

        if !changedThreadIds.isEmpty {
            await MainActor.run {
                delegate?.threadManager(self, didUpdateThreads: threads)
                for threadId in changedThreadIds {
                    NotificationCenter.default.post(
                        name: .magentAgentRateLimitChanged,
                        object: self,
                        userInfo: ["threadId": threadId]
                    )
                }
            }
        }

        if didChangeGlobalCache {
            // Keep last-published summary in sync with explicit cache changes.
            lastPublishedRateLimitSummary = nil
        }
        await publishRateLimitSummaryIfNeeded()
    }

    private func isRateLimitTrackable(agent: AgentType) -> Bool {
        return agent == .claude || agent == .codex
    }

    private func activeGlobalRateLimit(for agent: AgentType, now: Date) -> AgentRateLimitInfo? {
        guard let info = globalAgentRateLimits[agent] else { return nil }
        if let resetAt = info.resetAt, resetAt <= now {
            return nil
        }
        return info
    }

    @discardableResult
    private func pruneExpiredGlobalRateLimits(now: Date, changedThreadIds: inout Set<UUID>) -> Bool {
        let expiredAgents = globalAgentRateLimits.compactMap { entry -> AgentType? in
            guard let resetAt = entry.value.resetAt, resetAt <= now else { return nil }
            return entry.key
        }
        guard !expiredAgents.isEmpty else { return false }

        for agent in expiredAgents {
            globalAgentRateLimits.removeValue(forKey: agent)
            clearRateLimitMarkers(for: agent, changedThreadIds: &changedThreadIds)
        }
        return true
    }

    func publishRateLimitSummaryIfNeeded() async {
        let summary = globalRateLimitSummaryText()
        guard summary != lastPublishedRateLimitSummary else { return }
        lastPublishedRateLimitSummary = summary
        await MainActor.run {
            NotificationCenter.default.post(
                name: .magentGlobalRateLimitSummaryChanged,
                object: self
            )
        }
    }

    private func clearRateLimitMarkers(for agent: AgentType, changedThreadIds: inout Set<UUID>) {
        for i in threads.indices {
            var filtered = threads[i].rateLimitedSessions
            let keysToRemove = filtered.keys.filter { sessionName in
                agentType(for: threads[i], sessionName: sessionName) == agent
            }
            guard !keysToRemove.isEmpty else { continue }
            for key in keysToRemove {
                filtered.removeValue(forKey: key)
            }
            threads[i].rateLimitedSessions = filtered
            changedThreadIds.insert(threads[i].id)
        }
    }

    /// If an agent starts processing work after being rate-limited, clear the rate-limit
    /// cache for that agent globally and remove markers from all tabs using it.
    @discardableResult
    func clearRateLimitAfterRecovery(threadIndex: Int, sessionName: String) -> Set<UUID> {
        guard threads.indices.contains(threadIndex) else { return [] }
        let thread = threads[threadIndex]
        guard let agent = agentType(for: thread, sessionName: sessionName),
              isRateLimitTrackable(agent: agent) else {
            return []
        }

        let hadSessionMarker = thread.rateLimitedSessions[sessionName] != nil
        let hadGlobalMarker = globalAgentRateLimits[agent] != nil
        guard hadSessionMarker || hadGlobalMarker else { return [] }

        globalAgentRateLimits.removeValue(forKey: agent)
        lastPublishedRateLimitSummary = nil

        var changedThreadIds = Set<UUID>()
        clearRateLimitMarkers(for: agent, changedThreadIds: &changedThreadIds)
        return changedThreadIds
    }

    // MARK: - Rate-Limit Parsing

    func rateLimitInfo(from paneContent: String, now: Date) -> AgentRateLimitInfo? {
        let lines = paneContent.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let tail = lines.suffix(80).map(String.init)
        let normalizedRecentTail = tail.suffix(20).joined(separator: "\n").lowercased()

        // Strong indicators — unambiguously mean the agent is blocked.
        let hasStrongIndicator = normalizedRecentTail.contains("too many requests")
            || normalizedRecentTail.contains("quota exceeded")
            || normalizedRecentTail.contains("retry after")
            || normalizedRecentTail.contains("try again in")
            || normalizedRecentTail.contains("limit reached")
            || normalizedRecentTail.contains("limit exceeded")
            || normalizedRecentTail.contains("rate limited")
            || normalizedRecentTail.contains("hit your usage limit")
            || normalizedRecentTail.contains("hit your rate limit")
            || normalizedRecentTail.contains("you've been rate")

        // Weak indicators — "rate limit" / "usage limit" can appear in informational
        // displays (e.g. Claude Code status line, or agent output discussing rate limits).
        // Require additional blocking context to avoid false positives.
        if !hasStrongIndicator {
            let hasWeakKeyword = normalizedRecentTail.contains("rate limit")
                || normalizedRecentTail.contains("usage limit")
            let hasBlockingContext = normalizedRecentTail.contains("exceeded")
                || normalizedRecentTail.contains("reached")
                || normalizedRecentTail.contains("throttl")
                || normalizedRecentTail.contains("blocked")
                || normalizedRecentTail.contains("paused")
                || normalizedRecentTail.contains("wait")
                    && normalizedRecentTail.contains("until")
            guard hasWeakKeyword && hasBlockingContext else { return nil }
        }

        let focusLines = tail.filter { line in
            let normalized = line.lowercased()
            return normalized.contains("rate")
                || normalized.contains("limit")
                || normalized.contains("quota")
                || normalized.contains("retry")
                || normalized.contains("try again")
                || normalized.contains("reset")
                || normalized.contains("available")
                || normalized.contains("until")
        }
        let focusText = (focusLines.isEmpty ? tail.suffix(20) : focusLines.suffix(12))
            .joined(separator: "\n")

        var resetAt = parseRelativeResetDate(from: focusText, now: now)
        if resetAt == nil {
            resetAt = parseAbsoluteResetDate(from: focusText, now: now)
        }

        let resetDescription = extractRateLimitResetDescription(from: focusText)
        return AgentRateLimitInfo(resetAt: resetAt, resetDescription: resetDescription)
    }

    private func parseRelativeResetDate(from text: String, now: Date) -> Date? {
        let normalized = text.lowercased()
        let triggerPattern = #"(?:try again|retry|resets?|reset|available)\s+(?:in|after)\s+([^\n\.;,]+)"#
        guard let triggerRegex = try? NSRegularExpression(pattern: triggerPattern, options: []) else { return nil }
        let searchRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)

        for match in triggerRegex.matches(in: normalized, options: [], range: searchRange) {
            guard match.numberOfRanges >= 2,
                  let durationRange = Range(match.range(at: 1), in: normalized) else { continue }
            let durationText = String(normalized[durationRange])
            if let seconds = parseDurationSeconds(from: durationText), seconds > 0 {
                return now.addingTimeInterval(seconds)
            }
        }

        // Fallback for common API wording (e.g. "retry after 30s").
        if let seconds = parseDurationSeconds(from: normalized), seconds > 0,
           normalized.contains("retry after") || normalized.contains("try again in") {
            return now.addingTimeInterval(seconds)
        }

        return nil
    }

    private func parseDurationSeconds(from text: String) -> TimeInterval? {
        let tokenPattern = #"(\d+)\s*(days?|d|hours?|hrs?|hr|h|minutes?|mins?|min|m|seconds?|secs?|sec|s)\b"#
        guard let regex = try? NSRegularExpression(pattern: tokenPattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        var seconds: TimeInterval = 0
        var matchedAny = false

        for match in regex.matches(in: text, options: [], range: range) {
            guard match.numberOfRanges >= 3,
                  let numberRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Double(text[numberRange]) else {
                continue
            }
            matchedAny = true

            switch text[unitRange] {
            case "d", "day", "days":
                seconds += value * 86_400
            case "h", "hr", "hrs", "hour", "hours":
                seconds += value * 3_600
            case "m", "min", "mins", "minute", "minutes":
                seconds += value * 60
            case "s", "sec", "secs", "second", "seconds":
                seconds += value
            default:
                continue
            }
        }

        return matchedAny ? seconds : nil
    }

    private func parseAbsoluteResetDate(from text: String, now: Date) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }

        let relevantLines = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                let normalized = line.lowercased()
                return normalized.contains("reset")
                    || normalized.contains("available")
                    || normalized.contains("until")
                    || normalized.contains("try again")
                    || normalized.contains("retry")
            }
        let detectorText = relevantLines.isEmpty ? text : relevantLines.joined(separator: "\n")
        let range = NSRange(detectorText.startIndex..<detectorText.endIndex, in: detectorText)

        return detector.matches(in: detectorText, options: [], range: range)
            .compactMap(\.date)
            .filter { $0 > now.addingTimeInterval(-60) }
            .sorted()
            .first
    }

    private func extractRateLimitResetDescription(from text: String) -> String? {
        let lines = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let candidate = lines.reversed().first { line in
            let normalized = line.lowercased()
            return normalized.contains("reset")
                || normalized.contains("available")
                || normalized.contains("until")
                || normalized.contains("retry")
                || normalized.contains("try again")
        } ?? lines.last

        guard let candidate else { return nil }
        let normalizedWhitespace = candidate.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return normalizedWhitespace.isEmpty ? nil : normalizedWhitespace
    }
}
