<p align="center">
  <img src="https://raw.githubusercontent.com/whiteice217/IceNomad/main/Images/WanderingPenguin.png" width="160" alt="IceNomad">
</p>

<h1 align="center">IceNomad</h1>

<p align="center">
  <strong>A native Reticulum client for iOS and Mac.</strong><br>
  Decentralized, encrypted communication over Reticulum, LXMF, LoRa, and remote transport nodes — no servers, no gatekeepers.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20macOS-lightgrey" alt="Platform: iOS | macOS">
  <img src="https://img.shields.io/badge/status-active%20development-brightgreen" alt="Status: Active Development">
  <img src="https://img.shields.io/badge/built%20with-Swift%20%26%20SwiftUI-orange" alt="Built with Swift & SwiftUI">
</p>

<p align="center">
  <a href="https://icenomad.net">icenomad.net</a> &nbsp;·&nbsp;
  <a href="https://tux.icenomad.net">tux.icenomad.net</a> &nbsp;·&nbsp;
  <a href="mailto:wanderingpenguin@icenomad.net">wanderingpenguin@icenomad.net</a> &nbsp;·&nbsp;
  <a href="https://github.com/whiteice217/IceNomad/issues">Report an issue</a>
</p>

---

<p align="center">
  <img src="https://raw.githubusercontent.com/whiteice217/IceNomad/main/Images/PlatformShowcase.jpg" width="100%" alt="IceNomad on iPhone and Mac, alongside Tux, IceNomad's built-in Reticulum search engine">
</p>

<p align="center">
  🖥️ <strong>Mac — live</strong> &nbsp;&nbsp;|&nbsp;&nbsp;
  📱 <strong>iPhone — coming soon</strong> &nbsp;&nbsp;|&nbsp;&nbsp;
  🐧 <strong>Linux — in the works</strong>
</p>

---

## Table of Contents

- [About](#about)
- [Features](#features)
- [New to Reticulum?](#new-to-reticulum)
- [Download](#download)
- [Tux — a search engine for Reticulum](#tux--a-search-engine-for-reticulum)
- [Roadmap](#roadmap)
- [Status](#status)
- [The Story](#the-story)
- [Built With](#built-with)
- [Contributing](#contributing)
- [Support IceNomad](#support-icenomad)
- [License](#license)

## About

IceNomad is a native client for the [Reticulum Network Stack](https://reticulum.network), built to bring decentralized mesh communication to your phone and your desktop — the same way, on the same codebase.

Connect over TCP to a remote transport node, or go direct over LoRa with an RNode — by Bluetooth, WiFi, or (on Mac) plugged in over USB. Send messages, browse NomadNet pages, and see the mesh around you, all from a genuinely native SwiftUI app.

## Features

- **Reticulum protocol stack**, implemented in Swift — real identity/crypto, packet routing, Links, and Resource transfers, not a wrapper around someone else's client
- **LXMF messaging** — reliable two-way delivery, contacts that track a peer's live announced name, a persistent message history, notification sounds and unread badges
- **NomadNet browser** — fetches and renders real `.mu` pages, with favorites, downloads, and a home screen you can navigate from
- **Tux search built into the address bar** — live search suggestions as you type, backed by [Tux](https://tux.icenomad.net), Reticulum's own search engine
- **RNode (LoRa) support** — Bluetooth, WiFi, and direct USB serial (Mac), with full radio configuration built into the app
- **Live announce feed** — see peers as they're heard, filterable by LXMF, NomadNet, or specifically what's coming in over LoRa
- **QR code** scanning and sharing for addresses
- **Adaptive light/dark theme**, native on both iOS and Mac
- **First-launch onboarding** with a randomly generated penguin-themed identity, so you're never staring at a blank name field
- **A bundled getting-started guide**, right in the app — Settings → Getting Started, no internet connection required to read it

## New to Reticulum?

Never used a mesh network before? [**Read the User Guide**](USER_GUIDE.md) — a plain-language walkthrough of what Reticulum actually is, getting connected, messaging, browsing, and where to go if you get stuck. No prior networking knowledge assumed. It's also bundled straight into the app itself, under Settings → Getting Started.

## Download

### macOS — available now

IceNomad runs as a genuinely native Mac app, built on the exact same SwiftUI codebase as iOS via Mac Catalyst — not a wrapper, not a separate port.

**[⬇ Download the latest Mac build](https://github.com/whiteice217/IceNomad/releases/latest)** from GitHub Releases. It isn't notarized yet, so macOS will show an "unidentified developer" warning on first launch — right-click the app and choose **Open** (instead of double-clicking) to get past it. No paid developer account was needed to build it, and none is needed to run it.

Prefer to build it yourself? See [BUILDING.md](BUILDING.md) — about 10 minutes, mostly Xcode installing, and it sidesteps the Gatekeeper warning entirely since a locally-built app never picks up the "downloaded from the internet" flag that triggers it.

### iOS — coming soon

The same codebase already runs on iPhone day-to-day during development — public distribution (TestFlight or otherwise) is next up. Watch this repo or [reach out](mailto:wanderingpenguin@icenomad.net) if you'd like to help test it early.

### Linux — in the works

A native Linux build is on the roadmap, using the same shared Reticulum/LXMF core this whole app is already built on. No timeline yet — this section will update the moment there's something to try.

## Tux — a search engine for Reticulum

**Tux is live** at [tux.icenomad.net](https://tux.icenomad.net) — Reticulum's own search engine. It crawls NomadNet's `.mu` pages across the mesh, indexes what it finds, and makes the whole thing searchable, so you don't need to memorize a 32-character hash just to find a page you liked.

- **Real full-text search** over hundreds of crawled nodes, with an AI layer that reads each site and writes a one-line summary for search results
- **Hierarchical categories** — sites get sorted into a small set of top-level topics with real depth underneath (e.g. `Literature > Poetry > French`), browsable at [tux.icenomad.net/categories](https://tux.icenomad.net/categories)
- **Friendly names** — [claim a `.mu` name](https://tux.icenomad.net/claim) for your own node so people can find you by name instead of a hash
- **No client required** — plain HTTPS at tux.icenomad.net works from any browser, no Reticulum stack needed
- **Built into IceNomad** — Tux is the Browser tab's home page (when connected via the IceNomad Public Relay), rendered as its real HTML — not a plainer reconstruction — with the same live search suggestions surfaced right in the address bar

## Roadmap

### Also in progress
- **iOS public distribution** — see [Download](#download) above
- **A native Linux build** — see [Download](#download) above
- **Offline message delivery** — receiving LXMF messages sent while your app wasn't running, via propagation node support
- **Always-on background operation on Mac** — stay reachable without keeping the app window open

## Status

Actively developed. Currently working and in daily use:

- Reticulum protocol integration — real packet routing, Links, Resource transfers
- LXMF messaging, both directions, confirmed reliable
- NomadNet browsing — real pages, real nodes
- Tux search — live at tux.icenomad.net and integrated into the app's address bar
- RNode connectivity over Bluetooth, WiFi, and USB serial
- TCP client interfaces and live connection monitoring
- Native iOS and Mac Catalyst builds from one codebase

## The Story

A wandering penguin, a retired Yeti, and how Tux came to be — [read the story](STORY.md).

## Built With

Swift · SwiftUI · Reticulum · LXMF · LoRa / RNode · NomadNet · Apple's Network Framework

## Contributing

IceNomad is an open-source hobby project — contributions, bug reports, and feature suggestions are always welcome. Open an issue or submit a pull request any time.

## Support IceNomad

I'm the wandering penguin from [the story](STORY.md) — in real life, a nursing student who's loved tech for a lot longer than I've been in medicine. I build and maintain IceNomad out of my own pocket, one trail marker at a time. If you'd like to help keep it going, it's genuinely appreciated — every bit goes straight back into development. No pressure at all; just having you here using it means a lot.

- [Donate via PayPal](https://www.paypal.com/donate/?hosted_button_id=MX56K67Y4PGPS)

**Bitcoin (native):** `3PC2aHq4m71c5nsCytGd37nZbSAWbuHrEM`

<p>
  <img src="https://raw.githubusercontent.com/whiteice217/IceNomad/main/Images/DonateQR_Bitcoin.png" width="140" alt="Bitcoin donation QR code">
</p>

**Crypto — Base network only** (ETH, USDC, or BTC via cbBTC): `0xb708a0A34572Be9C7845E3Caa26733C3F1A2d914`

<p>
  <img src="https://raw.githubusercontent.com/whiteice217/IceNomad/main/Images/DonateQR_Base.png" width="140" alt="Base network donation QR code">
</p>

Only send assets on the **Base** network to that address — anything sent on another network (Ethereum mainnet, native Bitcoin, etc.) may be lost.

Be kind to one another, and share a fish when you can.

— Wandering Penguin ([@whiteice217](https://github.com/whiteice217))

## License

MIT License.
