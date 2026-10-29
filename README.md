# YT Music

A tiny native macOS wrapper around [YouTube Music](https://music.youtube.com). It is a plain AppKit window around a WKWebView, with no Electron. It adds media keys, Control Center and Now Playing support, and it keeps playing when you close the window.

It is distributed as a Homebrew tap that **builds from source on your Mac**, so there is no notarized binary to download.

## Why this exists

The `ytmdesktop-youtube-music` cask was disabled because its prebuilt app fails Gatekeeper: it is unsigned and not notarized. Homebrew 5 also removed `--no-quarantine`, so the usual workaround no longer works. See the [cask's status](https://formulae.brew.sh/cask/ytmdesktop-youtube-music) for the current policy.

Apps compiled on your own machine never get the quarantine flag, and on Apple silicon the toolchain ad-hoc signs them. A formula that builds from source sidesteps the problem entirely.

## Install

Requires macOS 13 (Ventura) or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

```bash
brew tap caboose-ai/ytmusic
brew trust --formula caboose-ai/ytmusic/ytmusic
brew install ytmusic
```

`brew trust` is needed because the formula comes from a third-party tap. Homebrew 5 asks you to trust it explicitly before installing.

### /Applications

The formula copies `YTMusic.app` into `/Applications` on every install and upgrade, so Spotlight, Launchpad and Raycast find it and keep finding it across versions. A symlink would not survive upgrades: launchers resolve it down to the versioned Cellar folder, which Homebrew deletes when it upgrades.

Open **YT Music** from Spotlight. Quit the app before upgrading so the copy can be replaced.

## Usage

- Sign in to your Google account once. The login persists across relaunches.
- Closing the window hides it and music keeps playing. Click the Dock icon to bring it back, or press ⌘0.
- Media keys and the Control Center Now Playing widget control playback.

| Action | Shortcut |
| --- | --- |
| Reload | ⌘R |
| Back / Forward | ⌘[ / ⌘] |
| Home | ⇧⌘H |
| Full Screen | ⌃⌘F |
| Play/Pause | ⌘P |
| Next / Previous | ⌥⌘→ / ⌥⌘← |
| Show main window | ⌘0 |

Links to sites outside YouTube and Google open in your default browser.

## Updating

```bash
brew update
brew upgrade ytmusic
```

To track the latest `main` instead of the tagged release: `brew install --HEAD ytmusic`.

## Development

```bash
swift build
scripts/build-app.sh dist && open dist/YTMusic.app
```

The layout:

- `Sources/YTMusic/AppDelegate.swift`: window, navigation policy, hide-on-close.
- `Sources/YTMusic/PlayerBridge.swift`: injected page script, Now Playing info, remote commands.
- `Sources/YTMusic/MainMenu.swift`: the main menu, including the Edit menu that ⌘V needs.
- `scripts/build-app.sh`: builds the `.app` bundle, icon and ad-hoc signature.
- `Formula/ytmusic.rb`: the Homebrew formula.

The version lives in `VERSION` and is written into `Info.plist` at build time.

## Limitations

- This is an unofficial wrapper. It is not affiliated with or endorsed by Google or YouTube.
- Music is streamed by YouTube Music through the page, so the usual YouTube Music terms apply.

## License

MIT. See [LICENSE](LICENSE).
