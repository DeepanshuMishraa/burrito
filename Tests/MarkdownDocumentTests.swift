import Testing
@testable import Burrito

@Suite("Markdown document")
struct MarkdownDocumentTests {
    @Test("Parses generated note structure into semantic blocks")
    func parsesGeneratedNotes() {
        let document = MarkdownDocument.parse(
            """
            # Overview

            A **short** summary.

            ## Key points
            - First
            - Second

            1. Start here
            2. Continue

            > Remember this.

            ---

            ```
            let value = 1
            ```
            """
        )

        #expect(
            document.blocks == [
                .heading(level: 1, text: "Overview"),
                .paragraph("A **short** summary."),
                .heading(level: 2, text: "Key points"),
                .unorderedList(["First", "Second"]),
                .orderedList(["Start here", "Continue"]),
                .quote("Remember this."),
                .divider,
                .code("let value = 1"),
            ]
        )
    }

    @Test("Repairs collapsed headings and bullets from generated Markdown")
    func repairsCollapsedGeneratedMarkdown() {
        let document = MarkdownDocument.parse(
            "## Overview: A concise summary. ## Key Points: * First point. * Second point."
        )

        #expect(
            document.blocks == [
                .heading(level: 2, text: "Overview"),
                .paragraph("A concise summary."),
                .heading(level: 2, text: "Key Points"),
                .unorderedList(["First point.", "Second point."]),
            ]
        )
    }

    @Test("Parses human Markdown into the rendered note structure")
    func parsesHumanNotes() {
        let document = MarkdownDocument.parse(
            """
            ## Questions

            - Is **Friday** confirmed?
            - Who owns the rollout?

            > Follow up with Priya.
            """
        )

        #expect(
            document.blocks == [
                .heading(level: 2, text: "Questions"),
                .unorderedList([
                    "Is **Friday** confirmed?",
                    "Who owns the rollout?",
                ]),
                .quote("Follow up with Priya."),
            ]
        )
    }

    @Test("Keeps ordered-list numbering across blank lines")
    func keepsOrderedListNumberingAcrossBlankLines() {
        let document = MarkdownDocument.parse(
            """
            1. First point

            2. Second point

            3. Third point
            """
        )

        #expect(
            document.blocks == [
                .orderedList(["First point", "Second point", "Third point"]),
            ]
        )
    }
}
