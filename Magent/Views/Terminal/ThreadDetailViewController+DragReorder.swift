import Cocoa
import MagentCore

extension ThreadDetailViewController {

    // MARK: - Drag-to-Reorder

    @objc func handleTabDrag(_ gesture: NSPanGestureRecognizer) {
        guard let draggedView = gesture.view as? TabItemView,
              let dragIndex = tabItems.firstIndex(where: { $0 === draggedView }) else { return }

        switch gesture.state {
        case .began:
            draggedView.isDragging = true
            draggedView.alphaValue = 0.85
            draggedView.layer?.zPosition = 100

        case .changed:
            let translation = gesture.translation(in: tabBarStack)
            draggedView.layer?.transform = CATransform3DMakeTranslation(translation.x, 0, 0)

            let draggedCenter = draggedView.frame.midX + translation.x

            // Constrain swaps within pinned/unpinned group
            let isPinned = dragIndex < pinnedCount
            let rangeStart = isPinned ? 0 : pinnedCount
            let rangeEnd = isPinned ? pinnedCount : tabItems.count

            // Check left neighbor
            if dragIndex > rangeStart {
                let leftTab = tabItems[dragIndex - 1]
                if draggedCenter < leftTab.frame.midX {
                    swapAdjacentTabs(dragIndex, dragIndex - 1, draggedView: draggedView, gesture: gesture)
                    return
                }
            }

            // Check right neighbor
            if dragIndex < rangeEnd - 1 {
                let rightTab = tabItems[dragIndex + 1]
                if draggedCenter > rightTab.frame.midX {
                    swapAdjacentTabs(dragIndex, dragIndex + 1, draggedView: draggedView, gesture: gesture)
                    return
                }
            }

        case .ended, .cancelled:
            draggedView.isDragging = false
            draggedView.alphaValue = 1.0
            draggedView.layer?.zPosition = 0
            draggedView.layer?.transform = CATransform3DIdentity
            persistTabOrder()
            rebindTabActions()

        default:
            break
        }
    }

    private func swapAdjacentTabs(_ indexA: Int, _ indexB: Int, draggedView: TabItemView, gesture: NSPanGestureRecognizer) {
        let otherView = (tabItems[indexA] === draggedView) ? tabItems[indexB] : tabItems[indexA]
        let otherOldFrame = otherView.frame

        // Swap in model arrays
        tabItems.swapAt(indexA, indexB)
        if indexA < terminalViews.count && indexB < terminalViews.count {
            terminalViews.swapAt(indexA, indexB)
        }
        if indexA < thread.tmuxSessionNames.count && indexB < thread.tmuxSessionNames.count {
            thread.tmuxSessionNames.swapAt(indexA, indexB)
        }

        // Update tracking indices
        if primaryTabIndex == indexA { primaryTabIndex = indexB }
        else if primaryTabIndex == indexB { primaryTabIndex = indexA }

        if currentTabIndex == indexA { currentTabIndex = indexB }
        else if currentTabIndex == indexB { currentTabIndex = indexA }

        // Swap positions in the stack view (removeArrangedSubview does NOT remove from superview)
        swapInStack(draggedView, otherView)

        // Force layout so frames update
        tabBarStack.layoutSubtreeIfNeeded()

        // Animate the other view from its old position to the new one
        let otherNewFrame = otherView.frame
        otherView.frame = otherOldFrame
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            otherView.animator().frame = otherNewFrame
        }

        // Reset translation — the dragged view is now at a new stack position
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

        // Remove from higher index first so lower index stays stable
        tabBarStack.removeArrangedSubview(viewAtMax)
        tabBarStack.removeArrangedSubview(viewAtMin)
        // Re-insert swapped
        tabBarStack.insertArrangedSubview(viewAtMax, at: minIdx)
        tabBarStack.insertArrangedSubview(viewAtMin, at: maxIdx)
    }

    func moveTab(from source: Int, to dest: Int) {
        guard source != dest else { return }

        let item = tabItems.remove(at: source)
        tabItems.insert(item, at: dest)

        let terminal = terminalViews.remove(at: source)
        terminalViews.insert(terminal, at: dest)

        if source < thread.tmuxSessionNames.count {
            var sessions = thread.tmuxSessionNames
            let session = sessions.remove(at: source)
            sessions.insert(session, at: min(dest, sessions.count))
            thread.tmuxSessionNames = sessions
        }

        // Update primaryTabIndex
        if primaryTabIndex >= 0 {
            if primaryTabIndex == source {
                primaryTabIndex = dest
            } else if source < primaryTabIndex && dest >= primaryTabIndex {
                primaryTabIndex -= 1
            } else if source > primaryTabIndex && dest <= primaryTabIndex {
                primaryTabIndex += 1
            }
        }

        // Update currentTabIndex
        if currentTabIndex == source {
            currentTabIndex = dest
        } else if source < currentTabIndex && dest >= currentTabIndex {
            currentTabIndex -= 1
        } else if source > currentTabIndex && dest <= currentTabIndex {
            currentTabIndex += 1
        }
    }

    func persistTabOrder() {
        threadManager.reorderTabs(for: thread.id, newOrder: thread.tmuxSessionNames)
        let pinnedSessions = (0..<pinnedCount).compactMap { i -> String? in
            guard i < thread.tmuxSessionNames.count else { return nil }
            return thread.tmuxSessionNames[i]
        }
        threadManager.updatePinnedTabs(for: thread.id, pinnedSessions: pinnedSessions)
    }
}

// MARK: - NSGestureRecognizerDelegate

extension ThreadDetailViewController: NSGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? NSPanGestureRecognizer,
              let tabView = pan.view as? TabItemView else { return true }

        let location = pan.location(in: tabView)
        let closeBounds = tabView.closeButton.convert(tabView.closeButton.bounds, to: tabView)
        if closeBounds.contains(location) { return false }

        return true
    }
}
