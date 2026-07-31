//
//  ContactsManagerPopover.swift
//  IceNomad
//
//  A management surface for saved contacts (rename, remove, multi-select
//  delete) — they were only ever visible passively at the bottom of New
//  Conversation before, with no way to edit or clear them. Same floating-
//  popover pattern as MUSitesDropdown (Browser) and FavoritesManagerPopover
//  (Browser).
//

import SwiftUI

struct ContactsManagerPopover: View {

    @ObservedObject var contactStore: ContactStore
    let onSelect: (String) -> Void

    @State private var renamingHex: String?
    @State private var renameText = ""

    @State private var isSelecting = false
    @State private var selectedHexes: Set<String> = []

    var body: some View {

        VStack(alignment: .leading, spacing: 0) {

            HStack {

                Text("Contacts")
                    .font(.headline)

                Spacer()

                if !contactStore.contacts.isEmpty {

                    Button(isSelecting ? "Done" : "Select") {

                        isSelecting.toggle()

                        if !isSelecting {
                            selectedHexes.removeAll()
                        }
                    }
                    .font(.subheadline)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if contactStore.contacts.isEmpty {

                Text("No contacts saved yet — labeling someone in a chat, or adding one from New Message, saves them here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)

            } else {

                ScrollView {

                    LazyVStack(alignment: .leading, spacing: 0) {

                        ForEach(contactStore.contacts) { contact in

                            contactRow(contact)

                            Divider()
                                .padding(.leading)
                        }
                    }
                }
                .frame(maxHeight: 360)

                if isSelecting {

                    Button(role: .destructive) {

                        contactStore.removeContacts(hexes: selectedHexes)
                        selectedHexes.removeAll()
                        isSelecting = false

                    } label: {
                        Label("Delete \(selectedHexes.count) Selected", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.danger)
                    .disabled(selectedHexes.isEmpty)
                    .padding()
                }
            }
        }
        .frame(width: 300)
        .alert("Rename Contact", isPresented: renamingBinding) {

            TextField("Name", text: $renameText)

            Button("Save") {
                if let hex = renamingHex {
                    contactStore.setLabel(renameText, for: hex)
                }
            }

            Button("Cancel", role: .cancel) {}
        }
    }


    private var renamingBinding: Binding<Bool> {

        Binding(
            get: { renamingHex != nil },
            set: { if !$0 { renamingHex = nil } }
        )
    }


    private func contactRow(_ contact: Contact) -> some View {

        let hex = contact.destinationHashHex
        let isChecked = selectedHexes.contains(hex)

        return HStack(spacing: 8) {

            Button {

                if isSelecting {

                    if isChecked {
                        selectedHexes.remove(hex)
                    } else {
                        selectedHexes.insert(hex)
                    }

                } else {
                    onSelect(hex)
                }

            } label: {

                HStack(spacing: 10) {

                    if isSelecting {

                        Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isChecked ? Theme.accent : Theme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {

                        Text(contactStore.displayName(for: hex))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)

                        Text(hex)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if !isSelecting {

                Menu {

                    Button {
                        renameText = contact.customLabel ?? ""
                        renamingHex = hex
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        contactStore.removeContact(hex: hex)
                    } label: {
                        Label("Remove", systemImage: "person.fill.xmark")
                    }

                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
