import Cocoa

extension InlineDiffViewController {

    // MARK: - Content

    func setDiffContent(_ rawDiff: String, fileCount: Int, worktreePath: String?, mergeBase: String?) {
        self.worktreePath = worktreePath
        self.mergeBase = mergeBase

        headerLabel.stringValue = "DIFF (\(fileCount) files)"

        // Clear old sections
        for sv in sectionsStackView.arrangedSubviews {
            sectionsStackView.removeArrangedSubview(sv)
            sv.removeFromSuperview()
        }
        sectionViews.removeAll()

        // Split diff into per-file chunks and create section views
        let chunks = splitDiffIntoFileChunks(rawDiff)
        for (path, chunkContent) in chunks {
            let section: DiffSectionView

            if isImageFile(path) {
                let state = detectImageDiffState(from: chunkContent)
                section = DiffSectionView(filePath: path, imageDiffMode: state)
                loadImages(for: section, path: path, chunk: chunkContent, state: state)
            } else {
                let (additions, deletions) = countStats(in: chunkContent)
                section = DiffSectionView(
                    filePath: path,
                    rawChunk: chunkContent,
                    additions: additions,
                    deletions: deletions
                )
            }

            section.onToggle = { [weak self, weak section] in
                guard let self, let section else { return }
                section.isExpanded.toggle()
                self.syncExpandCollapseState()
                self.scrollSectionIntoViewIfNeeded(section)
            }
            sectionViews.append(section)
            sectionsStackView.addArrangedSubview(section)
            section.leadingAnchor.constraint(equalTo: sectionsStackView.leadingAnchor).isActive = true
            section.trailingAnchor.constraint(equalTo: sectionsStackView.trailingAnchor).isActive = true
        }
    }

    // MARK: - Image Loading

    private func loadImages(for section: DiffSectionView, path: String, chunk: String, state: ImageDiffMode) {
        guard let worktreePath else { return }
        let mergeBase = self.mergeBase
        let beforePath = extractRenameFrom(chunk) ?? path

        Task {
            var beforeImage: NSImage?
            var afterImage: NSImage?

            // Load before image (from git ref)
            if state != .added, let ref = mergeBase {
                if let data = await GitService.shared.fileData(
                    atRef: ref,
                    relativePath: beforePath,
                    worktreePath: worktreePath
                ) {
                    beforeImage = NSImage(data: data)
                }
            }

            // Load after image (from working tree)
            if state != .deleted {
                let fileURL = URL(fileURLWithPath: worktreePath).appendingPathComponent(path)
                if let data = try? Data(contentsOf: fileURL) {
                    afterImage = NSImage(data: data)
                }
            }

            await MainActor.run {
                section.setImages(before: beforeImage, after: afterImage)
            }
        }
    }

    func expandFile(_ relativePath: String, collapseOthers: Bool) {
        for section in sectionViews {
            if section.filePath == relativePath {
                section.isExpanded = true
            } else if collapseOthers {
                section.isExpanded = false
            }
        }
        syncExpandCollapseState()
        // Scroll to the expanded section
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let section = self.sectionViews.first(where: { $0.filePath == relativePath }) {
                self.scrollSectionIntoViewIfNeeded(section)
            }
        }
    }

    func syncExpandCollapseState() {
        allExpanded = sectionViews.allSatisfy(\.isExpanded)
        updateExpandCollapseButton()
    }

    func expandAll() {
        // Find anchor section at top of viewport
        let visibleY = scrollView.contentView.bounds.origin.y
        var anchorSection: DiffSectionView?
        var anchorOffsetBefore: CGFloat = 0
        for section in sectionViews {
            let frame = section.convert(section.bounds, to: sectionsStackView)
            if frame.maxY > visibleY {
                anchorSection = section
                anchorOffsetBefore = frame.origin.y - visibleY
                break
            }
        }

        for section in sectionViews {
            section.isExpanded = true
        }
        allExpanded = true
        updateExpandCollapseButton()

        // Restore scroll after layout completes
        if let anchor = anchorSection {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.sectionsStackView.layoutSubtreeIfNeeded()
                let newFrame = anchor.convert(anchor.bounds, to: self.sectionsStackView)
                let newScrollY = newFrame.origin.y - anchorOffsetBefore
                self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(newScrollY, 0)))
                self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            }
        }
    }

    func collapseAll() {
        // Find anchor section at top of viewport
        let visibleY = scrollView.contentView.bounds.origin.y
        var anchorSection: DiffSectionView?
        var anchorOffsetBefore: CGFloat = 0
        for section in sectionViews {
            let frame = section.convert(section.bounds, to: sectionsStackView)
            if frame.maxY > visibleY {
                anchorSection = section
                anchorOffsetBefore = frame.origin.y - visibleY
                break
            }
        }

        for section in sectionViews {
            section.isExpanded = false
        }
        allExpanded = false
        updateExpandCollapseButton()

        // Restore scroll after layout completes
        if let anchor = anchorSection {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.sectionsStackView.layoutSubtreeIfNeeded()
                let newFrame = anchor.convert(anchor.bounds, to: self.sectionsStackView)
                let newScrollY = newFrame.origin.y - anchorOffsetBefore
                self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(newScrollY, 0)))
                self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            }
        }
    }

    func scrollToFile(_ relativePath: String) {
        guard let section = sectionViews.first(where: { $0.filePath == relativePath }) else { return }
        scrollSectionIntoViewIfNeeded(section)
    }

    private func scrollSectionIntoViewIfNeeded(_ section: DiffSectionView) {
        let sectionFrame = section.convert(section.bounds, to: sectionsStackView)
        scrollView.contentView.scrollToVisible(sectionFrame)
    }

    // MARK: - Diff Splitting

    private func splitDiffIntoFileChunks(_ rawDiff: String) -> [(path: String, content: String)] {
        var chunks: [(path: String, content: String)] = []
        let lines = rawDiff.components(separatedBy: "\n")

        var currentPath = ""
        var currentLines: [String] = []

        for line in lines {
            if line.hasPrefix("diff --git") {
                // Save previous chunk if any
                if !currentPath.isEmpty {
                    chunks.append((path: currentPath, content: currentLines.joined(separator: "\n")))
                }
                // Extract path from "diff --git a/path b/path"
                let parts = line.components(separatedBy: " b/")
                currentPath = parts.count >= 2 ? (parts.last ?? "") : ""
                currentLines = [line]
            } else {
                currentLines.append(line)
            }
        }

        // Save last chunk
        if !currentPath.isEmpty {
            chunks.append((path: currentPath, content: currentLines.joined(separator: "\n")))
        }

        return chunks
    }

    private func countStats(in chunk: String) -> (additions: Int, deletions: Int) {
        var adds = 0
        var dels = 0
        for line in chunk.components(separatedBy: "\n") {
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                adds += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                dels += 1
            }
        }
        return (adds, dels)
    }
}
