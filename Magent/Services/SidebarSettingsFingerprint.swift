import Foundation
import MagentCore

/// Settings that require the sidebar to refresh its rendered rows or layout.
struct SidebarSettingsFingerprint: Equatable {
    let projects: [Project]
    let threadSections: [ThreadSection]
    let useThreadSections: Bool
    let defaultSectionId: UUID?
    let autoReorderThreadsOnAgentCompletion: Bool
    let showThreadIcons: Bool
    let showWorktreeNames: Bool
    let showPRStatusBadges: Bool
    let showJiraStatusBadges: Bool
    let jiraTicketDetectionPrefixes: Set<String>
    let showBusyStateDuration: Bool
    let threadActivityIndicatorStyle: ThreadActivityIndicatorStyle
    let narrowThreads: Bool

    init(settings: AppSettings) {
        projects = settings.projects
        threadSections = settings.threadSections
        useThreadSections = settings.useThreadSections
        defaultSectionId = settings.defaultSectionId
        autoReorderThreadsOnAgentCompletion = settings.autoReorderThreadsOnAgentCompletion
        showThreadIcons = settings.showThreadIcons
        showWorktreeNames = settings.showWorktreeNames
        showPRStatusBadges = settings.showPRStatusBadges
        showJiraStatusBadges = settings.showJiraStatusBadges
        jiraTicketDetectionPrefixes = settings.jiraTicketDetectionPrefixFilterSet
        showBusyStateDuration = settings.showBusyStateDuration
        threadActivityIndicatorStyle = settings.threadActivityIndicatorStyle
        narrowThreads = !settings.wideThreads
    }
}
