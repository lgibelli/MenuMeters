//
//  AppDelegate.swift
//  MenuMeters
//
//  Application lifecycle: preferences, meters and the menu bar.
//
//  Copyright (c) 2015-2026 The MenuMeters contributors (see the Git history)
//  The read-only volume check is adapted from Squirrel.Mac (MIT License);
//  see Docs/Acknowledgements.md.
//
//  This file is part of MenuMeters.
//
//  MenuMeters is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 2 as
//  published by the Free Software Foundation.
//
//  MenuMeters is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with MenuMeters; if not, see <https://www.gnu.org/licenses/>.
//
//  SPDX-License-Identifier: GPL-2.0-only
//
//  Changes:
//  2026-10     gonejack: rewritten in Swift from the Objective-C original.
//  2026-10-30  Luca Gibelli: single instance in both directions, login item on first launch only, Sparkle updates.
//

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let welcomeFile = "Welcome"

    private var prefsWindow: PrefsWindowController?
    private var updater: Updater?
    private var appMenu: NSMenu?
    private var cpuExtra: CPUExtra?
    private var diskExtra: DiskExtra?
    private var netExtra: NetExtra?
    private var memExtra: MemExtra?

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Touching the shared preferences performs the one-time migration from
        // the old com.ragingmenace.MenuMeters domain.
        _ = Prefs.shared
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isRunningOnReadOnlyVolume() {
            alertConcerningAppTranslocation()
        }

        // A newer copy already in the menu bar wins; two would show every meter twice.
        guard !newerInstanceIsRunning() else {
            NSApp.terminate(nil)
            return
        }
        killOlderInstances()

        let updater = Updater()
        self.updater = updater
        appMenu?.insertItem(updater.makeMenuItem(), at: 1)

        prefsWindow = PrefsWindowController(aboutFile: Self.welcomeFile, updater: updater)

        let key = Self.welcomeFile + "Presented"
        if !UserDefaults.standard.bool(forKey: key) {
            prefsWindow?.openAbout(nil)
            UserDefaults.standard.set(true, forKey: key)
        }

        // Meters are created last: a failure while probing hardware must not
        // prevent the preferences from working.
        cpuExtra = CPUExtra(bundleID: MM.cpuBundleID)
        diskExtra = DiskExtra(bundleID: MM.diskBundleID)
        netExtra = NetExtra(bundleID: MM.netBundleID)
        memExtra = MemExtra(bundleID: MM.memBundleID)

        LoginItem.registerOnFirstLaunch()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                      hasVisibleWindows flag: Bool) -> Bool {
        prefsWindow?.showPreferences()
        return true
    }

    // MARK: - Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        self.appMenu = appMenu

        let about = NSMenuItem(title: "About MenuMeters",
                               action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide MenuMeters", action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
                        keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MenuMeters", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout(_ sender: Any?) {
        prefsWindow?.openAbout(sender)
    }

    // MARK: - Single instance and translocation

    private static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// The other running copies of this app, with their bundle versions.
    private func otherInstances() -> [(app: NSRunningApplication, version: String)] {
        let thisProcess = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: MM.appBundleID)
            .filter { $0.processIdentifier != thisProcess }
            .map { app in
                let version = app.bundleURL
                    .flatMap { Bundle(url: $0) }?
                    .infoDictionary?["CFBundleVersion"] as? String ?? "0"
                return (app, version)
            }
    }

    private func newerInstanceIsRunning() -> Bool {
        otherInstances().contains { other in
            let newer = Version.compare(other.version, Self.bundleVersion) == .orderedDescending
            if newer {
                NSLog("MenuMeters: version \(other.version) is already running, ours is \(Self.bundleVersion)")
            }
            return newer
        }
    }

    private func killOlderInstances() {
        for other in otherInstances() {
            NSLog("MenuMeters: terminating instance \(other.version), ours is \(Self.bundleVersion)")
            other.app.terminate()
        }
        // Builds from before the bundle identifier changed are always older,
        // and would show every meter a second time.
        for legacy in NSRunningApplication.runningApplications(withBundleIdentifier: MM.legacyAppBundleID) {
            NSLog("MenuMeters: terminating the copy with the old bundle identifier")
            legacy.terminate()
        }
    }

    private func isRunningOnReadOnlyVolume() -> Bool {
        var info = statfs()
        let path = FileManager.default.fileSystemRepresentation(withPath: Bundle.main.bundleURL.path)
        guard statfs(path, &info) == 0 else {
            // If the volume cannot be inspected, assume the app is translocated.
            return true
        }
        return (info.f_flags & UInt32(MNT_RDONLY)) != 0
    }

    private func alertConcerningAppTranslocation() {
        let alert = NSAlert()
        alert.messageText = "Please move the app after downloading it"
        alert.addButton(withTitle: "OK, I quit the app and move it")
        alert.informativeText = """
            Please move the app to, say, /Applications, using your mouse/trackpad, not from the command line.

            macOS runs downloaded apps from a temporary location, which prevents MenuMeters from registering itself as a login item.

            I am sorry for the inconvenience.
            """
        alert.runModal()
        NSApp.terminate(nil)
    }
}
