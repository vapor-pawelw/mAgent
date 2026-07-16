import AppKit
import Testing

@Suite("Section header strip style")
struct SectionHeaderStripStyleTests {
    @Test("Section content keeps its established alignment without header decoration")
    func contentAlignment() {
        #expect(SectionHeaderStripStyle.contentLeadingInset == 12)
        #expect(SectionHeaderStripStyle.contentTrailingInset == 20)
    }

    @Test("Section-count text uses the shared appearance-aware badge contrast")
    func badgeColorContrast() throws {
        let lightAppearance = try #require(NSAppearance(named: .aqua))
        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        let yellow = NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
        let lightModeColor = SectionHeaderStripStyle.badgeForegroundColor(
            sectionColor: yellow,
            appearance: lightAppearance
        ).usingColorSpace(.sRGB)
        let darkModeColor = SectionHeaderStripStyle.badgeForegroundColor(
            sectionColor: yellow,
            appearance: darkAppearance
        ).usingColorSpace(.sRGB)

        #expect(lightModeColor != nil)
        #expect((lightModeColor?.redComponent ?? 1) < yellow.redComponent)
        #expect((lightModeColor?.greenComponent ?? 1) < yellow.greenComponent)
        #expect((darkModeColor?.greenComponent ?? 0) > yellow.greenComponent)
        #expect((lightModeColor?.redComponent ?? 0) > (lightModeColor?.greenComponent ?? 1))
        #expect((darkModeColor?.redComponent ?? 0) > (darkModeColor?.greenComponent ?? 1))
    }
}

@Suite("Thread row capsule style")
struct ThreadRowCapsuleStyleTests {
    @Test("Section markers use forty-percent section color")
    func sectionMarkerStyle() {
        let sectionColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        let color = ThreadCapsuleSectionMarkerStyle.color(
            sectionColor: sectionColor,
            isSelected: false
        )
        let selectedColor = ThreadCapsuleSectionMarkerStyle.color(
            sectionColor: sectionColor,
            isSelected: true
        )

        #expect(abs(color.alphaComponent - 0.40) < 0.001)
        #expect(abs(selectedColor.alphaComponent - 1) < 0.001)
    }

    @Test("Section marker is a four-point diagonal band offset twelve points from the top-right")
    func sectionMarkerGeometry() {
        let capsuleRect = NSRect(x: 12, y: 4, width: 296, height: 52)
        let flippedVertices = ThreadCapsuleSectionMarkerStyle.vertices(
            in: capsuleRect,
            isFlipped: true
        )
        let unflippedVertices = ThreadCapsuleSectionMarkerStyle.vertices(
            in: capsuleRect,
            isFlipped: false
        )

        #expect(ThreadCapsuleSectionMarkerStyle.markerWidth == 4)
        #expect(ThreadCapsuleSectionMarkerStyle.cornerOffset == 12)
        #expect(flippedVertices.count == 4)
        #expect(unflippedVertices.count == 4)
        #expect(abs(flippedVertices[0].x - 293.172) < 0.001)
        #expect(flippedVertices[0].y == capsuleRect.minY)
        #expect(abs(flippedVertices[1].x - 298.828) < 0.001)
        #expect(flippedVertices[1].y == capsuleRect.minY)
        #expect(flippedVertices[2].x == capsuleRect.maxX)
        #expect(abs(flippedVertices[2].y - 13.172) < 0.001)
        #expect(flippedVertices[3].x == capsuleRect.maxX)
        #expect(abs(flippedVertices[3].y - 18.828) < 0.001)
        #expect(unflippedVertices[0].y == capsuleRect.maxY)
        #expect(unflippedVertices[1].y == capsuleRect.maxY)
        #expect(unflippedVertices[2].x == capsuleRect.maxX)
        #expect(abs(unflippedVertices[2].y - 46.828) < 0.001)
        #expect(unflippedVertices[3].x == capsuleRect.maxX)
        #expect(abs(unflippedVertices[3].y - 41.172) < 0.001)
    }

    @Test("Selection keeps precedence over completion state")
    func statePrecedence() {
        let completion = ThreadRowCapsuleVisualState.resolve(
            isSelected: false,
            showsRateLimitHighlight: false,
            showsWaitingHighlight: false,
            showsCompletionHighlight: true,
            showsPopoutTint: false
        )
        let selectedCompletion = ThreadRowCapsuleVisualState.resolve(
            isSelected: true,
            showsRateLimitHighlight: false,
            showsWaitingHighlight: false,
            showsCompletionHighlight: true,
            showsPopoutTint: false
        )

        #expect(completion == .completed)
        #expect(selectedCompletion == .selected)
    }
}
