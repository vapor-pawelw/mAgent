import Cocoa
import GhosttyBridge
import MagentCore

extension ThreadDetailViewController {

    // MARK: - Drag-to-Reorder

    @objc func handleTabDrag(_ gesture: NSPanGestureRecognizer) {
        guard let draggedView = gesture.view as? TabItemView,
              let dragIndex = tabItems.firstIndex(where: { $0 === draggedView }) else { return }
        guard !isPermanentTab(at: dragIndex) else { return }

        switch gesture.state {
        case .began:
            draggedView.isDragging = true
            draggedView.alphaValue = 0.85
            draggedView.layer?.zPosition = 100

        case .changed:
            let translation = gesture.translation(in: tabBarStack)
            draggedView.layer?.transform = CATransform3DMakeTranslation(translation.x, 0, 0)

            let draggedCenter = draggedView.frame.midX + translation.x

            // Only two drag groups: pinned and unpinned. All tab types mix freely.
            let groups = currentTabGroups()
            let group = groups.pinned.contains(dragIndex) ? groups.pinned : groups.unpinned
            guard let groupPosition = group.firstIndex(of: dragIndex) else { return }

            // Check left neighbor
            if groupPosition > group.startIndex {
                let leftIndex = group[group.index(before: groupPosition)]
                let leftTab = tabItems[leftIndex]
                if draggedCenter < leftTab.frame.midX {
                    swapAdjacentTabs(dragIndex, leftIndex, draggedView: draggedView, gesture: gesture)
                    return
                }
            }

            // Check right neighbor
            let nextPosition = group.index(after: groupPosition)
            if nextPosition < group.endIndex {
                let rightIndex = group[nextPosition]
                let rightTab = tabItems[rightIndex]
                if draggedCenter > rightTab.frame.midX {
                    swapAdjacentTabs(dragIndex, rightIndex, draggedView: draggedView, gesture: gesture)
                    return
                }
            }

        case .ended, .cancelled:
            let displacement = abs(gesture.translation(in: tabBarStack).x)
            draggedView.isDragging = false
            draggedView.alphaValue = 1.0
            draggedView.layer?.zPosition = 0
            draggedView.layer?.transform = CATransform3DIdentity
            // If the drag was negligible (click with slight jitter), treat as tap-to-select
            if displacement < 3 {
                selectTab(at: dragIndex)
            }
            persistTabOrder()
            rebindAllTabActions()

        default:
            break
        }
    }

    /// Swap two adjacent tabs in display order. Only `tabItems` and `tabSlots` are reordered;
    /// backing arrays (`terminalViews`, `webTabs`) stay in creation order.
    private func swapAdjacentTabs(_ indexA: Int, _ indexB: Int, draggedView: TabItemView, gesture: NSPanGestureRecognizer) {
        let otherView = (tabItems[indexA] === draggedView) ? tabItems[indexB] : tabItems[indexA]
        let otherOldFrame = otherView.frame

        // Swap display-order arrays only
        tabItems.swapAt(indexA, indexB)
        tabSlots.swapAt(indexA, indexB)

        if currentTabIndex == indexA { currentTabIndex = indexB }
        else if currentTabIndex == indexB { currentTabIndex = indexA }

        // Swap positions in the stack view
        swapInStack(draggedView, otherView)

        tabBarStack.layoutSubtreeIfNeeded()

        let otherNewFrame = otherView.frame
        otherView.frame = otherOldFrame
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            otherView.animator().frame = otherNewFrame
        }

        gesture.setTranslation(.zero, in: tabBarStack)
        draggedView.layer?.transform = CATransform3DIdentity
    }

    private func swapInStack(_ viewA: NSView, _ viewB: NSView) {
        guard let idxA = tabBarStack.arrangedSubviews.firstIndex(of: viewA),
              let idxB = tabBarStack.arrangedSubviews.firstIndex(of: viewB) else { return }

        let minIdx = min(idxA, idxB)
        let maxIdx = max(idxA, idxB)
        let viewAtMin = tabBarStack.arrangedSubviews[minIdx]
        let viewAtMax = tabBarStack.arrangedSubviews[maxIdx]

        tabBarStack.removeArrangedSubview(viewAtMax)
        tabBarStack.removeArrangedSubview(viewAtMin)
        tabBarStack.insertArrangedSubview(viewAtMax, at: minIdx)
        tabBarStack.insertArrangedSubview(viewAtMin, at: maxIdx)
    }

    /// Move a tab in display order. Only `tabItems` and `tabSlots` are reordered.
    func moveTab(from source: Int, to dest: Int) {
        guard source != dest else { return }
        guard source < tabSlots.count, dest < tabSlots.count else { return }
        guard !isPermanentTab(at: source), !isPermanentTab(at: dest) else { return }

        let item = tabItems.remove(at: source)
        tabItems.insert(item, at: dest)

        let slot = tabSlots.remove(at: source)
        tabSlots.insert(slot, at: dest)

        // Update currentTabIndex
        if currentTabIndex == source {
            currentTabIndex = dest
        } else if source < currentTabIndex && dest >= currentTabIndex {
            currentTabIndex -= 1
        } else if source > currentTabIndex && dest <= currentTabIndex {
            currentTabIndex += 1
        }
    }

    /// Persist the current display order to the thread model and disk.
    func persistTabOrder() {
        let pinnedIndices = Set(currentTabGroups().pinned)
        // Derive terminal session order and pinned sessions from tabSlots
        var terminalOrder: [String] = []
        var pinnedSessions: [String] = []

        for (i, slot) in tabSlots.enumerated() {
            if case .terminal(let name) = slot {
                terminalOrder.append(name)
                if pinnedIndices.contains(i) {
                    pinnedSessions.append(name)
                }
            }
        }

        // Reorder terminalViews to match the new session order.
        // terminalViews is kept parallel to thread.tmuxSessionNames; if we update
        // the name order without reordering the views, terminalView(forSession:)
        // will return the wrong surface after a drag/pin/unpin.
        let oldNames = thread.tmuxSessionNames
        var reorderedViews: [TerminalSurfaceView] = []
        for name in terminalOrder {
            if let oldIdx = oldNames.firstIndex(of: name), oldIdx < terminalViews.count {
                reorderedViews.append(terminalViews[oldIdx])
            }
        }
        terminalViews = reorderedViews

        thread.tmuxSessionNames = terminalOrder
        threadManager.reorderTabs(for: thread.id, newOrder: terminalOrder)
        threadManager.updatePinnedTabs(for: thread.id, pinnedSessions: pinnedSessions)

        // Persist web tab order and pin state
        var newPersistedWebTabs: [PersistedWebTab] = []
        for (i, slot) in tabSlots.enumerated() {
            if case .web(let identifier) = slot {
                if var persisted = thread.persistedWebTabs.first(where: { $0.identifier == identifier }) {
                    persisted.isPinned = pinnedIndices.contains(i)
                    newPersistedWebTabs.append(persisted)
                }
            }
        }
        thread.persistedWebTabs = newPersistedWebTabs
        threadManager.updatePersistedWebTabs(for: thread.id, webTabs: thread.persistedWebTabs)

        // Persist draft tab order and pin state.
        var newPersistedDraftTabs: [PersistedDraftTab] = []
        for (i, slot) in tabSlots.enumerated() {
            if case .draft(let identifier) = slot,
               var persisted = thread.persistedDraftTabs.first(where: { $0.identifier == identifier }) {
                persisted.isPinned = pinnedIndices.contains(i)
                newPersistedDraftTabs.append(persisted)
            }
        }
        thread.persistedDraftTabs = newPersistedDraftTabs
        let oldDraftTabs = draftTabs
        draftTabs = newPersistedDraftTabs.compactMap { persisted in
            if var entry = oldDraftTabs.first(where: { $0.identifier == persisted.identifier }) {
                entry.isPinned = persisted.isPinned
                return entry
            }
            return nil
        }
        threadManager.updatePersistedDraftTabs(for: thread.id, draftTabs: thread.persistedDraftTabs)

        // Persist chat tab order and pin state.
        var newPersistedChatTabs: [PersistedChatTab] = []
        for (i, slot) in tabSlots.enumerated() {
            if case .chat(let identifier) = slot,
               var persisted = thread.persistedChatTabs.first(where: { $0.identifier == identifier }) {
                persisted.isPinned = pinnedIndices.contains(i)
                newPersistedChatTabs.append(persisted)
            }
        }
        thread.persistedChatTabs = newPersistedChatTabs
        let oldChatTabs = chatTabs
        chatTabs = newPersistedChatTabs.compactMap { persisted in
            if var entry = oldChatTabs.first(where: { $0.identifier == persisted.identifier }) {
                entry.isPinned = persisted.isPinned
                return entry
            }
            return nil
        }
        threadManager.updatePersistedChatTabs(for: thread.id, chatTabs: thread.persistedChatTabs)

        persistTabDisplayOrder()
    }

    func persistTabDisplayOrder() {
        let displayOrder = tabSlots.dropFirst(Self.permanentTabCount).compactMap(\.displayOrderIdentifier)
        guard displayOrder != thread.tabDisplayOrder else { return }
        thread.tabDisplayOrder = displayOrder
        threadManager.updateTabDisplayOrder(for: thread.id, tabDisplayOrder: displayOrder)
    }

    func restorePersistedTabDisplayOrder() {
        guard !thread.tabDisplayOrder.isEmpty else { return }

        let fixedCount = min(Self.permanentTabCount, tabSlots.count)
        let pinnedEnd = min(max(pinnedCount, fixedCount), tabSlots.count)
        let fixedSlots = Array(tabSlots.prefix(fixedCount))
        let fixedItems = Array(tabItems.prefix(fixedCount))
        let pinnedPairs = reorderedTabPairs(in: fixedCount..<pinnedEnd)
        let unpinnedPairs = reorderedTabPairs(in: pinnedEnd..<tabSlots.count)
        let orderedPairs = pinnedPairs + unpinnedPairs

        tabSlots = fixedSlots + orderedPairs.map(\.slot)
        tabItems = fixedItems + orderedPairs.map(\.item)
    }

    private func reorderedTabPairs(in range: Range<Int>) -> [(slot: TabSlot, item: TabItemView)] {
        var remainingPairs = range.compactMap { index -> (slot: TabSlot, item: TabItemView)? in
            guard tabSlots.indices.contains(index), tabItems.indices.contains(index) else { return nil }
            return (tabSlots[index], tabItems[index])
        }
        let currentIdentifiers = remainingPairs.compactMap { $0.slot.displayOrderIdentifier }
        let orderedIdentifiers = TabDisplayOrderResolver.resolve(
            currentIdentifiers: currentIdentifiers,
            persistedOrder: thread.tabDisplayOrder
        )
        var orderedPairs: [(slot: TabSlot, item: TabItemView)] = []
        for identifier in orderedIdentifiers {
            guard let index = remainingPairs.firstIndex(where: { $0.slot.displayOrderIdentifier == identifier }) else {
                continue
            }
            orderedPairs.append(remainingPairs.remove(at: index))
        }
        orderedPairs.append(contentsOf: remainingPairs)
        return orderedPairs
    }
}

// MARK: - NSGestureRecognizerDelegate

extension ThreadDetailViewController: NSGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard let tabView = gestureRecognizer.view as? TabItemView else { return true }

        let location = gestureRecognizer.location(in: tabView)
        let closeBounds = tabView.closeButton.convert(tabView.closeButton.bounds, to: tabView)
        if closeBounds.contains(location) { return false }

        return true
    }
}
