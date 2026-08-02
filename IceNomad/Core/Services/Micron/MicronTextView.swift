//
//  MicronTextView.swift
//  IceNomad
//
//  Renders one Micron line's spans via UIKit (UITextView + a real
//  NSAttributedString), not SwiftUI's native Text(AttributedString).
//
//  Why: real .mu pages lean heavily on legacy box-drawing/block-element
//  characters (═ ║ ╔ ╗ ╚ ╝ █, U+2500–259F) for BBS-style ASCII art
//  banners. SwiftUI's Text(AttributedString) visibly corrupts glyph
//  layout for these characters when a background color is set — glyphs
//  render overlapping/smeared into an unrecognizable "maze" pattern —
//  independent of which monospaced font is requested (confirmed by
//  rendering the exact same AttributedString via SwiftUI's ImageRenderer
//  vs. plain UIKit/AppKit NSAttributedString drawing side-by-side: the
//  UIKit/AppKit render was pixel-correct, the SwiftUI one was not).
//  Bridging AttributedString -> NSAttributedString doesn't help either —
//  it preserves SwiftUI-only attribute keys (SwiftUI.Font,
//  SwiftUI.BackgroundColor, ...) that UITextView doesn't understand, so
//  the attributed string has to be built directly with UIFont/UIColor.
//

import SwiftUI
import UIKit

struct MicronTextView: UIViewRepresentable {

    let spans: [MicronSpan]
    let alignment: TextAlignment
    let fontSize: CGFloat
    let isDarkMode: Bool
    /// The Browser's current viewport width, used only for wrapping
    /// ordinary prose lines (see `isFixedWidthArt`) — art lines ignore
    /// this and always report their natural size.
    let availableWidth: CGFloat
    var forceBold: Bool = false
    /// Bypasses the isFixedWidthArt density heuristic entirely — used for
    /// divider fill rows (see MicronView), which are built from whatever
    /// single glyph a page specifies and may not fall in the box-drawing
    /// Unicode range the heuristic looks for (e.g. a plain "■" or "*"),
    /// but still need art's unwrapped/natural-size treatment rather than
    /// being word-wrapped as if they were prose.
    var forceUnwrapped: Bool = false
    var onLinkTap: ((MicronLink) -> Void)?

    /// Real .mu pages mix two very different kinds of content: ASCII-art
    /// banners built almost entirely from legacy box-drawing/block-element
    /// characters (═ ║ ╔ ╗ ╚ ╝ █, U+2500–259F), which only hold their
    /// shape unwrapped, and ordinary prose, which needs to wrap to the
    /// screen width like any normal text or every paragraph becomes one
    /// giant line requiring horizontal scrolling just to read a sentence.
    /// A line built mostly from these characters is unambiguously art —
    /// real prose essentially never contains them — so checking for their
    /// presence at all is a reliable, simple way to tell the two apart
    /// without needing the page to mark it explicitly.
    private var isFixedWidthArt: Bool {
        forceUnwrapped || Self.isFixedWidthArt(spans)
    }

    /// Shared with MicronView, which needs the same classification per
    /// line to decide spacing between rows (art rows sit flush against
    /// each other to hold their banner shape; prose keeps normal
    /// paragraph spacing) without duplicating the heuristic.
    static func isFixedWidthArt(_ spans: [MicronSpan]) -> Bool {

        let text = spans.map(\.text).joined()

        guard !text.isEmpty else {
            return false
        }

        let artCharacters = text.unicodeScalars.filter { (0x2500...0x259F).contains($0.value) }
        return Double(artCharacters.count) / Double(text.unicodeScalars.count) > 0.15
    }

    /// Whenever every span carrying an explicit background agrees on the
    /// same color, that's the author's intent for the whole row (a page
    /// that sets `` `Bxxx `` once and never resets it, expecting the
    /// entire line — not just the glyphs — to be that color). Spans with
    /// no background at all don't break the match; a line that mixes two
    /// genuinely different background colors falls back to nil, leaving
    /// the old glyph-tight per-span painting as-is rather than guessing
    /// which one should "win" the whole row.
    private var uniformRowBackground: Color? {

        let backgrounds = spans.compactMap(\.background)

        guard let first = backgrounds.first else {
            return nil
        }

        return backgrounds.allSatisfy { $0 == first } ? first : nil
    }

    func makeUIView(context: Context) -> UITextView {

        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator

        // Real terminal-grid ASCII art (box-drawing/block characters
        // stacked to form banners) needs rows packed at exactly the
        // font's cell height with no extra breathing room — UIKit's
        // default line-height calculation includes the font's "leading"
        // value on top of ascent+descent, which is normally desirable
        // typographically but pulls vertically-connecting glyphs (║, for
        // instance) apart by a hairline between rows, showing up as a
        // seam/tear running through the art. Disabling it packs lines
        // tight, matching how a real terminal renders the same content.
        textView.layoutManager.usesFontLeading = false

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {

        // Fills the view's actual frame, not just the glyph-tight regions
        // the per-span .backgroundColor attribute below can reach — this
        // is what makes a page-wide `` `Bxxx `` cover the full row instead
        // of leaving gaps past the text and around short lines.
        textView.backgroundColor = uniformRowBackground.map(UIColor.init) ?? .clear

        var links: [MicronLink] = []
        let attributed = NSMutableAttributedString()

        for span in spans {

            let font = Theme.micronUIFont(size: fontSize, bold: span.bold || forceBold, italic: span.italic)

            var attributes: [NSAttributedString.Key: Any] = [.font: font]

            if let foreground = span.foreground {
                attributes[.foregroundColor] = UIColor(Theme.legiblePageColor(foreground, isDarkMode: isDarkMode))
            } else {
                attributes[.foregroundColor] = UIColor(Theme.textPrimary)
            }

            if let background = span.background {
                attributes[.backgroundColor] = UIColor(background)
            }

            if span.underline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            if let link = span.link {

                let index = links.count
                links.append(link)

                attributes[.link] = URL(string: "micron://\(index)")!
                // A page that colors its own links (`` `Fxxx `` around a
                // `` `[Label`target] ``) should see that color, same as it
                // would for plain text — Theme.accent is only a fallback
                // for links that never specified one, not a hard override.
                if span.foreground == nil {
                    attributes[.foregroundColor] = UIColor(Theme.accent)
                }
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            attributed.append(NSAttributedString(string: span.text, attributes: attributes))
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = nsTextAlignment(alignment)
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributed.length))

        // UITextView.linkTextAttributes isn't nil by default even if this
        // is never touched — Apple's own docs: it defaults to
        // {foregroundColor: tintColor}, applied on top of the attributed
        // string's own inline attributes for any `.link` range. That
        // default alone was enough to keep overriding a page's own link
        // color back to the tint (a blue, same as Theme.accent) — setting
        // it to an explicitly empty dictionary is what actually suppresses
        // it, not just refraining from assigning it ourselves. Each span
        // already carries the right color, explicit or fallback; nothing
        // else should touch it.
        textView.linkTextAttributes = [:]

        textView.attributedText = attributed
        textView.textContainer.lineBreakMode = isFixedWidthArt ? .byClipping : .byWordWrapping
        textView.textContainer.size = isFixedWidthArt
            ? CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            : CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        context.coordinator.links = links
        context.coordinator.onLinkTap = onLinkTap
    }

    /// Art lines report their natural, unwrapped size — real Micron pages
    /// are authored against a fixed-width terminal grid, and ASCII-art
    /// banners only hold their shape unwrapped; the surrounding ScrollView
    /// (see BrowserView) lets you pan across a wide one, same as panning
    /// around an image. Ordinary prose lines wrap to `availableWidth`
    /// instead, same as any normal text — otherwise every paragraph
    /// becomes one giant unreadable line.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {

        if isFixedWidthArt {

            let natural = uiView.attributedText.size()

            // Art still reports (and stays laid out at) its own natural
            // width when that's wider than the viewport — a banner needs
            // to keep panning like an image, not get squashed. But when
            // it's narrower and carries a background color, the reported
            // width needs to reach at least the viewport edge too, or
            // there's nothing painted in the leftover strip past the
            // logo — the app's own background was showing through there.
            guard uniformRowBackground != nil else {
                return natural
            }

            return CGSize(width: max(natural.width, availableWidth), height: natural.height)
        }

        let fitted = uiView.sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))

        // A short line's natural width is narrower than the viewport —
        // fine normally, but it means a row background would stop right
        // after the text instead of reaching the page edge. Only widen
        // when there's actually a background to carry all the way across;
        // leaving plain text at its natural width avoids changing layout
        // anywhere else on the page.
        guard uniformRowBackground != nil else {
            return fitted
        }

        return CGSize(width: availableWidth, height: fitted.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func nsTextAlignment(_ alignment: TextAlignment) -> NSTextAlignment {
        switch alignment {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {

        var links: [MicronLink] = []
        var onLinkTap: ((MicronLink) -> Void)?

        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {

            guard URL.scheme == "micron",
                  let host = URL.host,
                  let index = Int(host),
                  index < links.count
            else {
                return true
            }

            onLinkTap?(links[index])
            return false
        }
    }
}
