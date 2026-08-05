//
//  Theme.swift
//  IceNomad
//
//  Arctic/penguin color system — ice blues and snow whites in light
//  mode, polar-night navy in dark mode, with green (TCP) and blue
//  (RNode) kept as the two reserved "functional" hues used everywhere
//  an interface's identity needs to be visible at a glance (Announce,
//  Browser node list). Every color here is a dynamic UIColor, so it
//  switches automatically with the system appearance — no
//  .preferredColorScheme override; the app always follows the user's
//  system setting, light or dark.
//

import SwiftUI
import UIKit


enum Theme {

    // MARK: - Dynamic color helper

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {

        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }


    // MARK: - Surfaces

    /// Main screen background — snow white in light mode, polar-night
    /// navy in dark mode (not pure black, so panels/materials still read).
    static let background = adaptive(
        light: UIColor(red: 0.965, green: 0.978, blue: 0.988, alpha: 1),
        dark:  UIColor(red: 0.043, green: 0.075, blue: 0.114, alpha: 1)
    )

    /// Cards, rows, elevated panels.
    static let surface = adaptive(
        light: UIColor(red: 0.925, green: 0.951, blue: 0.973, alpha: 1),
        dark:  UIColor(red: 0.086, green: 0.141, blue: 0.204, alpha: 1)
    )

    /// Hairline dividers and borders.
    static let divider = adaptive(
        light: UIColor(red: 0.827, green: 0.878, blue: 0.918, alpha: 1),
        dark:  UIColor(red: 0.176, green: 0.235, blue: 0.302, alpha: 1)
    )


    // MARK: - Text

    /// Primary text — deep glacier-navy on light, ice white on dark.
    /// Neither is pure black/white, since arctic light is always tinted.
    static let textPrimary = adaptive(
        light: UIColor(red: 0.071, green: 0.125, blue: 0.180, alpha: 1),
        dark:  UIColor(red: 0.941, green: 0.965, blue: 0.984, alpha: 1)
    )

    /// Secondary text — a cool slate-blue instead of system neutral
    /// gray, tuned to stay legible against both the light and dark
    /// surface colors above (the plain gray this replaced was too washed
    /// out against the dark navy background).
    static let textSecondary = adaptive(
        light: UIColor(red: 0.318, green: 0.400, blue: 0.478, alpha: 1),
        dark:  UIColor(red: 0.616, green: 0.702, blue: 0.780, alpha: 1)
    )


    // MARK: - Accent

    /// Primary accent — matches the app's existing AccentColor (an ice
    /// blue), exposed here so call sites don't need to know that.
    static let accent = Color.accentColor


    // MARK: - Functional interface colors
    //
    // Reserved hues: green always means "heard via TCP", blue always
    // means "heard via RNode" — used consistently in Announce and the
    // Browser's node list so the source of a peer is visible at a glance.

    static let tcpGreen = adaptive(
        light: UIColor(red: 0.114, green: 0.616, blue: 0.404, alpha: 1),
        dark:  UIColor(red: 0.290, green: 0.827, blue: 0.612, alpha: 1)
    )

    static let rnodeBlue = adaptive(
        light: UIColor(red: 0.098, green: 0.463, blue: 0.780, alpha: 1),
        dark:  UIColor(red: 0.353, green: 0.702, blue: 0.949, alpha: 1)
    )


    // MARK: - Status

    static let success = tcpGreen

    static let warning = adaptive(
        light: UIColor(red: 0.788, green: 0.541, blue: 0.078, alpha: 1),
        dark:  UIColor(red: 0.937, green: 0.749, blue: 0.310, alpha: 1)
    )

    static let danger = adaptive(
        light: UIColor(red: 0.784, green: 0.220, blue: 0.235, alpha: 1),
        dark:  UIColor(red: 0.949, green: 0.408, blue: 0.412, alpha: 1)
    )


    // MARK: - Chat bubbles
    //
    // Dedicated colors rather than reusing `accent`/`surface` directly —
    // the general-purpose accent is a bright ice-blue tuned for buttons/
    // controls, which in light mode is light enough that white bubble
    // text sits on it with weak contrast. These are deliberately deeper/
    // more saturated so white text stays legible in both appearances,
    // while still reading as "the app's blue," not a generic iMessage
    // blue — and the incoming bubble is a clearly visible cool slate
    // instead of the very subtle card-elevation `surface` tone.

    static let outgoingBubble = adaptive(
        light: UIColor(red: 0.106, green: 0.478, blue: 0.831, alpha: 1),
        dark:  UIColor(red: 0.145, green: 0.412, blue: 0.788, alpha: 1)
    )

    static let incomingBubble = adaptive(
        light: UIColor(red: 0.878, green: 0.906, blue: 0.933, alpha: 1),
        dark:  UIColor(red: 0.161, green: 0.220, blue: 0.290, alpha: 1)
    )


    // MARK: - Browser page source
    //
    // Which of BrowserState's three tiers actually rendered the page
    // currently on screen (see BrowserView's page-source badge) — blue
    // for Tux's real HTTP render, a paler blue-white for Tux's
    // Reticulum-cached .mu, green (matching this file's existing "green
    // always means TCP" convention above) for genuine live browsing.

    static let pageSourceTuxHTTP = rnodeBlue

    static let pageSourceTuxCache = adaptive(
        light: UIColor(red: 0.796, green: 0.878, blue: 0.949, alpha: 1),
        dark:  UIColor(red: 0.804, green: 0.878, blue: 0.937, alpha: 1)
    )

    static let pageSourceLive = tcpGreen
}


// MARK: - Micron content contrast safeguard

extension Theme {

    /// The font Micron pages render in. Deliberately Menlo, not the
    /// SwiftUI `design: .monospaced` system font (SF Mono) — real .mu
    /// pages lean heavily on legacy box-drawing/block-element characters
    /// (═ ║ ╔ ╗ ╚ ╝ █, U+2500–259F) for BBS-style ASCII art logos, and SF
    /// Mono's coverage of that range falls back to a substitute font
    /// with unrelated decorative glyphs instead of clean lines/blocks.
    /// Menlo (Apple's actual Terminal.app font, always present on iOS)
    /// has full glyph coverage for these ranges — confirmed directly via
    /// CoreText glyph lookup, not just by inspection.
    private static func micronPostscriptName(bold: Bool, italic: Bool) -> String {

        switch (bold, italic) {
        case (true, true): return "Menlo-BoldItalic"
        case (true, false): return "Menlo-Bold"
        case (false, true): return "Menlo-Italic"
        case (false, false): return "Menlo-Regular"
        }
    }

    static func micronFont(size: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize, bold: Bool = false, italic: Bool = false) -> Font {

        let postscriptName = micronPostscriptName(bold: bold, italic: italic)

        if UIFont(name: postscriptName, size: size) != nil {
            return Font.custom(postscriptName, size: size)
        }

        // Defensive fallback — Menlo ships on every iOS version IceNomad
        // targets, so this should never actually trigger.
        var font = Font.system(size: size, design: .monospaced)
        if bold { font = font.bold() }
        if italic { font = font.italic() }
        return font
    }

    /// UIFont counterpart of `micronFont`, for the UIKit (`UITextView`)
    /// rendering path Micron content actually uses — see MicronTextView's
    /// doc comment for why SwiftUI's own `Text(AttributedString)` can't
    /// be used here: it visibly corrupts glyph layout for these
    /// characters (confirmed via a side-by-side `ImageRenderer` capture
    /// against plain UIKit/AppKit attributed-string drawing, which
    /// renders the exact same content correctly), independent of which
    /// font is requested.
    static func micronUIFont(size: CGFloat = UIFont.preferredFont(forTextStyle: .body).pointSize, bold: Bool = false, italic: Bool = false) -> UIFont {

        let postscriptName = micronPostscriptName(bold: bold, italic: italic)
        return UIFont(name: postscriptName, size: size) ?? UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }


    /// Default per-level heading fg/bg band, matching real NomadNet's
    /// STYLES_DARK/STYLES_LIGHT tables exactly (same 3-digit hex codes,
    /// just re-expressed as adaptive Colors instead of a fixed palette
    /// entry) — a page's own inline color codes within a heading line
    /// still override these, same as the real client (this is only the
    /// *starting* fg/bg state MicronParser seeds before parsing a
    /// heading's content).
    private static let micronHeadingForegroundHex: [(dark: String, light: String)] = [
        ("222", "000"), ("111", "111"), ("000", "222"),
    ]

    private static let micronHeadingBackgroundHex: [(dark: String, light: String)] = [
        ("bbb", "777"), ("999", "aaa"), ("777", "ccc"),
    ]

    static func micronHeadingForeground(level: Int) -> Color {
        adaptiveMicronHex(micronHeadingForegroundHex[min(max(level, 1), 3) - 1])
    }

    static func micronHeadingBackground(level: Int) -> Color {
        adaptiveMicronHex(micronHeadingBackgroundHex[min(max(level, 1), 3) - 1])
    }

    private static func adaptiveMicronHex(_ hex: (dark: String, light: String)) -> Color {
        adaptive(light: UIColor(Color(micronHex3: hex.light)), dark: UIColor(Color(micronHex3: hex.dark)))
    }


    /// NomadNet pages specify their own text colors (`` `Fxxx `` hex
    /// codes), authored with no idea what background they'll render on.
    /// A page author's light gray, perfectly legible on the white
    /// terminal background they tested against, can disappear entirely
    /// against IceNomad's dark-mode background. This nudges a
    /// page-specified color's lightness away from the background's
    /// lightness whenever they'd otherwise end up too close to read.
    static func legiblePageColor(_ color: Color, isDarkMode: Bool) -> Color {

        let uiColor = UIColor(color)

        var white: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getWhite(&white, alpha: &alpha) else {

            // Not representable as grayscale (has real hue/saturation) —
            // leave it as authored; the contrast problem is specific to
            // near-gray colors that collide with the background.
            return color
        }

        let minimumContrast: CGFloat = 0.35

        if isDarkMode {

            // Dark background: anything too dark needs lifting toward white.
            if white < minimumContrast {
                let lifted = minimumContrast + (white * (1 - minimumContrast))
                return Color(white: Double(lifted))
            }

        } else {

            // Light background: anything too light needs darkening toward black.
            if white > (1 - minimumContrast) {
                let darkened = (1 - minimumContrast) * white
                return Color(white: Double(darkened))
            }
        }

        return color
    }
}
