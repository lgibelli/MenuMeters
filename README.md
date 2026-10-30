# MenuMeters

MenuMeters is a set of CPU, memory, disk, and network meters for the macOS
menu bar. It is based on the classic MenuMeters by Alex Harper, was kept
running on modern macOS by Yuji Tachikawa and many contributors, and was
rewritten in Swift by gonejack. This fork adds an audit of that rewrite, the
fixes it found, and signed automatic updates. Releases are published at
<https://www.salamacchine.it/apps/menumeters/>.

## Requirements

- macOS 26 Tahoe or later (Apple Silicon and Intel)
- Xcode 26 or later, **or** the Command Line Tools

The app is a universal binary (`arm64` + `x86_64`) and is written in Swift with
programmatic AppKit views. There are no nibs or Objective-C sources.

## Updates

MenuMeters updates itself with [Sparkle](https://sparkle-project.org). It
checks <https://www.salamacchine.it/apps/menumeters/appcast.xml> once a day
and asks before installing anything. An update is installed only if its
archive is signed with this fork's Ed25519 key and the app inside is signed by
the same Developer ID team as the running copy. The About tab of the
preferences turns the daily check off, and has a Check Now button.

## Features

- CPU usage, per-core graphs, temperature, and a top-process list
- Disk activity and free-space meters with several icon sets
- Memory usage, pressure, paging, and swap information
- Network throughput, interface selection, and PPP/VPN support
- Configurable colors, widths, intervals, and menu-bar display modes
- PowerMate support, and a login item (see below)

MenuMeters adds itself to the login items on the first launch only. After that
the choice is yours: the Startup checkbox in the About tab of the preferences
turns it on and off, and so does System Settings → General → Login Items.

The app stores its settings in the standard domain for its bundle identifier,
`it.salamacchine.menumeters`. On the first launch it copies them once from
`com.yujitach.MenuMeters`, the identifier of MenuMeters 3.0 and earlier, or,
when that domain is empty, from the `com.ragingmenace.MenuMeters` preferences
of 2.1.6 and earlier. Colors saved by 2.1.6 and earlier use the legacy
`NSArchiver` format, which is no longer decoded; those colors fall back to the
defaults while the remaining preferences are still imported.

When you install this version over MenuMeters 3.0 or earlier, remove the old
copy: it has a different bundle identifier, so macOS treats it as a separate
app with its own login item. If both start, the new one quits the old one.
If you ever installed a build made between commits `933ae2a` and `74eea79`,
delete it: those builds trusted an update key that does not belong to this
fork.

## Build

### Xcode

1. Open `MenuMeters.xcodeproj`.
2. Select the `MenuMeters` scheme and the `My Mac` destination.
3. Build and run.

The project signs ad hoc, with the hardened runtime, for local builds; release
builds are made with `build-clt.sh` (see Release signing). Xcode fetches
Sparkle 2.10.1 as a Swift package. The app's deployment target is macOS 26.0.

### Command Line Tools only

```sh
./build-clt.sh
```

This produces a complete `out/MenuMeters.app` bundle containing the universal
executable, the Sparkle framework, localized strings, disk icons, the About
text, and the license notices. It is signed with the hardened runtime: ad hoc
by default, or with your Developer ID when `release.env` names your team. The
first build downloads Sparkle 2.10.1 once into `build/vendor` and checks it
against a pinned SHA-256. Run the app with `open out/MenuMeters.app` or copy it
to `/Applications`.

To update an existing installation, quit MenuMeters first and replace the
whole bundle. Remove the old one before copying: `ditto` merges into an
existing bundle, and files left over from an older version break its
signature.

```sh
rm -rf /Applications/MenuMeters.app
ditto out/MenuMeters.app /Applications/MenuMeters.app
```

During development, a build can be removed from the login items without
opening the UI:

```sh
out/MenuMeters.app/Contents/MacOS/MenuMeters --unregister-login-item
```

## Release signing

Releases are signed with a Developer ID, notarized, and published with a
signed appcast:

1. Copy `release.env.example` to `release.env` and fill in your team ID and
   notarytool profile.
2. `./Scripts/notarize.sh` builds, signs, notarizes and staples
   `out/MenuMeters.app`.
3. `./Scripts/make-dmg.sh` wraps it in a signed, notarized disk image in
   `build/`.
4. `./Scripts/make-appcast.sh` signs the disk image with the Sparkle Ed25519
   key in the login keychain (account `menumeters`) and writes
   `build/appcast/appcast.xml`, with the release notes from
   `Docs/RELEASE-NOTES.md`.
5. Attach the disk image to the GitHub release `v<version>`, and publish the
   appcast at the feed URL in `MenuMeters-Info.plist`.

The private update key never leaves the release machine. Back it up with
`build/vendor/sparkle-2.10.1/bin/generate_keys --account menumeters -x <file>`.

## Verification

```sh
./build-clt.sh
lipo -info out/MenuMeters.app/Contents/MacOS/MenuMeters
codesign --verify --deep --strict out/MenuMeters.app
```

There is no automated test suite. The build script is the reference build and
compiles every Swift source file for both architectures with the current SDK.
GitHub Actions runs the Command Line Tools build and the Xcode project build on
every push and pull request.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/MenuMeters/` | Swift app lifecycle, preferences, meters, temperature, PowerMate, login item, updater |
| `Resources/` | Localizations, disk icon TIFFs, app icon, About RTF, default preferences, release page, Sparkle license |
| `MenuMeters-Info.plist` | Bundle metadata, deployment target, update feed and key |
| `build-clt.sh` | Universal app-bundle build without Xcode |
| `Scripts/` | Shared build settings and the release scripts |
| `Docs/Modernization.md` | Detailed modernization and compatibility notes |
| `Docs/Acknowledgements.md` | Third-party code and its licenses |
| `Docs/RELEASE-NOTES.md` | Release notes shown in the update alert |

## License

MenuMeters is free software under the GNU General Public License version 2
(`LICENSE`). Third-party code and its licenses are listed in
[`Docs/Acknowledgements.md`](Docs/Acknowledgements.md), which ships in the app
bundle together with Sparkle's own notice.

## Modernization notes

The codebase was originally written for Mac OS X 10.2–10.4 and later kept
running through a series of compatibility layers. The current version has been
rewritten in Swift and uses `NSStatusItem` directly rather than the private
`NSMenuExtra` API. See [`Docs/Modernization.md`](Docs/Modernization.md) for the
architecture and migration details.

## Other versions and related software

If you run a sufficiently new macOS, also consider these actively maintained
menu-bar monitors:

- <https://github.com/exelban/stats>
- <https://iglance.github.io>
- <https://github.com/gao-sun/eul>

Other forks of MenuMeters:

- <https://github.com/emcrisostomo/MenuMeters> (DMG installers)
- <https://gitlab.com/axet/MenuMeters> (CPU-meter features)

## Background

MenuMeters was originally developed at
<http://www.ragingmenace.com/software/menumeters/>. The original version stopped
working on El Capitan and later because SystemUIServer no longer loads
third-party menu extras. This fork runs as a faceless app that uses
`NSStatusItem` instead of `NSMenuExtra`. Since Catalina it is an independent
app rather than a System Preferences pane.
