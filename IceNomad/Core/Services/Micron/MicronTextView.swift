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
    var forceBold: Bool = false
    var onLinkTap: ((MicronLink) -> Void)?

    func makeUIView(context: Context) -> UITextView {

        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byClipping
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {

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
                attributes[.foregroundColor] = UIColor(Theme.accent)
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            attributed.append(NSAttributedString(string: span.text, attributes: attributes))
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = nsTextAlignment(alignment)
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributed.length))

        // Links get the accent color/underline via .link's own default
        // UITextView styling too — explicit attributes above just make
        // sure it's consistent even before/without tint customization.
        textView.linkTextAttributes = [.foregroundColor: UIColor(Theme.accent)]

        textView.attributedText = attributed
        context.coordinator.links = links
        context.coordinator.onLinkTap = onLinkTap
    }

    /// Deliberately ignores the proposed width and reports the text's
    /// natural, unwrapped size. Real Micron pages are authored against a
    /// fixed-width terminal grid — ASCII-art banners in particular only
    /// hold their shape unwrapped. Reflowing them to fit a narrow phone
    /// screen breaks them outright, so instead the page renders at its
    /// natural width and the surrounding ScrollView (see BrowserView)
    /// lets you pan across it, same as panning around a wide image.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        uiView.attributedText.size()
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
