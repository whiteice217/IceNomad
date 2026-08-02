# Building IceNomad from Source

The most reliable way to run IceNomad on your Mac today — a locally-built app never picks up the "downloaded from the internet" flag that triggers macOS's stricter Gatekeeper warnings, so there's nothing to click through, no security prompts to fight. Xcode signs it with your own free Apple ID automatically.

Takes about 10 minutes, most of it Xcode installing.

## 1. Install Xcode

Get it free from the [Mac App Store](https://apps.apple.com/us/app/xcode/id497799835). It's a big download — a good excuse for a coffee break.

## 2. Sign into Xcode with your own Apple ID

Any Apple ID works, no paid developer account needed.

- Open Xcode → **Settings** (⌘,) → **Accounts**
- Click **+** → **Apple ID** → sign in

## 3. Get the code

```bash
git clone https://github.com/whiteice217/IceNomad.git
cd IceNomad
open IceNomad.xcodeproj
```

(No `git`? Use GitHub's green "Code" → "Download ZIP" button instead, then double-click `IceNomad.xcodeproj`.)

## 4. Point signing at your own account

The project is currently configured to sign with the author's own team — you'll need to switch that to yours:

- In Xcode's left sidebar, click the top-level **IceNomad** project icon
- Select the **IceNomad** target → **Signing & Capabilities** tab
- Under **Team**, change the dropdown from whatever's selected to **your own name/Apple ID**
- Do this for both the **IceNomad** target — Xcode will regenerate a provisioning profile scoped to your account automatically

If Xcode shows a red error about the bundle identifier being taken, add something to the end of it (Settings → General → Identity → Bundle Identifier) — e.g. `com.saltycapn.icenomad.IceNomad2` — any unique string works, it only matters for signing.

## 5. Run it

- At the top of the Xcode window, next to the Run/Stop buttons, make sure the destination reads **"My Mac (Mac Catalyst)"**
- Press **▶ Run** (or ⌘R)

First build takes a minute or two. After that it's fast. The app launches straight from Xcode — no DMG, no download, no Gatekeeper involved at all.

## Reporting issues

Found a bug, or something feels off? Open an issue at [github.com/whiteice217/IceNomad/issues](https://github.com/whiteice217/IceNomad/issues), or message the developer directly through the app (Settings → Message the Developer) once you're up and running.
