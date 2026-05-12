import MagentCore
import Testing

@Suite("ChatMarkdownTokenizer")
struct ChatMarkdownTokenizerTests {
    @Test("Parses bold segments wrapped in double asterisks")
    func parsesBoldSegments() {
        #expect(
            ChatMarkdownTokenizer.tokenize("before **bold text** after")
                == [
                    .text("before "),
                    .bold("bold text"),
                    .text(" after"),
                ]
        )
    }

    @Test("Leaves unmatched double-asterisk markers as plain text")
    func leavesUnmatchedBoldMarkersAsText() {
        #expect(
            ChatMarkdownTokenizer.tokenize("before **bold text")
                == [.text("before **bold text")]
        )
    }

    @Test("Keeps empty bold markers as plain text")
    func keepsEmptyBoldMarkersAsText() {
        #expect(ChatMarkdownTokenizer.tokenize("****") == [.text("****")])
    }

    @Test("Does not parse bold markers inside inline code")
    func ignoresBoldInsideInlineCode() {
        #expect(
            ChatMarkdownTokenizer.tokenize("`**not bold**` and **bold**")
                == [
                    .code("**not bold**"),
                    .text(" and "),
                    .bold("bold"),
                ]
        )
    }
}
