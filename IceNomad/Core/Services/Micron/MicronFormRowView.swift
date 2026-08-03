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

            HStack(alignment: .firstTextBaseline, spacing: 6) {

                if alignment != .leading {
                    Spacer(minLength: 0)
                }

                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                    spanView(for: span)
                }

                if alignment != .trailing {
                    Spacer(minLength: 0)
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


    @ViewBuilder
    private func spanView(for span: MicronSpan) -> some View {

        if let field = span.field {

            switch field.kind {

            case .text:
                TextField("", text: textBinding(for: field))
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.micronFont(size: UIFont.preferredFont(forTextStyle: .body).pointSize))
                    .frame(width: CGFloat(min(max(field.width, 4), 40)) * 9)
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
