//
//  MicronFormRowView.swift
//  IceNomad
//
//  Renders one Micron line that contains form-field directives (`<...>` —
//  text inputs, checkboxes, radios) as real interactive SwiftUI controls
//  bound to a MicronFormState shared with the rest of the page.
//
//  Kept as its own SwiftUI-native row rather than embedding live controls
//  inside MicronTextView's UIKit attributed-string rendering — real .mu
//  forms put each field on its own line in practice (see Tux's claim.mu),
//  so flowing plain text around an inline control isn't worth the
//  complexity it'd add to that already-delicate UIKit bridge. A field
//  line is never merged into an art run or a multi-line group — its
//  spans have empty `text`, so MicronTextView.isFixedWidthArt's own
//  "guard !text.isEmpty" already keeps it a standalone line without any
//  change needed in MicronView's grouping.
//

import SwiftUI

struct MicronFormRowView: View {

    let spans: [MicronSpan]
    let alignment: TextAlignment
    /// The viewport width this line has to work with — used to cap a
    /// text field's width so it can't claim the whole row on a narrow
    /// phone screen, and to size the wrapping FlowLayout below (see its
    /// header comment for why a plain HStack isn't enough here).
    let availableWidth: CGFloat
    @ObservedObject var formState: MicronFormState
    /// So a link can sit on the same line as a field — e.g. Tux's search
    /// box with its "Search" submit link right after it, one row instead
    /// of stacked — rather than only ever appearing inside MicronTextView.
    var onLinkTap: ((MicronLink) -> Void)?
    /// Live, database-backed autocomplete for this row's search field
    /// (see isSearchQuery) — the same Tux-backed suggestions the native
    /// address bar shows, so typing in the on-page search box gets the
    /// identical dropdown instead of a plain, unassisted text field.
    var searchSuggestions: [BrowserState.Suggestion] = []
    var onSearchQueryChange: ((String) -> Void)?
    var onSelectSearchSuggestion: ((BrowserState.Suggestion) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {

        VStack(alignment: alignment == .trailing ? .trailing : .leading, spacing: 6) {

            // A plain HStack never wraps — a field plus its submit link
            // could run straight off the edge of a narrow phone screen
            // in portrait mode with no way back (confirmed live: Tux's
            // own search box did exactly this). FlowLayout instead drops
            // whatever doesn't fit to a second line, same as text
            // wrapping would.
            FlowLayout(spacing: 6) {

                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                    spanView(for: span)
                }
            }

            if hasSearchField, !searchSuggestions.isEmpty {
                AddressSuggestionsList(suggestions: searchSuggestions) { suggestion in
                    onSelectSearchSuggestion?(suggestion)
                }
            }
        }
    }


    private var hasSearchField: Bool {
        spans.contains { $0.field.map(isSearchQuery) ?? false }
    }


    /// A page author's declared field width (in characters) is a real
    /// author intent worth respecting on a wide enough screen, but with
    /// no cap at all a wide field (Tux's own search box: 24 characters,
    /// 216pt) could claim most or all of a narrow phone's row by itself
    /// — capped to a fraction of the actual viewport instead of trusting
    /// the raw character count.
    private func cappedFieldWidth(for field: MicronField) -> CGFloat {
        let requested = CGFloat(min(max(field.width, 4), 40)) * 9
        return min(requested, availableWidth * 0.7)
    }


    @ViewBuilder
    private func spanView(for span: MicronSpan) -> some View {

        if let field = span.field {

            switch field.kind {

            case .text:
                TextField("", text: textBinding(for: field))
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.micronFont(size: UIFont.preferredFont(forTextStyle: .body).pointSize))
                    .frame(width: cappedFieldWidth(for: field))
                    .textInputAutocapitalization(isSearchQuery(field) ? .sentences : .never)
                    .autocorrectionDisabled(!isSearchQuery(field))
                    .privacySensitive(field.masked)
                    .textContentType(field.masked ? .password : nil)
                    .onChange(of: formState.textValues[field.name]) { _, newValue in
                        if isSearchQuery(field) {
                            onSearchQueryChange?(newValue ?? "")
                        }
                    }

            case .checkbox:
                checkboxView(for: field, exclusive: false)

            case .radio:
                checkboxView(for: field, exclusive: true)
            }

        } else if let link = span.link {

            Button {
                onLinkTap?(link)
            } label: {
                Text(span.text)
                    .font(Theme.micronFont(size: UIFont.preferredFont(forTextStyle: .body).pointSize, bold: span.bold, italic: span.italic))
                    .foregroundStyle(Theme.accent)
                    .underline()
            }
            .buttonStyle(.plain)

        } else if !span.text.isEmpty {

            Text(span.text)
                .font(Theme.micronFont(size: UIFont.preferredFont(forTextStyle: .body).pointSize, bold: span.bold, italic: span.italic))
                .foregroundStyle(span.foreground.map { Theme.legiblePageColor($0, isDarkMode: colorScheme == .dark) } ?? Theme.textPrimary)
        }
    }


    private func checkboxView(for field: MicronField, exclusive: Bool) -> some View {

        let checked = formState.isChecked(fieldName: field.name, value: field.value)

        return Button {
            formState.setChecked(!checked, value: field.value, fieldName: field.name, exclusive: exclusive)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconName(checked: checked, exclusive: exclusive))
                    .foregroundStyle(checked ? Theme.accent : Theme.textSecondary)
                Text(field.label)
                    .font(Theme.micronFont(size: UIFont.preferredFont(forTextStyle: .body).pointSize))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }


    private func iconName(checked: Bool, exclusive: Bool) -> String {

        if exclusive {
            return checked ? "largecircle.fill.circle" : "circle"
        }

        return checked ? "checkmark.square.fill" : "square"
    }


    private func textBinding(for field: MicronField) -> Binding<String> {
        Binding(
            get: { formState.textValues[field.name] ?? field.initialText },
            set: { formState.textValues[field.name] = $0 }
        )
    }


    /// A search box wants the system's normal predictive-text/autofill
    /// keyboard behavior — it's natural-language input, unlike a claim
    /// form's name/hash/address fields, where autocorrect actively hurts
    /// (confirmed the hard way this session: iOS "corrected" a typed
    /// hostname into a different word entirely). Micron itself has no
    /// field-type hint for this, so this keys off Tux's own established
    /// convention of always naming its search field "q" — narrow, but
    /// explicit and easy to extend if another server adopts it too.
    private func isSearchQuery(_ field: MicronField) -> Bool {
        field.name == "q"
    }
}


/// Lays out children left-to-right, wrapping to a new row instead of
/// overflowing when the next child doesn't fit — the wrapping behavior
/// SwiftUI's HStack deliberately doesn't provide. Used instead of
/// HStack for a field row's spans so a wide text field plus its submit
/// link/label drop to a second line on a narrow phone screen rather
/// than running past the edge with no way to reach the rest of the row.
private struct FlowLayout: Layout {

    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {

        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {

            let size = subview.sizeThatFits(.unspecified)

            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }

            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }

        totalHeight += rowHeight

        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {

        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {

            let size = subview.sizeThatFits(.unspecified)

            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
