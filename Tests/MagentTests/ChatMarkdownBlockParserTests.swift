import Testing
import MagentCore

@Suite("Chat Markdown block parser")
struct ChatMarkdownBlockParserTests {
    @Test("Recognizes headings, lists, quotes, separators, and fenced code")
    func recognizesCommonAssistantMarkdown() {
        let blocks = ChatMarkdownBlockParser.parse("""
        ### Proposed plan

        - First step
        2. Second step
        > Important detail
        ---
        ```swift
        let answer = 42
        ```
        """)

        #expect(blocks == [
            .heading(level: 3, text: "Proposed plan"),
            .blankLine,
            .unorderedListItem("First step"),
            .orderedListItem(number: 2, text: "Second step"),
            .blockQuote("Important detail"),
            .separator,
            .codeBlock(language: "swift", code: "let answer = 42"),
        ])
    }

    @Test("Leaves non-Markdown markers as ordinary text")
    func preservesOrdinaryMarkers() {
        #expect(ChatMarkdownBlockParser.parse("#hashtag\n-compact") == [
            .paragraph("#hashtag"),
            .paragraph("-compact"),
        ])
    }

    @Test("Recognizes fenced code without a language tag")
    func recognizesUnlabeledFencedCode() {
        #expect(ChatMarkdownBlockParser.parse("""
        ```
        # not a heading
        - not a list
        ```
        """) == [
            .codeBlock(language: nil, code: "# not a heading\n- not a list"),
        ])
    }
}
