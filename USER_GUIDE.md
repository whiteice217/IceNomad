# Getting Started with IceNomad

A plain-language guide for anyone who's never touched Reticulum before. No networking background required.

---

## What is Reticulum, actually?

Normal messaging apps work like this: you send a message, it goes to a company's servers, the company hands it to your friend. If the company's servers go down, or decide to ban you, or get subpoenaed — that's out of your hands.

**Reticulum has no company and no servers.** It's a set of rules for how devices talk to each other directly, hopping the message along from device to device until it reaches whoever it's addressed to. Anyone can run a piece of that network from their own computer, phone, or radio — including you, just by having IceNomad open.

A few things that fall out of that:

- **Your identity isn't an account.** When you first open IceNomad, it generates a real cryptographic keypair on your device — that *is* your identity. There's no username/password, no company database with your info in it, nothing to "sign up" for.
- **It works two very different ways.** Over the regular internet (fast, easy, needs an existing internet connection), or over actual radio hardware called **LoRa** (works with zero internet at all — just two radios in range of each other, or a chain of them). IceNomad supports both, and you can use either or both at once.
- **"The mesh"** is just the informal name for everyone doing this at the same time — every phone, computer, and radio node connected this way, all reachable from each other, hop by hop.

You don't need to understand the plumbing to use any of this. The rest of this guide is about what you'll actually tap on.

---

## Getting Connected

The first time you open IceNomad, a short setup walks you through two things:

1. **Pick a name.** This is what other people see when your device announces itself on the mesh. Change it any time later.
2. **Pick how you connect.** For almost everyone starting out, choose **Use IceNomad** — that's our own always-on relay, a doorway onto the wider mesh over the regular internet. It also unlocks Tux (see below) as your Browser's home page, with real search and caching built in.

If you already own a physical LoRa radio (an **RNode**), you can add it instead or alongside — over Bluetooth, WiFi, or (on Mac) plugged in by USB. That lets you talk to people nearby with no internet involved at all. You can always add, remove, or switch connections later from **Settings → Manage Connections** — nothing here is permanent.

Not sure which to pick? Use IceNomad. You can add an RNode any time once you've got the hang of things.

---

## Messaging

Messaging in IceNomad uses **LXMF** — Reticulum's messaging format. Think of it like email: your address is a long identifier (not tied to a phone number), and messages get delivered even if you and the other person aren't both online at the exact same moment.

### Finding your own address

Open the **Messages** tab. Your display name sits at the top — tap it to rename yourself. Right below it are two buttons:

- **Display QR** — shows a scannable code with your address, the easiest way to hand it to someone standing next to you
- **Copy Address** — copies your raw address to paste anywhere (chat, email, wherever)

### Talking to someone

- **Contacts** opens a drawer of everyone you've saved, sliding in from the left
- **New Message** starts a fresh conversation — paste or type someone's address, or pick from a saved contact
- **Announced Contacts** (right-side drawer) shows everyone whose device has recently "announced" itself on the mesh — a live list of people currently reachable, searchable and sortable by name, hop count, or how recently they were heard

Once you're in a conversation, it behaves like any chat app — type, send, done. Tap-and-hold (or right-click on Mac) a conversation in your list for options like deleting it.

### If someone shares a QR code with you

Scan it from **Settings → Manage Connections**. IceNomad figures out what it's for automatically — a person's address opens a new conversation with them, a NomadNet page address opens it in your Browser.

---

## The Browser

The Browser tab lets you visit **NomadNet pages** — the "websites" of Reticulum, hosted by other people's own nodes instead of a company's servers. Anyone running compatible software can host one.

### Finding your way around

If you're connected via the IceNomad relay, your Browser's home page is **Tux** — IceNomad's own built-in search engine for the mesh. Type into the search/address bar and:

- If it looks like a search (a word, a phrase), you'll get live suggestions as you type — real pages the AI has actually read and can describe, not just a list of raw links
- If you already know a specific address (a long hash, or a claimed friendly `.mu` name), just type or paste it directly

A small colored badge appears at the top of a page telling you how it loaded — blue for Tux's fast, best-looking version, pale blue for a plain cached copy, green for a genuine live connection straight to that node. You don't need to do anything with this, it's just there so you know what you're looking at.

### Useful buttons on the Browser bar

- **Home** (house icon) — back to Tux's homepage
- **Star** — save the current page to your Favorites, organized into folders
- **Tux Cache toggle** — on by default; turns off to always fetch pages live instead of from Tux's cache (slower, but guaranteed current)
- **"Browse the Reticulum Net"** — a live-updating list of NomadNet nodes currently announcing on the mesh, if you want to explore rather than search
- **Downloads** — anything you've saved from a page

### If a page doesn't load

Not every node on the mesh is online all the time — someone's phone might be asleep, or their radio might be out of range. If a page won't load, that's usually why. Try again later, or check **"Browse the Reticulum Net"** to see who's currently reachable.

---

## Don't Want to Install Anything? Use Tux from a Regular Browser

Everything in the previous section is also available at **[tux.icenomad.net](https://tux.icenomad.net)** from an ordinary web browser — Safari, Chrome, whatever's already on your phone or computer. No app to install, no Reticulum identity to set up, nothing to configure. This is the easiest way to try searching the mesh, or to point someone else at it who isn't ready to install anything yet.

From the website you can:

- **Search** the same live index IceNomad's own address bar uses
- **Browse pages**, including on-demand fetching one Tux hasn't crawled yet, the same as the app's own live tier
- **Browse categories** — everything the AI has grouped sites into, drilling down from broad topics into more specific ones
- **[Claim a friendly `.mu` name](https://tux.icenomad.net/claim)** for your own node, so people can find you by name instead of a 32-character hash

One real limit: the website is browsing-only. **Sending or receiving LXMF messages needs your own Reticulum identity**, which only a real client like IceNomad has — the website has no identity of its own to message from. For messaging, you'll need the app (or another Reticulum client); for everything else, the website works on its own.

---

## Getting Support

Stuck, found a bug, or just have an idea? All of these reach a real person:

- **Settings → Report a Bug on GitHub** — the best option if you can describe what happened; it's tracked and never gets lost
- **Settings → Email Support**
- **Settings → Message the Developer** — a real LXMF message, sent the same way you'd message anyone else in the app

If IceNomad or Tux stops working entirely and you can't reach any of the above from inside the app, the project's [GitHub repository](https://github.com/whiteice217/IceNomad) (linked from Tux's own homepage too) is always reachable independently of the app.

Be patient — this is a small, independently-run project, not a company with a support team. Every report genuinely gets read.
