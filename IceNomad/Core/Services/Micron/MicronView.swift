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
    /// The Browser's current viewport width — passed straight through to
    /// each MicronTextView, which only actually uses it for ordinary
    /// prose lines (art lines ignore it and size to their natural width).
    let availableWidth: CGFloat
    /// Live values for any `<...>` form fields on this page — nil for
    /// contexts that never render a form (falls back to a fresh, throwaway
    /// state so field lines still render, just without a live binding
    /// anywhere else cares about).
    @ObservedObject var formState: MicronFormState
    var onLinkTap: ((MicronLink) -> Void)?
    /// Threaded straight through to whichever MicronFormRowView renders
    /// this page's search field, if it has one — see that view's own
    /// doc comment.
    var searchSuggestions: [BrowserState.Suggestion] = []
    var onSearchQueryChange: ((String) -> Void)?
    var onSelectSearchSuggestion: ((BrowserState.Suggestion) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    /// Convenience initializer — parses raw .mu source directly.
    init(
        source: String,
        availableWidth: CGFloat,
        formState: MicronFormState = MicronFormState(),
        searchSuggestions: [BrowserState.Suggestion] = [],
        onSearchQueryChange: ((String) -> Void)? = nil,
        onSelectSearchSuggestion: ((BrowserState.Suggestion) -> Void)? = nil,
        onLinkTap: ((MicronLink) -> Void)? = nil
    ) {
        self.document = MicronParser.parse(source)
        self.availableWidth = availableWidth
        self.formState = formState
        self.searchSuggestions = searchSuggestions
        self.onSearchQueryChange = onSearchQueryChange
        self.onSelectSearchSuggestion = onSelectSearchSuggestion
        self.onLinkTap = onLinkTap
    }

    init(
        document: MicronDocument,
        availableWidth: CGFloat,
        formState: MicronFormState = MicronFormState(),
        searchSuggestions: [BrowserState.Suggestion] = [],
        onSearchQueryChange: ((String) -> Void)? = nil,
        onSelectSearchSuggestion: ((BrowserState.Suggestion) -> Void)? = nil,
        onLinkTap: ((MicronLink) -> Void)? = nil
    ) {
        self.document = document
        self.availableWidth = availableWidth
        self.formState = formState
        self.searchSuggestions = searchSuggestions
        self.onSearchQueryChange = onSearchQueryChange
        self.onSelectSearchSuggestion = onSelectSearchSuggestion
        self.onLinkTap = onLinkTap
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in

                groupView(for: group)

                if index < groups.count - 1 {
                    // A plain Spacer() here is fully transparent — fine
                    // normally, but on a page with a uniform background it
                    // left a strip of the app's own background showing
                    // through between every paragraph. Fill it with
                    // whatever color the group just above actually used.
                    Rectangle()
                        .fill(uniformBackground(of: group) ?? Color.clear)
                        .frame(height: spacing(after: group))
                }
            }
        }
        // Belt-and-suspenders on top of the per-row/per-gap fills above:
        // SwiftUI can leave a sub-pixel seam between two independently-
        // sized UIViewRepresentables (each row is its own UITextView) even
        // when both report backgrounds that agree — invisible on the old
        // uniformly-dark page, but a glaring thin line of the app's own
        // background once a page actually commits to one color throughout.
        // Painting the same color behind the whole stack means any such
        // seam shows the *right* color no matter where it comes from,
        // rather than chasing exact pixel alignment.
        .background(documentUniformBackground ?? Color.clear)
    }


    /// Same "does every span agree" check as a single row/group, but
    /// across the entire parsed document — only non-nil for a page that
    /// commits to one background color throughout (the common case this
    /// exists for), not one that legitimately changes color partway
    /// through (that page's own per-row fills already handle themselves).
    private var documentUniformBackground: Color? {

        let backgrounds = document.lines.flatMap(\.spans).compactMap(\.background)

        guard let first = backgrounds.first else {
            return nil
        }

        return backgrounds.allSatisfy { $0 == first } ? first : nil
    }


    /// Consecutive ASCII-art source lines (see MicronTextView.isFixedWidthArt)
    /// are merged into a single run before rendering. Earlier this glued
    /// separate per-line UITextViews together with a computed 0pt SwiftUI
    /// spacer between them — visually close, but each view's height came
    /// from an independent `sizeThatFits` call, and any sub-pixel rounding
    /// difference between adjacent boxes showed up as a hairline seam/tear
    /// between banner rows. Joining the source lines with real "\n"
    /// characters into one NSAttributedString and letting a single
    /// UITextView lay all of it out removes the seam entirely, since UIKit
    /// computes line-to-line spacing itself instead of SwiftUI approximating
    /// it from the outside — the same fix in spirit as the original move
    /// off SwiftUI's Text(AttributedString) (see MicronTextView's header).
    private var groups: [[MicronLine]] {

        var result: [[MicronLine]] = []
        var artRun: [MicronLine] = []

        func flushArtRun() {
            guard !artRun.isEmpty else { return }
            result.append(artRun)
            artRun = []
        }

        for line in document.lines {

            if line.kind == .text, !line.spans.isEmpty, MicronTextView.isFixedWidthArt(line.spans) {
                artRun.append(line)
            } else {
                flushArtRun()
                result.append([line])
            }
        }

        flushArtRun()

        return result
    }


    @ViewBuilder
    private func groupView(for group: [MicronLine]) -> some View {

        Group {

            if group.count == 1 {

                lineView(for: group[0])

            } else {

                MicronTextView(
                    spans: joinedSpans(group),
                    alignment: group[0].alignment,
                    fontSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                    isDarkMode: colorScheme == .dark,
                    availableWidth: availableWidth,
                    onLinkTap: onLinkTap
                )
            }
        }
        .padding(.leading, group[0].indent)
    }


    /// Same "does every span agree" check MicronTextView uses for a single
    /// row, extended to a whole group of lines — lets the spacing gap
    /// right after this group carry the same background forward instead
    /// of leaving a transparent seam between paragraphs on a colored page.
    private func uniformBackground(of group: [MicronLine]) -> Color? {

        let backgrounds = group.flatMap(\.spans).compactMap(\.background)

        guard let first = backgrounds.first else {
            return nil
        }

        return backgrounds.allSatisfy { $0 == first } ? first : nil
    }


    private func joinedSpans(_ group: [MicronLine]) -> [MicronSpan] {

        var combined: [MicronSpan] = []

        for (index, line) in group.enumerated() {

            combined.append(contentsOf: line.spans)

            if index < group.count - 1 {
                combined.append(MicronSpan(text: "\n"))
            }
        }

        return combined
    }


    @ViewBuilder
    private func lineView(for line: MicronLine) -> some View {

        switch line.kind {

        case .divider:

            // Real NomadNet dividers are a repeated fill glyph drawn with
            // whatever fg/bg color was active on the page when the
            // divider line was hit — not a fixed neutral hairline.
            // MicronParser captured the fill character + colors as a
            // single-character span; repeat it out here (at render time,
            // since only here do we know the actual viewport width) and
            // render it through the same unwrapped/art-style path as any
            // other banner row.
            if let fillSpan = line.spans.first, !fillSpan.text.isEmpty {

                let fontSize = UIFont.preferredFont(forTextStyle: .body).pointSize
                let approxCharWidth = fontSize * 0.6
                let repeatCount = max(1, Int(availableWidth / approxCharWidth))

                MicronTextView(
                    spans: [
                        MicronSpan(
                            text: String(repeating: fillSpan.text, count: repeatCount),
                            foreground: fillSpan.foreground,
                            background: fillSpan.background
                        )
                    ],
                    alignment: .leading,
                    fontSize: fontSize,
                    isDarkMode: colorScheme == .dark,
                    availableWidth: availableWidth,
                    forceUnwrapped: true,
                    onLinkTap: nil
                )

            } else {
                Divider() // defensive fallback, shouldn't normally hit
            }

        case .heading(let level):

            MicronTextView(
                spans: line.spans,
                alignment: line.alignment,
                fontSize: headingFontSize(level),
                isDarkMode: colorScheme == .dark,
                availableWidth: availableWidth,
                forceBold: true,
                onLinkTap: onLinkTap
            )

        case .text:

            if line.spans.isEmpty {
                EmptyView()
            } else if line.spans.contains(where: { $0.field != nil }) {

                // A field-bearing line renders as real SwiftUI controls
                // (MicronFormRowView), not through MicronTextView's UIKit
                // attributed-string path — see that view's header comment
                // for why. Its spans already have empty `text`, so
                // MicronTextView.isFixedWidthArt's own emptiness guard
                // already keeps this line out of `groups`' art-run
                // merging without any change needed there.
                MicronFormRowView(
                    spans: line.spans,
                    alignment: line.alignment,
                    formState: formState,
                    onLinkTap: onLinkTap,
                    searchSuggestions: searchSuggestions,
                    onSearchQueryChange: onSearchQueryChange,
                    onSelectSearchSuggestion: onSelectSearchSuggestion
                )

            } else {

                MicronTextView(
                    spans: line.spans,
                    alignment: line.alignment,
                    fontSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                    isDarkMode: colorScheme == .dark,
                    availableWidth: availableWidth,
                    onLinkTap: onLinkTap
                )
            }
        }
    }


    /// Spacing between rendered groups (a group is one prose/heading/
    /// divider line, or one already-merged run of art lines) — normal
    /// paragraph spacing, except a small gap following a blank source
    /// line, matching the original per-line behavior.
    private func spacing(after group: [MicronLine]) -> CGFloat {

        if group.count == 1, group[0].kind == .text, group[0].spans.isEmpty {
            return 4
        }

        return 10
    }


    private func headingFontSize(_ level: Int) -> CGFloat {

        switch level {
        case 1: return 28
        case 2: return 22
        default: return 19
        }
    }
}
