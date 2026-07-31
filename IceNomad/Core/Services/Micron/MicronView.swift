//
//  MicronView.swift
//  IceNomad
//
//  Renders a parsed Micron document (see MicronParser.swift). Body text
//  and headings both render via MicronTextView (UIKit) — see its doc
//  comment for why SwiftUI's native Text(AttributedString) can't be
//  used for Micron content.
//

import SwiftUI

struct MicronView: View {

    let document: MicronDocument
    var onLinkTap: ((MicronLink) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

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

        VStack(alignment: .leading, spacing: 10) {

            ForEach(document.lines) { line in

                switch line.kind {

                case .divider:
                    Divider()

                case .heading(let level):

                    MicronTextView(
                        spans: line.spans,
                        alignment: line.alignment,
                        fontSize: headingFontSize(level),
                        isDarkMode: colorScheme == .dark,
                        forceBold: true,
                        onLinkTap: onLinkTap
                    )

                case .text:

                    if line.spans.isEmpty {

                        Spacer().frame(height: 4)

                    } else {

                        MicronTextView(
                            spans: line.spans,
                            alignment: line.alignment,
                            fontSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                            isDarkMode: colorScheme == .dark,
                            onLinkTap: onLinkTap
                        )
                    }
                }
            }
        }
    }


    private func headingFontSize(_ level: Int) -> CGFloat {

        switch level {
        case 1: return 28
        case 2: return 22
        default: return 19
        }
    }
}
