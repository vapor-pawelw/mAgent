import MagentCore
import Testing

@Suite("InlineMarkdownBoldTokenizer")
struct InlineMarkdownBoldTokenizerTests {
    @Test("Parses a simple bold span")
    func parsesSimpleBoldSpan() {
        #expect(
            InlineMarkdownBoldTokenizer.tokenize("before **bold text** after")
                == [
                    .text("before "),
                    .bold("bold text"),
                    .text(" after"),
                ]
        )
    }

    @Test("Parses multiple bold spans")
    func parsesMultipleBoldSpans() {
        #expect(
            InlineMarkdownBoldTokenizer.tokenize("**one** and **two**")
                == [
                    .bold("one"),
                    .text(" and "),
                    .bold("two"),
                ]
        )
    }

    @Test("Keeps unmatched marker as plain text")
    func keepsUnmatchedMarkerAsPlainText() {
        #expect(
            InlineMarkdownBoldTokenizer.tokenize("before **bold text")
                == [.text("before **bold text")]
        )
    }

    @Test("Keeps empty markers as plain text")
    func keepsEmptyMarkersAsPlainText() {
        #expect(InlineMarkdownBoldTokenizer.tokenize("****") == [.text("****")])
    }
}
