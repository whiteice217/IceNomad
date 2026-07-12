//
//  MicronParser.swift
//  IceNomad
//
//  Parses Micron (.mu) markup, the lightweight formatting language
//  NomadNet pages are written in.
//
//  Confirmed syntax (from NomadNet's own docs / micron-composer reference):
//    `!text`!         bold (toggle)
//    `*text`*         italic (toggle)
//    `_text`_         underline (toggle)
//    ``               reset all formatting
//    `Fxxxtext`f      foreground color (xxx = 3-digit hex), `f resets it
//    `Bxxxtext`b      background color, `b resets it
//    `ctext`a / `l / `r   center / left / right align, `a resets to left
//    >, >>, >>>       heading levels 1-3 (line-start)
//    `[Label`target]  link ("target" may be "path" or "hash:/path")
//    `<name`default>  input field (rendered as a placeholder — not wired
//                     up to submission yet, since there's no live Link)
//
//  Not yet handled: tables (added in a later NomadNet version) and the
//  full set of link request-parameter syntax — both are safe to add
//  later without changing this file's shape.
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
}


// MARK: - Parser

enum MicronParser {

    static func parse(_ source: String) -> MicronDocument {

        var lines: [MicronLine] = []

        // Formatting state persists across lines until explicitly toggled
        // off or reset — pages commonly style a whole paragraph this way.
        var bold = false
        var italic = false
        var underline = false
        var foreground: Color?
        var background: Color?
        var alignment: TextAlignment = .leading

        for rawLine in source.components(separatedBy: "\n") {

            // Comment lines are ignored entirely.
            if rawLine.hasPrefix("#") {
                continue
            }

            // Divider: a line that's only dashes.
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "-" }) {
                lines.append(MicronLine(kind: .divider, alignment: .leading, spans: []))
                continue
            }

            // Headings: leading >, >>, >>>
            var content = Substring(rawLine)
            var headingLevel = 0

            while content.first == ">" {
                headingLevel += 1
                content = content.dropFirst()
            }

            let spans = parseInline(
                String(content),
                bold: &bold,
                italic: &italic,
                underline: &underline,
                foreground: &foreground,
                background: &background,
                alignment: &alignment
            )

            let kind: MicronLineKind = headingLevel > 0
                ? .heading(level: min(headingLevel, 3))
                : .text

            lines.append(MicronLine(kind: kind, alignment: alignment, spans: spans))
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
        alignment: inout TextAlignment
    ) -> [MicronSpan] {

        var spans: [MicronSpan] = []
        var buffer = ""

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
                let hexStart = i + 2

                if hexStart + 3 <= chars.count,
                   chars[hexStart..<hexStart + 3].allSatisfy({ $0.isHexDigit }) {

                    let hex = String(chars[hexStart..<hexStart + 3])
                    let color = Color(micronHex3: hex)

                    if isForeground {
                        foreground = color
                    } else {
                        background = color
                    }

                    i = hexStart + 3

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


private extension Color {

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
}
