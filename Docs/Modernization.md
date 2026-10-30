# Modernization notes

MenuMeters dates back to the Mac OS X 10.2 era. The current version is a Swift
rewrite of the maintained fork: the user-facing meters and preferences are
preserved, while the old Objective-C menu-extra architecture and its
compatibility shims are gone.

## Architecture

MenuMeters is now a single Swift application. It has no nib, no Objective-C
sources, and no preference pane.

| File | Responsibility |
| --- | --- |
| `main.swift` | Creates `NSApplication`, installs the app delegate, and runs the accessory app |
| `AppDelegate.swift` | Startup, single-instance handling, meter creation, main menu |
| `MenuExtraBase.swift` | Shared `NSStatusItem` lifecycle, timers, menu plumbing, theme changes, Activity Monitor switching |
| `CPUExtra.swift`, `CPUStats.swift`, `CPUTopProcesses.swift`, `Uptime.swift` | CPU meter, graphs, top processes, load and uptime |
| `DiskExtra.swift`, `DiskIO.swift`, `DiskSpace.swift` | Disk activity and volume-space meters |
| `MemExtra.swift`, `MemStats.swift` | Memory meter, pressure, paging, and swap information |
| `NetExtra.swift`, `NetConfig.swift`, `NetStats.swift`, `NetPPP.swift` | Network throughput, interfaces, and PPP/VPN support |
| `PrefsWindow.swift` | Programmatic five-tab preferences and About window |
| `Defaults.swift` | Typed preferences, validation, and legacy migration |
| `Support.swift` | Constants, localization, notifications, login item, activation policy, app launching, version comparison |
| `Updater.swift` | Sparkle updater, gentle update reminders |
| `TemperatureReader.swift` | SMC / Apple Silicon temperature access |
| `PowerMate.swift` | Griffin PowerMate support |

Each meter owns one `NSStatusItem` and is created independently. A failure in
one meter does not prevent the preferences window from starting.
The application is an `LSUIElement` accessory app and temporarily switches to a
regular activation policy while the preferences window or an update alert is
open.

The public notification names from the old implementation are retained:
`openPref` and `menuExtraUnloaded`. Meter preference-change
notifications still use the meter bundle identifier as the notification name
and `"prefChange"` as the object.

## Preferences and compatibility

Preferences use `UserDefaults.standard` under the app's bundle identifier,
`it.salamacchine.menumeters`. On first launch the app copies the settings of
MenuMeters 3.0 and earlier from `com.yujitach.MenuMeters`, leaving out the
Sparkle state some of those builds stored. When that domain is empty it imports
values from the old `com.ragingmenace.MenuMeters` domain instead, if that plist
exists; values equal to the bundled defaults are skipped. A migration marker
prevents either import from running again.

The historical meter identifiers are unchanged:

- `com.ragingmenace.MenuMeterCPU`
- `com.ragingmenace.MenuMeterDisk`
- `com.ragingmenace.MenuMeterMem`
- `com.ragingmenace.MenuMeterNet`

This keeps existing preference values working. Colors written by 2.1.6 and
earlier use legacy `NSArchiver` data, which the current app does not decode;
those colors fall back to the defaults while the other preferences are
imported. New colors use secure keyed archives. Downgrading to 2.1.6 or earlier
will show default colors for colors saved by this version.

## API modernization

| Old implementation | Current implementation |
| --- | --- |
| Private `NSMenuExtra` / SystemUIServer menu extras | Public `NSStatusItem` in a standalone accessory app |
| Objective-C app delegate and nib | Swift `NSApplicationDelegate`, programmatic AppKit |
| `NSOnState` / `NSOffState` | `NSControl.StateValue.on` / `.off` |
| `NSArchiver` / `NSUnarchiver` colors | `NSKeyedArchiver` / `NSKeyedUnarchiver` |
| `NSBeginAlertSheet` | `NSAlert` |
| `FSRef` / `FSGetVolumeInfo` | `URL` resource values |
| `IOMasterPort()` | `IOMainPort()` / `kIOMainPortDefault` |
| `NXGetLocalArchInfo()` | `sysctlbyname("hw.machine")` |
| `NSColor.ignoresAlpha` | `NSColorWell.supportsAlpha` |
| `String(cString:)` from raw buffers | Bounded UTF-8 conversion |
| `/usr/bin/top` subprocess | `/bin/ps` run directly, without a shell, off the main thread |
| `/bin/sh -c "ifconfig … \| egrep …"` | `/sbin/ifconfig -v <name>` run directly, parsed in Swift, off the main thread |
| AppleScript / System Events automation | `AXUIElement` accessibility traversal, best effort |
| `LSSharedFileList` | `SMAppService.mainApp` |
| Fixed `NSTimer` selectors | Block-based timers with weak captures and tolerance |

Timers keep the user-selected interval and use tolerance so the system can
coalesce wake-ups. Disk, CPU, memory, and network formatters are created once
and configured with properties instead of being round-tripped through an
archiver. CPU and package counts are cached file-private values with guards
against zero.

## Resources and build layout

All app resources live in `Resources/`:

- `Resources/*.lproj/` contains `Localizable.strings`,
  `MenuMetersPref.strings`, and `DiskImageSet.strings`.
- `Resources/DiskIcons/` contains the TIFF icon sets.
- `Resources/MenuMeters.icns` is the app icon.
- `Resources/Welcome.rtf` is shown in the About tab.
- `Resources/com.ragingmenace.MenuMeters.plist` provides the bundled defaults
  used during migration.
- `Resources/releases.html` is the release-history page.
- `Resources/Sparkle-LICENSE.txt` is Sparkle's license notice, shipped in the
  bundle.
- `Resources/MenuMeters-adhoc.entitlements` is used for ad hoc signing only.

Both build paths copy the disk TIFFs and localized tables to the top level of
`Contents/Resources`, which is where `NSImage(named:)` and
`Bundle.localizedString(forKey:value:table:)` expect them.

`build-clt.sh` is the reference build. It compiles every Swift source for
`arm64` and `x86_64`, embeds `Sparkle.framework`, copies the resources, and
signs the resulting `out/MenuMeters.app` with the hardened runtime. Sparkle is
the only bundled third-party framework. The script downloads the official
2.10.1 release once into `build/vendor` and checks it against a pinned
SHA-256; the Xcode project gets the same version as a Swift package.

Ad hoc builds carry one entitlement,
`com.apple.security.cs.disable-library-validation`
(`Resources/MenuMeters-adhoc.entitlements`). Without a team identifier,
library validation would refuse to load Sparkle. Developer ID builds have no
entitlements, and library validation applies in full.

The Xcode project contains the same sources and resources and uses resource
variant groups for the localized string tables. The shared `MenuMeters` scheme
builds the app; CI runs both the Xcode and Command Line Tools builds.

## Deployment and signing

- Minimum deployment target: **macOS 26.0**.
- Architectures: `arm64` and `x86_64`.
- Swift language mode: Swift 5.
- Every build has the hardened runtime. Local builds are signed ad hoc;
  release builds are signed with a Developer ID, notarized, and stapled by
  `Scripts/notarize.sh` and `Scripts/make-dmg.sh`.
- Updates come through Sparkle from
  `https://www.salamacchine.it/apps/menumeters/appcast.xml`, checked once a
  day. The appcast is signed by `Scripts/make-appcast.sh` with an Ed25519 key
  that only the release machine holds; the public half is `SUPublicEDKey` in
  `MenuMeters-Info.plist`. Sparkle also requires the update to be signed by
  the same Developer ID team as the running app.

## Licenses

MenuMeters is distributed under the GNU General Public License version 2.
Every Swift source carries the GPL notice, an SPDX identifier, and a dated
"Changes" list, as section 2(a) of the license asks of modified files. Code
taken from other projects is credited in the file it is used in and listed,
with the full license text, in `Docs/Acknowledgements.md`:

- the SMC key-description lookup, from VirtualSMC's `smcread.c`
  (BSD-3-Clause);
- the Apple silicon sensor access, from freedomtan/sensors (BSD-3-Clause), by
  way of fermion-star/apple_sensors;
- the read-only volume check, from Squirrel.Mac (MIT);
- Sparkle (MIT, with the external licenses in its notice).

Both build paths copy `LICENSE`, `Acknowledgements.md`, and Sparkle's own
notice (`Resources/Sparkle-LICENSE.txt`) into the app bundle.

## Known limitations and follow-up work

- There is no automated test suite. `./build-clt.sh` compiles every source file
  for both architectures and the CI workflow builds the Xcode project as well.
- Activity Monitor's toolbar is not public API. The accessibility traversal
  used for pane switching is intentionally best effort and may need adjustment
  after major Activity Monitor redesigns. It requires Accessibility permission.
- Colors archived by MenuMeters 2.1.6 and earlier are not decoded and fall
  back to the defaults. Login items registered by the old preference-pane
  version are also not removed automatically; use System Settings to delete
  stale entries.
- The preference window uses fixed frames inherited from the old nib. A future
  layout pass could make it resize more gracefully.

## Verification

```sh
./build-clt.sh
lipo -info out/MenuMeters.app/Contents/MacOS/MenuMeters
codesign --verify --deep --strict out/MenuMeters.app
```

The Xcode build can be run with a full Xcode installation:

```sh
xcodebuild \
  -project MenuMeters.xcodeproj \
  -scheme MenuMeters \
  -configuration Release \
  -destination "platform=macOS" \
  build
```
