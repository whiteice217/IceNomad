<p align="center">
  <img src="https://raw.githubusercontent.com/whiteice217/IceNomad/main/Images/WanderingPenguin.png" width="180" alt="IceNomad">
</p>

<h1 align="center">IceNomad</h1>

<p align="center">
  <strong>A native Reticulum client for iOS and Mac.</strong><br>
  Decentralized, encrypted communication over Reticulum, LXMF, LoRa, and remote transport nodes — no servers, no gatekeepers.
</p>

<p align="center">
  <a href="https://icenomad.net">icenomad.net</a> &nbsp;·&nbsp;
  <a href="mailto:wanderingpenguin@icenomad.net">wanderingpenguin@icenomad.net</a> &nbsp;·&nbsp;
  <a href="https://github.com/whiteice217/IceNomad/issues">Report an issue</a>
</p>

---

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

## Try It on Mac

IceNomad now runs as a genuinely native Mac app, built on the exact same SwiftUI codebase as iOS via Mac Catalyst — not a wrapper, not a separate port. It's in active testing right now.

**The easiest way to run it today is to build it yourself** — see [BUILDING.md](BUILDING.md). It's a 10-minute process (mostly Xcode installing) and sidesteps macOS's Gatekeeper warnings entirely, since a locally-built app never picks up the "downloaded from the internet" flag that triggers them. No paid developer account, no security prompts to fight.

A downloadable DMG is also available for testers — reach out at [wanderingpenguin@icenomad.net](mailto:wanderingpenguin@icenomad.net) for access. Since it isn't notarized yet, macOS will show an "unidentified developer" warning on first launch — right-click the app and choose **Open** (instead of double-clicking) to get past it.

## Tux — a search engine for Reticulum

**Tux is live** at [tux.icenomad.net](https://tux.icenomad.net) — Reticulum's own search engine. It crawls NomadNet's `.mu` pages across the mesh, indexes what it finds, and makes the whole thing searchable, so you don't need to memorize a 32-character hash just to find a page you liked.

- **Real full-text search** over hundreds of crawled nodes, with an AI layer that reads each site and writes a one-line summary for search results
- **Categories that grow on their own** — sites get sorted into an evolving taxonomy (not a fixed list) as more of the mesh gets indexed, browsable at [tux.icenomad.net/categories](https://tux.icenomad.net/categories)
- **Friendly names** — [claim a `.mu` name](https://tux.icenomad.net/claim) for your own node so people can find you by name instead of a hash
- **No client required** — plain HTTPS at tux.icenomad.net works from any browser, no Reticulum stack needed
- **Built into IceNomad** — Tux is the Browser tab's home page (when connected via the IceNomad Public Relay), with the same live search suggestions surfaced right in the address bar

## Roadmap

### Also in progress
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
