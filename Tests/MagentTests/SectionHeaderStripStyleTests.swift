import AppKit
import Testing

@Suite("Section header strip style")
struct SectionHeaderStripStyleTests {
    @Test("Strip stays compact and aligned with thread capsules")
    func stripGeometry() {
        let bounds = NSRect(x: 0, y: 0, width: 320, height: 28)

        let strip = SectionHeaderStripStyle.stripRect(in: bounds)
        let rail = SectionHeaderStripStyle.railRect(in: bounds)

        #expect(strip == NSRect(x: 12, y: 2, width: 296, height: 24))
        #expect(rail.width == 3)
        #expect(rail.minX > strip.minX)
        #expect(rail.minY > strip.minY)
        #expect(rail.maxY < strip.maxY)
        #expect(SectionHeaderStripStyle.contentLeadingInset - rail.maxX >= 8)
        #expect(strip.maxX - (bounds.maxX - SectionHeaderStripStyle.contentTrailingInset) >= 8)
    }
}
