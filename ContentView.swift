import SwiftUI

struct ContentView: View {

    @State private var destination = ""
    @State private var page = "Welcome to IceNomad.\n\nEnter a destination and tap Connect."

    var body: some View {

        NavigationStack {

            VStack {

                TextField("Destination Hash", text: $destination)
                    .textFieldStyle(.roundedBorder)

                Button("Connect") {
                    page = "Connecting to \(destination)..."
                }
                .buttonStyle(.borderedProminent)

                Divider()

                ScrollView {
                    Text(page)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }

            }
            .padding()
            .navigationTitle("IceNomad")
        }
    }
}
