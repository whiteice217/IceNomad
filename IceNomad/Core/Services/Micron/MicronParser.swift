//
//  MicronParser.swift
//  IceNomad
//
//  Parses Micron (.mu) markup, the lightweight formatting language
//  NomadNet pages are written in.
//
//  Confirmed syntax (from real NomadNet source — nomadnet/ui/textui/
//  MicronParser.py — fetched and diffed against this implementation
//  rather than guessed at from examples):
//    `!text`!         bold (toggle)
//    `*text`*         italic (toggle)
//    `_text`_         underline (toggle)
//    ``               reset all formatting
//    `Fxxxtext`f      foreground color (xxx = 3-digit hex shorthand), `f resets it
//    `FTxxxxxxtext`f  foreground color (xxxxxx = 6-digit true-color hex)
//    `Fgnn text`f     foreground color (nn = 2-digit grayscale, 00-99)
//    `Bxxx / `BT... / `Bgnn   same three forms for background
//    `ctext`a / `l / `r   center / left / right align, `a resets to left
//    >, >>, >>>       heading levels 1-3 (line-start); each level also
//                      indents subsequently-depth content and gets a
//                      default background/foreground band, both matching
//                      real NomadNet's behavior (see Theme.micronHeading*)
//    <                a bare "<" resets heading depth (and its indent)
//                      back to top level
//    `[Label`target]  link ("target" may be "path", "hash:/path", or "type@hash")
//    `<name`default>  input field (rendered as placeholder — not wired to submission)
//    -X...            divider — ANY line starting with "-"; if the line is
//                      EXACTLY 2 characters, the 2nd is the fill glyph,
//                      else default U+2500 "─". Rendered with whatever
//                      fg/bg color was active when the divider was hit.
//    `=               toggles literal mode: every line until the next `=
//                      is emitted completely as-is, no markup processing
//                      at all (real pages use this to protect ASCII-art
//                      banners from accidental markup collisions).
//    \X               backslash escapes the next character X, printing it
//                      literally instead of letting it trigger formatting
//                      (or, at the very start of a line, preventing that
//                      first character from being read as a heading/
//                      divider/comment marker).
//
//  Not yet handled: tables (`t, a later NomadNet addition) and partials
//  (`{, dynamically-loaded fragments) — both are safe to add later
//  without changing this file's shape.
//

import SwiftUI


// MARK: - Model

struct MicronDocument {
    var lines: [MicronLine]
}


enum MicronLineKind: Equatable {
    case text
    case heading(level: Int)
    case divider
}


struct MicronLine: Identifiable {
    let id = UUID()
    var kind: MicronLineKind
    var alignment: TextAlignment
    var spans: [MicronSpan]
    /// Left indent in points, driven by heading-depth section nesting
    /// (see the `>`/`<` handling below) — 0 for top-level content.
    var indent: CGFloat = 0
}


struct MicronSpan: Identifiable {
    let id = UUID()
    var text: String
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var foreground: Color?
    var background: Color?
    var link: MicronLink?
}


struct MicronLink: Equatable {
    var label: String
    var destinationHashHex: String?   // nil = relative to the current node
    var path: String
    var rawParams: String?            // captured but not acted on yet
    /// True for an `lxmf@<hash>` link — real NomadNet's shorthand for "open
    /// a conversation with this LXMF address" rather than browsing a page.
    /// Confirmed against nomadnet/ui/textui/Browser.py's expand_shorthands()
    /// + handle_link()/handle_lxmf_link(): the `@` separator picks a
    /// destination type (`lxmf` -> `lxmf.delivery`, `nnn` -> `nomadnetwork.node`,
    /// `rrc` -> `rrc.hub.session`), defaulting to a page link when absent.
    var isMessagingLink: Bool = false
    /// True for any link whose path starts with "/file/" — real NomadNet's
    /// Browser.py routes these to a file download (Browser.download_file)
    /// instead of navigating there as a page (confirmed against source:
    /// `if path.startswith("/file/"):`). Tapping one of these should hand
    /// off to DownloadManager rather than BrowserState.followLink.
    var isFileLink: Bool { path.hasPrefix("/file/") }
}


// MARK: - Parser

enum MicronParser {

    static func parse(_ source: String) -> MicronDocument {

        var lines: [MicronLine] = []

        // Formatting state persists across lines until explicitly toggled
        // off or reset — pages commonly style a whole paragraph this way.
        var isLiteral = false
        var depth = 0
        var bold = false
        var italic = false
        var underline = false
        var foreground: Color?
        var background: Color?
        var alignment: TextAlignment = .leading

        // 2 characters of indent per depth level, matching real
        // NomadNet's SECTION_INDENT, at a rough monospace char-width
        // estimate (exact pixel-perfect alignment isn't the point here —
        // depth is meant to visually nest content under its heading).
        func indentPoints() -> CGFloat {
            CGFloat(max(0, depth - 1)) * 2 * 8
        }

        func appendLine(_ spans: [MicronSpan], kind: MicronLineKind = .text) {
            lines.append(MicronLine(kind: kind, alignment: alignment, spans: spans, indent: indentPoints()))
        }

        // A regular (non-recursive) local function so the `<` case below
        // can re-enter it for the remainder of a line — Swift lets a
        // nested function freely mutate its enclosing function's locals,
        // which keeps all the formatting state above as plain `var`s
        // instead of needing a class or a pile of `inout` parameters.
        func processLine(_ raw: String) {

            // Literal-mode toggle — checked unconditionally, even while
            // already inside a literal block, since that's also how one
            // ends.
            if raw == "`=" {
                isLiteral.toggle()
                return
            }

            if isLiteral {

                // The one escape recognized inside a literal block: a
                // line that's just this exact sequence prints a literal
                // "`=" instead of being read as the block's end.
                let text = raw == "\\`=" ? "`=" : raw

                appendLine([
                    MicronSpan(text: text, bold: bold, italic: italic, underline: underline, foreground: foreground, background: background)
                ])

                return
            }

            guard let firstChar = raw.first else {
                appendLine([]) // blank source line
                return
            }

            var line = raw
            var lineStartsEscaped = false

            if firstChar == "\\" {

                // A leading backslash escapes the new first character's
                // special meaning (heading/divider/comment), not just a
                // formatting directive — strip it and fall through to
                // plain content parsing below.
                line = String(line.dropFirst())
                lineStartsEscaped = true

            } else if firstChar == "#" {

                return // comment line

            } else if firstChar == "<" {

                depth = 0

                let remainder = String(line.dropFirst())
                if !remainder.isEmpty {
                    processLine(remainder)
                }

                return

            } else if firstChar == ">" {

                var content = Substring(line)
                var headingLevel = 0

                while content.first == ">" {
                    headingLevel += 1
                    content = content.dropFirst()
                }

                depth = headingLevel

                guard !content.isEmpty else { return }

                let level = min(headingLevel, 3)

                // Headings get a default fg/bg band (matching real
                // NomadNet's per-level heading styles) that the heading's
                // own inline codes can still override — scoped to just
                // this line, same as real `latched_style`/`style_to_state`.
                let savedForeground = foreground
                let savedBackground = background
                foreground = Theme.micronHeadingForeground(level: level)
                background = Theme.micronHeadingBackground(level: level)

                let spans = parseInline(
                    String(content),
                    bold: &bold,
                    italic: &italic,
                    underline: &underline,
                    foreground: &foreground,
                    background: &background,
                    alignment: &alignment
                )

                foreground = savedForeground
                background = savedBackground

                lines.append(MicronLine(kind: .heading(level: level), alignment: alignment, spans: spans, indent: indentPoints()))
                return

            } else if firstChar == "-" {

                // Fill glyph only comes from the 2nd character when the
                // WHOLE line is exactly 2 characters — anything longer
                // (e.g. "-■■■■■■") still just becomes a default-filled
                // divider, the rest of the line is discarded, matching
                // real NomadNet exactly (confirmed against source).
                let fillCharacter: Character

                if raw.count == 2, let second = raw.dropFirst().first,
                   !(second.asciiValue.map { $0 < 32 } ?? false) {
                    fillCharacter = second
                } else {
                    fillCharacter = "\u{2500}"
                }

                // Colored using whatever fg/bg was active when this line
                // was hit — real dividers are drawn with the terminal's
                // current color state, not a fixed neutral line.
                lines.append(
                    MicronLine(
                        kind: .divider,
                        alignment: .leading,
                        spans: [MicronSpan(text: String(fillCharacter), foreground: foreground, background: background)],
                        indent: indentPoints()
                    )
                )
                return
            }

            let spans = parseInline(
                line,
                bold: &bold,
                italic: &italic,
                underline: &underline,
                foreground: &foreground,
                background: &background,
                alignment: &alignment,
                startEscaped: lineStartsEscaped
            )

            appendLine(spans)
        }

        // Split on any newline convention (\n, \r\n, \r) — real NomadNet
        // pages come from all kinds of authoring tools/platforms, and a
        // stray \r left at the end of a line (from splitting \r\n on
        // just \n) renders as a bare carriage-return character, which
        // makes text overlap/look jumbled instead of just wrapping.
        for rawLine in source.components(separatedBy: .newlines) {
            processLine(rawLine)
        }

        return MicronDocument(lines: lines)
    }


    // MARK: - Inline parsing

    private static func parseInline(
        _ text: String,
        bold: inout Bool,
        italic: inout Bool,
        underline: inout Bool,
        foreground: inout Color?,
        background: inout Color?,
        alignment: inout TextAlignment,
        startEscaped: Bool = false
    ) -> [MicronSpan] {

        var spans: [MicronSpan] = []
        var buffer = ""
        var escaping = startEscaped

        func flush() {
            guard !buffer.isEmpty else { return }
            spans.append(
                MicronSpan(
                    text: buffer,
                    bold: bold,
                    italic: italic,
                    underline: underline,
                    foreground: foreground,
                    background: background
                )
            )
            buffer = ""
        }

        let chars = Array(text)
        var i = 0

        while i < chars.count {

            let char = chars[i]

            // A backslash makes the very next character literal — it
            // can't trigger formatting (or, if it's itself a backslash,
            // collapses to one literal backslash).
            if escaping {
                buffer.append(char)
                escaping = false
                i += 1
                continue
            }

            if char == "\\" {
                escaping = true
                i += 1
                continue
            }

            guard char == "`" else {
                buffer.append(char)
                i += 1
                continue
            }

            guard i + 1 < chars.count else {
                // Trailing lone backtick — treat as literal text.
                buffer.append(char)
                i += 1
                continue
            }

            let next = chars[i + 1]

            switch next {

            case "`":
                flush()
                bold = false
                italic = false
                underline = false
                foreground = nil
                background = nil
                i += 2

            case "!":
                flush()
                bold.toggle()
                i += 2

            case "*":
                flush()
                italic.toggle()
                i += 2

            case "_":
                flush()
                underline.toggle()
                i += 2

            case "f":
                flush()
                foreground = nil
                i += 2

            case "b":
                flush()
                background = nil
                i += 2

            case "a":
                flush()
                alignment = .leading
                i += 2

            case "c":
                flush()
                alignment = .center
                i += 2

            case "l":
                flush()
                alignment = .leading
                i += 2

            case "r":
                flush()
                alignment = .trailing
                i += 2

            case "F", "B":
                flush()

                let isForeground = (next == "F")
                let codeStart = i + 2

                if codeStart < chars.count, chars[codeStart] == "T",
                   codeStart + 7 <= chars.count,
                   chars[(codeStart + 1)..<(codeStart + 7)].allSatisfy({ $0.isHexDigit }) {

                    // `FTxxxxxx` / `BTxxxxxx` — true-color, full 24-bit
                    // hex (not the digit-doubled 3-digit shorthand below).
                    let hex = String(chars[(codeStart + 1)..<(codeStart + 7)])
                    let color = Color(micronHex6: hex)

                    if isForeground { foreground = color } else { background = color }
                    i = codeStart + 7

                } else if codeStart < chars.count, chars[codeStart] == "g",
                          codeStart + 3 <= chars.count,
                          chars[(codeStart + 1)..<(codeStart + 3)].allSatisfy({ $0.isNumber }) {

                    // `Fg50` / `Bg50` — grayscale shorthand, 2 decimal
                    // digits, 00-99.
                    let digits = String(chars[(codeStart + 1)..<(codeStart + 3)])
                    let intensity = min(Double(digits) ?? 0, 99) / 99.0
                    let color = Color(white: intensity)

                    if isForeground { foreground = color } else { background = color }
                    i = codeStart + 3

                } else if codeStart + 3 <= chars.count,
                          chars[codeStart..<codeStart + 3].allSatisfy({ $0.isHexDigit }) {

                    let hex = String(chars[codeStart..<codeStart + 3])
                    let color = Color(micronHex3: hex)

                    if isForeground { foreground = color } else { background = color }
                    i = codeStart + 3

                } else {
                    // Malformed color code — skip the directive, don't crash.
                    i += 2
                }

            case "[":
                flush()

                var j = i + 2
                var label = ""

                while j < chars.count, chars[j] != "`" {
                    label.append(chars[j])
                    j += 1
                }

                guard j < chars.count else {
                    // No closing backtick — bail out, treat as literal text.
                    buffer.append(contentsOf: "`[" + label)
                    i = j
                    break
                }

                j += 1 // skip the backtick separating label from target

                var target = ""

                while j < chars.count, chars[j] != "]" {
                    target.append(chars[j])
                    j += 1
                }

                if j < chars.count {
                    j += 1 // skip closing ]
                }

                let link = parseLinkTarget(target, fallbackLabel: label)

                spans.append(
                    MicronSpan(
                        text: link.label,
                        bold: bold,
                        italic: italic,
                        underline: underline,
                        foreground: foreground,
                        background: background,
                        link: link
                    )
                )

                i = j

            case "<":
                // Input field — rendered as a placeholder for now, since
                // there's no live Link yet to submit values over.
                flush()

                var j = i + 2
                var fieldSpec = ""

                while j < chars.count, chars[j] != ">" {
                    fieldSpec.append(chars[j])
                    j += 1
                }

                if j < chars.count {
                    j += 1
                }

                spans.append(
                    MicronSpan(
                        text: "[field: \(fieldPlaceholderName(fieldSpec))]",
                        bold: bold,
                        italic: italic,
                        underline: underline,
                        foreground: .secondary,
                        background: nil
                    )
                )

                i = j

            default:
                // Unrecognized directive — keep the backtick as literal
                // text rather than eating real page content.
                buffer.append(char)
                i += 1
            }
        }

        flush()
        return spans
    }


    private static func parseLinkTarget(_ raw: String, fallbackLabel: String) -> MicronLink {

        // A target can carry extra `-separated request parameters after
        // the path — captured, but not acted on without a live Link.
        let parts = raw.components(separatedBy: "`")
        let destinationAndPath = parts.first ?? raw
        let rawParams = parts.count > 1 ? parts.dropFirst().joined(separator: "`") : nil

        // `<type>@<hash>` shorthand — currently only `lxmf`/`lxmf.delivery`
        // is acted on specially (open a conversation, not a page).
        if let atIndex = destinationAndPath.firstIndex(of: "@") {

            let typeToken = String(destinationAndPath[destinationAndPath.startIndex..<atIndex])
            let hashToken = String(destinationAndPath[destinationAndPath.index(after: atIndex)...])

            if (typeToken == "lxmf" || typeToken == "lxmf.delivery"),
               hashToken.count == 32, hashToken.allSatisfy({ $0.isHexDigit }) {

                return MicronLink(
                    label: fallbackLabel.isEmpty ? hashToken : fallbackLabel,
                    destinationHashHex: hashToken,
                    path: "",
                    rawParams: rawParams,
                    isMessagingLink: true
                )
            }
        }

        var destinationHashHex: String?
        var path = destinationAndPath

        if let colonIndex = destinationAndPath.firstIndex(of: ":") {

            let possibleHash = String(destinationAndPath[destinationAndPath.startIndex..<colonIndex])

            if possibleHash.count == 32, possibleHash.allSatisfy({ $0.isHexDigit }) {
                destinationHashHex = possibleHash
                path = String(destinationAndPath[destinationAndPath.index(after: colonIndex)...])
            }
        }

        let label = fallbackLabel.isEmpty ? path : fallbackLabel

        return MicronLink(
            label: label,
            destinationHashHex: destinationHashHex,
            path: path,
            rawParams: rawParams
        )
    }


    private static func fieldPlaceholderName(_ spec: String) -> String {

        // Formats seen: "fieldname", "24|fieldname", "!16|password"
        if let barIndex = spec.firstIndex(of: "|") {
            return String(spec[spec.index(after: barIndex)...])
        }

        return spec
    }
}


extension Color {

    /// Micron colors are 3-digit hex shorthand, e.g. "f00" -> bright red.
    init(micronHex3 hex: String) {

        let chars = Array(hex)

        func expand(_ c: Character) -> Double {
            guard let value = UInt8(String([c, c]), radix: 16) else { return 0 }
            return Double(value) / 255.0
        }

        self = Color(
            red: expand(chars[0]),
            green: expand(chars[1]),
            blue: expand(chars[2])
        )
    }

    /// Micron true-color form (`FT`/`BT`) — a plain 6-digit hex, e.g.
    /// "ff8800", not the digit-doubled 3-digit shorthand above.
    init(micronHex6 hex: String) {

        let chars = Array(hex)

        func pair(_ a: Character, _ b: Character) -> Double {
            guard let value = UInt8(String([a, b]), radix: 16) else { return 0 }
            return Double(value) / 255.0
        }

        self = Color(
            red: pair(chars[0], chars[1]),
            green: pair(chars[2], chars[3]),
            blue: pair(chars[4], chars[5])
        )
    }
}
