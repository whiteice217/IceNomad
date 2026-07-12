//
//  MicronView.swift
//  IceNomad
//
//  Renders a parsed Micron document (see MicronParser.swift).
//

import SwiftUI

struct MicronView: View {

    let document: MicronDocument
    var onLinkTap: ((MicronLink) -> Void)?

    /// Convenience initializer — parses raw .mu source directly.
    init(source: String, onLinkTap: ((MicronLink) -> Void)? = nil) {
        self.document = MicronParser.parse(source)
        self.onLinkTap = onLinkTap
    }

    init(document: MicronDocument, onLinkTap: ((MicronLink) -> Void)? = nil) {
        self.document = document
        self.onLinkTap = onLinkTap
    }

    var body: some View {

        let rendered = buildContent()

        VStack(alignment: .leading, spacing: 10) {

            ForEach(rendered.items) { item in
                item.content
            }
        }
        .environment(\.openURL, OpenURLAction { url in

            guard url.scheme == "micron",
                  let host = url.host,
                  let index = Int(host),
                  index < rendered.links.count
            else {
                return .systemAction
            }

            onLinkTap?(rendered.links[index])
            return .handled
        })
    }


    // MARK: - Building

    private struct RenderedLine: Identifiable {
        let id: UUID
        let content: AnyView
    }

    private struct RenderResult {
        let items: [RenderedLine]
        let links: [MicronLink]
    }

    private func buildContent() -> RenderResult {

        var links: [MicronLink] = []
        var items: [RenderedLine] = []

        for line in document.lines {

            switch line.kind {

            case .divider:
                items.append(RenderedLine(id: line.id, content: AnyView(Divider())))

            case .heading(let level):

                let text = attributedText(for: line.spans, links: &links)

                items.append(
                    RenderedLine(
                        id: line.id,
                        content: AnyView(
                            Text(text)
                                .font(headingFont(level))
                                .fontWeight(.bold)
                                .multilineTextAlignment(line.alignment)
                                .frame(maxWidth: .infinity, alignment: frameAlignment(line.alignment))
                        )
                    )
                )

            case .text:

                if line.spans.isEmpty {

                    items.append(
                        RenderedLine(id: line.id, content: AnyView(Spacer().frame(height: 4)))
                    )

                } else {

                    let text = attributedText(for: line.spans, links: &links)

                    items.append(
                        RenderedLine(
                            id: line.id,
                            content: AnyView(
                                Text(text)
                                    .multilineTextAlignment(line.alignment)
                                    .frame(maxWidth: .infinity, alignment: frameAlignment(line.alignment))
                            )
                        )
                    )
                }
            }
        }

        return RenderResult(items: items, links: links)
    }


    /// Builds a single AttributedString for a line's spans. Using
    /// AttributedString (rather than a custom flow layout) gets us
    /// correct text wrapping AND tappable inline links for free, via
    /// the `.link` attribute and `.environment(\.openURL)` above.
    private func attributedText(for spans: [MicronSpan], links: inout [MicronLink]) -> AttributedString {

        var result = AttributedString()

        for span in spans {

            var attr = AttributedString(span.text)
            var font: Font = .body

            if span.bold {
                font = font.bold()
            }

            if span.italic {
                font = font.italic()
            }

            attr.font = font

            if span.underline {
                attr.underlineStyle = .single
            }

            if let foreground = span.foreground {
                attr.foregroundColor = foreground
            }

            if let background = span.background {
                attr.backgroundColor = background
            }

            if let link = span.link {

                let index = links.count
                links.append(link)

                attr.link = URL(string: "micron://\(index)")
                attr.foregroundColor = .blue
                attr.underlineStyle = .single
            }

            result += attr
        }

        return result
    }


    private func headingFont(_ level: Int) -> Font {

        switch level {
        case 1: return .title
        case 2: return .title2
        default: return .title3
        }
    }


    private func frameAlignment(_ alignment: TextAlignment) -> Alignment {

        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
