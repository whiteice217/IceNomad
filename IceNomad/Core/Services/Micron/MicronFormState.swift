//
//  MicronFormState.swift
//  IceNomad
//
//  Live editable state for a Micron page's `<...>` form fields (text
//  inputs, checkboxes, radios) — reseeded fresh from the parsed document
//  every time BrowserState loads a new page (see BrowserState.setContent).
//  MicronFormRowView binds its controls directly to this; a form-submit
//  link tap (MicronLink.isFormSubmit) reads it back out to build the
//  field_* request payload real NomadNet servers expect.
//

import Foundation
import Combine

final class MicronFormState: ObservableObject {

    @Published var textValues: [String: String] = [:]
    @Published var checkedValues: [String: Set<String>] = [:]

    /// Every field name declared anywhere in the current document, in
    /// source order — lets a submit-all ("*") link know the full field
    /// set without re-parsing the page.
    private(set) var allFieldNames: [String] = []

    init(document: MicronDocument = MicronDocument(lines: [])) {

        var seenNames: Set<String> = []

        for field in document.lines.flatMap(\.spans).compactMap(\.field) {

            if !seenNames.contains(field.name) {
                seenNames.insert(field.name)
                allFieldNames.append(field.name)
            }

            switch field.kind {

            case .text:
                textValues[field.name] = field.initialText

            case .checkbox, .radio:
                if field.prechecked {
                    checkedValues[field.name, default: []].insert(field.value)
                }
            }
        }
    }


    func isChecked(fieldName: String, value: String) -> Bool {
        checkedValues[fieldName]?.contains(value) ?? false
    }


    /// `exclusive` (radio) selects `value` and clears every other value
    /// under the same field name — matching real urwid.RadioButton
    /// groups, where a field name IS the group. A checkbox just
    /// inserts/removes its own value independently.
    func setChecked(_ checked: Bool, value: String, fieldName: String, exclusive: Bool) {

        if exclusive {
            checkedValues[fieldName] = checked ? [value] : []
            return
        }

        if checked {
            checkedValues[fieldName, default: []].insert(value)
        } else {
            checkedValues[fieldName]?.remove(value)
        }
    }


    /// Builds the `field_*` payload for a submit link. `names == nil`
    /// means every field on the page (a link's third segment was "*",
    /// real NomadNet's `all_fields` behavior); otherwise only the named
    /// fields are included. An empty/unchecked checkbox group is simply
    /// omitted, matching real NomadNet ("do nothing if not checked") —
    /// not sent as false.
    func fieldPayload(includingOnly names: [String]?) -> [(MsgpackValue, MsgpackValue)] {

        let included = names ?? allFieldNames
        var pairs: [(MsgpackValue, MsgpackValue)] = []

        for name in included {

            if let text = textValues[name] {
                pairs.append((.string("field_" + name), .string(text)))
            } else if let values = checkedValues[name], !values.isEmpty {
                pairs.append((.string("field_" + name), .string(values.sorted().joined(separator: ","))))
            }
        }

        return pairs
    }
}
