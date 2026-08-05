//
//  MarkdownDocumentView.swift
//  IceNomad
//
//  A small, purpose-built Markdown renderer for USER_GUIDE.md (see
//  UserGuideView) — not a general CommonMark implementation, just the
//  handful of block types that guide actually uses: #/##/### headings,
//  paragraphs, bullet/numbered lists, and thematic breaks (---).
//
//  Splitting block structure out is done manually, line by line, since
//  the source is well-formed and simple; each block's own *inline*
//  content (bold, links, inline code) is handed to Foundation's real
//  Markdown parser (AttributedString(markdown:)) instead of hand-rolling
//  that too — SwiftUI's Text already renders bold/links/code spans from
//  an AttributedString correctly with zero extra work, so there's no
//  reason to reimplement it. Manual block splitting was still simpler
//  and more predictable than walking AttributedString's own block-level
//  PresentationIntent runs, given the fixed, known feature set here.
//

import SwiftUI

struct MarkdownDocumentView: View {

    let markdown: String

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            ForEach(Array(Self.parseBlocks(markdown).enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
    }


    @ViewBuilder
    private func blockView(for block: Block) -> some View {

        switch block {

        case .heading(let level, let text):

            Text(text)
                .font(headingFont(level))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, level == 1 ? 0 : 10)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):

            Text(text)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

        case .bulletItem(let text):

            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundStyle(Theme.textSecondary)
                Text(text)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numberedItem(let number, let text):

            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: 18, alignment: .trailing)
                Text(text)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .divider:

            Divider()
                .padding(.vertical, 2)
        }
    }


    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.bold)
        default: return .headline
        }
    }


    // MARK: - Parsing

    private enum Block {
        case heading(level: Int, text: AttributedString)
        case paragraph(text: AttributedString)
        case bulletItem(text: AttributedString)
        case numberedItem(number: Int, text: AttributedString)
        case divider
    }

    private static let numberedListRE = try! NSRegularExpression(pattern: #"^(\d+)\.\s+(.*)$"#)

    private static func parseBlocks(_ markdown: String) -> [Block] {

        var blocks: [Block] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(text: inline(paragraphLines.joined(separator: " "))))
            paragraphLines = []
        }

        for rawLine in markdown.components(separatedBy: "\n") {

            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if line == "---" {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            if line.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.heading(level: 3, text: inline(String(line.dropFirst(4)))))
                continue
            }

            if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(level: 2, text: inline(String(line.dropFirst(3)))))
                continue
            }

            if line.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.heading(level: 1, text: inline(String(line.dropFirst(2)))))
                continue
            }

            if line.hasPrefix("- ") {
                flushParagraph()
                blocks.append(.bulletItem(text: inline(String(line.dropFirst(2)))))
                continue
            }

            let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = numberedListRE.firstMatch(in: line, range: fullRange),
               let numberRange = Range(match.range(at: 1), in: line),
               let restRange = Range(match.range(at: 2), in: line) {
                flushParagraph()
                let number = Int(line[numberRange]) ?? 0
                blocks.append(.numberedItem(number: number, text: inline(String(line[restRange]))))
                continue
            }

            paragraphLines.append(line)
        }

        flushParagraph()
        return blocks
    }


    /// Bold/italic/links/inline-code within one block's text — real
    /// Markdown parsing (Foundation's own), scoped to inline syntax only
    /// so it doesn't try to interpret block structure we've already
    /// handled ourselves above.
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
