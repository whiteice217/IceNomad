//
//  TuxAdminWebView.swift
//  IceNomad
//
//  Reached only by tapping the homepage's Tux logo 7 times (see
//  TuxHTMLWebView's admin-gate JS) — a hidden, app-only shortcut to
//  Tux's real admin dashboard, same "tap the build number" pattern as
//  iOS's own hidden developer menu. The tap sequence is purely a
//  discoverability gate against stray taps; the actual security is
//  still Tux's own server-side HTTP Basic Auth on /admin — never
//  bypassed or special-cased here.
//
//  A native SwiftUI login form validates the credentials first (a
//  plain URLSession request, checked for 200 vs. 401), rather than
//  relying on WKWebView's own implicit handling of the 401 challenge —
//  confirmed live that WKWebView does NOT reliably show the system's
//  native Basic Auth prompt on its own; without an explicit
//  WKNavigationDelegate handling `didReceive challenge`, it just
//  rendered Tux's raw 401 JSON body as page content instead of
//  prompting. This also lets wrong credentials get Bryan's exact
//  requested behavior (a clear "wrong login" message, then straight
//  back to the homepage) instead of the OS's generic retry alert.
//  Once validated, the credential is handed to the actual admin
//  WebView's own navigationDelegate, which answers every subsequent
//  Basic Auth challenge (pagination, /admin/ai, …) with it directly —
//  never prompts again for the rest of this admin session.
//

import SwiftUI
import WebKit

struct TuxAdminWebView: View {

    var onDone: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var isValidating = false
    /// Retryable — a network hiccup, not a rejected credential; stays
    /// on the login form so the user can just try again.
    @State private var networkErrorMessage: String?
    /// Not retryable — a real 401. Shown as a dismissing alert per
    /// Bryan's spec ("say wrong login and go back to the homepage");
    /// its own OK button is what actually calls onDone().
    @State private var showingWrongLoginAlert = false
    @State private var validatedCredential: URLCredential?

    private static let adminURL = URL(string: "https://tux.icenomad.net/admin")!

    var body: some View {

        NavigationStack {

            Group {

                if let credential = validatedCredential {
                    AdminWebView(url: Self.adminURL, credential: credential)
                } else {
                    loginForm
                }
            }
            .navigationTitle("Tux Admin")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .alert("Wrong Login", isPresented: $showingWrongLoginAlert) {
            Button("OK", action: onDone)
        } message: {
            Text("That username or password isn't right.")
        }
    }


    private var loginForm: some View {

        Form {

            Section {

                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .onSubmit(validate)

            } footer: {
                Text("Signs in to Tux's admin dashboard directly.")
            }

            if let networkErrorMessage {
                Text(networkErrorMessage)
                    .font(.subheadline)
                    .foregroundStyle(Theme.danger)
            }

            Button {
                validate()
            } label: {
                if isValidating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Log In")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(username.isEmpty || password.isEmpty || isValidating)
        }
    }


    private func validate() {

        guard !username.isEmpty, !password.isEmpty else { return }

        isValidating = true
        networkErrorMessage = nil

        let credential = URLCredential(user: username, password: password, persistence: .forSession)

        var request = URLRequest(url: Self.adminURL, timeoutInterval: 8)
        let authData = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(authData)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, error in

            DispatchQueue.main.async {

                isValidating = false

                guard let http = response as? HTTPURLResponse else {
                    networkErrorMessage = "Couldn't reach Tux — check your connection and try again."
                    return
                }

                if http.statusCode == 200 {

                    // Stored so anything else that independently
                    // challenges this protection space (unlikely here,
                    // but harmless) can also find it — the WebView's own
                    // delegate below doesn't actually depend on this,
                    // it already holds the credential directly.
                    let protectionSpace = URLProtectionSpace(
                        host: Self.adminURL.host ?? "",
                        port: 443,
                        protocol: "https",
                        realm: nil,
                        authenticationMethod: NSURLAuthenticationMethodHTTPBasic
                    )
                    URLCredentialStorage.shared.set(credential, for: protectionSpace)

                    validatedCredential = credential

                } else if http.statusCode == 401 {
                    showingWrongLoginAlert = true
                } else {
                    networkErrorMessage = "Tux returned an unexpected error (\(http.statusCode))."
                }
            }
        }.resume()
    }


    /// Unlike TuxHTMLWebView, every link (pagination, category
    /// browsing, "Recrawl", "Log out", …) navigates normally in
    /// place — there's no BrowserState PageRef concept to route admin
    /// pages through, this is just a real embedded browser scoped to
    /// Tux's admin area.
    private struct AdminWebView: UIViewRepresentable {

        let url: URL
        let credential: URLCredential

        func makeUIView(context: Context) -> WKWebView {
            let webView = WKWebView()
            webView.navigationDelegate = context.coordinator
            webView.load(URLRequest(url: url))
            return webView
        }

        func updateUIView(_ webView: WKWebView, context: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(credential: credential)
        }

        final class Coordinator: NSObject, WKNavigationDelegate {

            let credential: URLCredential

            init(credential: URLCredential) {
                self.credential = credential
            }

            func webView(
                _ webView: WKWebView,
                didReceive challenge: URLAuthenticationChallenge,
                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
            ) {

                guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic else {
                    completionHandler(.performDefaultHandling, nil)
                    return
                }

                completionHandler(.useCredential, credential)
            }
        }
    }
}
