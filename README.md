<p align="center">
  <img src=".github/icon.png?v=1" width="128" alt="SheepKey app icon">
</p>

# 🐑 SheepKey

**Mac keyboard shortcuts inside AnyDesk, TeamViewer and RustDesk — ⌘C, ⌘V, ⌘Z, ⌘S reach the Windows side as Ctrl+C, Ctrl+V, Ctrl+Z, Ctrl+S.**

Remote-desktop clients forward the ⌘ key to Windows as the Win key, so every Mac shortcut you
have in your fingers stops working the moment you are inside a session. Microsoft's own Windows
App translates ⌘ to Ctrl for you; SheepKey does the same for every other client. It lives in
the menu bar, watches which app is in front, and rewrites the modifier keys only while one of
your remote-desktop apps is frontmost. Everywhere else on the Mac nothing changes.

## ⬇️ Download

[![Download SheepKey for macOS](https://img.shields.io/badge/Download-SheepKey_1.0_%289%29_for_macOS-2ea44f?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/bestonehxh/SheepKey/releases/latest)

**[Get the latest release →](https://github.com/bestonehxh/SheepKey/releases/latest)** — download `SheepKey-1.0-9.zip`, unzip, and drag **SheepKey.app** into `Applications`.

> The build is unsigned (not notarized), so macOS will warn on first launch —
> right-click the app and choose **Open**, or run
> `xattr -dr com.apple.quarantine /Applications/SheepKey.app`
>
> Requires macOS 26.4 (Tahoe) or later, Apple Silicon.

## The Sheep family 🐑

SheepKey is one of eight small native macOS apps that share the same sheep icon set:

|  | App | What it does |
|---|---|---|
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepDrop/main/.github/icon.png?v=3" width="44" alt=""> | [SheepDrop](https://github.com/bestonehxh/SheepDrop) | SFTP / SCP / FTP / TFTP file transfer — client and built-in server |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepTerm/main/.github/icon.png?v=3" width="44" alt=""> | [SheepTerm](https://github.com/bestonehxh/SheepTerm) | SSH / Serial / local-shell terminal for network engineers |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepTap/main/.github/icon.png?v=3" width="44" alt=""> | [SheepTap](https://github.com/bestonehxh/SheepTap) | Menu-bar viewer for your Mac's network interfaces with click-to-copy |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepPing/main/.github/icon.png?v=3" width="44" alt=""> | [SheepPing](https://github.com/bestonehxh/SheepPing) | Continuous multi-host ping monitor with per-host logs and CSV export |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepText/main/.github/icon.png?v=3" width="44" alt=""> | [SheepText](https://github.com/bestonehxh/SheepText) | Fast text editor with tree-sitter highlighting and a JavaScript plugin system |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepArt/main/.github/icon.png?v=3" width="44" alt=""> | [SheepArt](https://github.com/bestonehxh/SheepArt) | Screenshot annotation — draw, crop, layers, one-key background removal |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepRadius/main/.github/icon.png?v=4" width="44" alt=""> | [SheepRadius](https://github.com/bestonehxh/SheepRadius) | RADIUS + LDAP lab for 802.1X, device logins and NAC — with a joinable Samba AD |
| <img src="https://raw.githubusercontent.com/bestonehxh/SheepKey/main/.github/icon.png?v=1" width="44" alt=""> | [SheepKey](https://github.com/bestonehxh/SheepKey) | Mac shortcuts (⌘ as Ctrl) inside AnyDesk, TeamViewer and RustDesk |

## Features

- **⌘ becomes Ctrl** while a remote-desktop app is frontmost — ⌘C / ⌘V / ⌘Z / ⌘S / ⌘A / ⌘F
  land on Windows as the Ctrl shortcuts, including the modifier key itself, so clients that
  forward key-down / key-up separately see a real Ctrl press
- Two modes: **Swap ⌘ and ⌃** (⌃ reaches Windows as the Win key, so nothing is lost) or
  **⌘ acts as ⌃** (⌃ untouched)
- **Only in the apps you choose** — AnyDesk, TeamViewer and RustDesk by default; add any app
  from the running list or by picking its `.app`, tick or untick each one
- **Screenshots still work inside a session** — remote clients grab the macOS screenshot
  shortcuts before the system can, so SheepKey intercepts ⇧⌘3 / ⇧⌘4 / ⇧⌘5 (or whatever you
  assigned in System Settings → Keyboard → Shortcuts → Screenshots) and takes the capture
  itself: same folder, same file name, same save / copy behaviour
- ⌘-Tab, ⌘-Space and ⌘-` stay with macOS, so app switching and Spotlight keep working
  mid-session
- Leaving the remote app with ⌘ still held releases the key on the Windows side — no stuck Ctrl
- Near-zero cost: a few nanoseconds per keystroke, 0 % CPU when idle, ~17 MB of memory
- **Launch at login** registered on first run (turn it off from the menu)
- No network requests, no analytics, no third-party dependencies — Apple frameworks only

## Permissions

SheepKey asks for two things on first launch, both in System Settings › Privacy & Security:

- **Accessibility** — required to see and rewrite keystrokes. Without it the app just waits.
- **Screen Recording** — only for taking screenshots inside a remote app. The menu offers it
  the first time it is needed.

## Requirements

- macOS 26.4 (Tahoe) or later, Apple Silicon

## Building

```bash
xcodebuild -project SheepKey.xcodeproj -scheme SheepKey -configuration Release build
```

(or open `SheepKey.xcodeproj` in Xcode 26+ and hit Run). The app is not sandboxed — a
modifying event tap cannot run inside the App Sandbox.

## License

[MIT](LICENSE) © 2026 bestonehxh
