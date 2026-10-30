//
//  Support.swift
//  MenuMeters
//
//  Shared constants, localization, notifications and small helpers.
//
//  Copyright (c) 2002-2014 Alex Harper
//  Copyright (c) 2015-2026 The MenuMeters contributors (see the Git history)
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
//  2026-10-30  Luca Gibelli: login item follows the user's choice; activation policy helper; new bundle identifier.
//

import Cocoa
import ServiceManagement

// MARK: - Constants

enum MM {
    static let defaultsDomain = "com.ragingmenace.MenuMeters"
    static let obsoleteDomain = "MenuMeters"
    static let prefVersionKey = "MenuMeterPrefVersion"
    static let currentPrefVersion = 8
    static let prefChange = "prefChange"
    static let primaryInterface = "primary"
    static let borderAlpha: CGFloat = 0.8

    static let cpuBundleID = "com.ragingmenace.MenuMeterCPU"
    static let diskBundleID = "com.ragingmenace.MenuMeterDisk"
    static let memBundleID = "com.ragingmenace.MenuMeterMem"
    static let netBundleID = "com.ragingmenace.MenuMeterNet"
    static let prefsBundleID = "com.ragingmenace.MenuMeters"
    static let appBundleID = "it.salamacchine.menumeters"
    /// The bundle identifier of MenuMeters 2.x and 3.0, whose settings are
    /// imported once.
    static let legacyAppBundleID = "com.yujitach.MenuMeters"

    static let allMeterIDs = [cpuBundleID, diskBundleID, memBundleID, netBundleID]
    static let meterCountMax = 25

    // Activity Monitor pane selectors: positive values count from the first
    // radio button, negative values from the last (GPU tabs vary by machine).
    static let cpuPane = 1
    static let diskPane = -2
    static let memPane = -4
    static let netPane = -1

    // Localized menu titles
    static let openActivityMonitorTitle = "Open Activity Monitor"
    static let openPrefsTitle = "Open MenuMeters Preferences…"
    static let noInfoMessage = "No info available"
}

enum CPU {
    static let displayPercent = 1
    static let displayGraph = 2
    static let displayThermometer = 4
    static let displayHorizontalThermometer = 8
    static let percentLarge = 0
    static let percentSmall = 1
    static let percentSplit = 2
    static let thermometerWidth: CGFloat = 11
    static let multiProcGap: CGFloat = 5
    static let labelOnlyWidth: CGFloat = 25
    static let percentBorderWidth: CGFloat = 2

    // Menu indexes
    static let uptimeMenuIndex = 4
    static let taskInfoMenuIndex = 6
    static let loadInfoMenuIndex = 8
#if arch(x86_64)
    static let powerLimitInfoMenuIndex = 10
    static let processLabelMenuIndex = 11
#else
    static let processLabelMenuIndex = 9
#endif
    static var processMenuIndex: Int { processLabelMenuIndex + 1 }
}

enum Disk {
    static let imageSets = ["Color Arrows", "Arrows", "Lights", "Aqua Lights", "Disk Arrows", "Disk Arrows (large)"]
    static let darkImageSets = ["Dark Color Arrows", "Dark Arrows", "Lights", "Aqua Lights", "Disk Arrows", "Disk Arrows (large)"]
    static let arrowsImageSet = 4
    static let arrowsLargeImageSet = 5
    static let viewWidth: CGFloat = 16
}

enum Mem {
    static let displayPie = 1
    static let displayBar = 2
    static let displayGraph = 3
    static let displayNumber = 4
    static let pieWidth: CGFloat = 17
    static let numberShortWidth: CGFloat = 20
    static let numberLongWidth: CGFloat = 26
    static let numberExtraLongWidth: CGFloat = 34
    static let thermometerWidth: CGFloat = 11
    static let pagingWidth: CGFloat = 17
    static let pagingGap: CGFloat = 4

    static let usageMenuIndex = 1
    static let activeWiredMenuIndex = 3
    static let inactiveFreeMenuIndex = 4
    static let compressedMenuIndex = 5
    static let pageInfoMenuIndex = 7
    static let cacheInfoMenuIndex = 8
    static let faultInfoMenuIndex = 9
    static let pressureInfoMenuIndex = 11
    static let swapCountMenuIndex = 13
    static let swapPeakMenuIndex = 14
    static let swapSizeMenuIndex = 15
}

enum Net {
    static let displayArrows = 1
    static let displayThroughput = 2
    static let displayGraph = 4
    static let orientTxRx = 0
    static let orientRxTx = 1
    static let scaleInterfaceSpeed = 0
    static let scalePeakTraffic = 1
    static let scaleLinear = 0
    static let scaleSquareRoot = 1
    static let scaleCubeRoot = 2
    static let scaleLog = 3
    static let graphStandard = 0
    static let graphCentered = 1
    static let graphOpposed = 2
    static let graphInverseOpposed = 3
    static let arrowWidth: CGFloat = 13
    static let gap: CGFloat = 2
}

enum DiskActivity: Int {
    case idle = 0, read, write, readWrite
}

// MARK: - Localization

func L(_ key: String, table: String = "Localizable") -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: table)
}

func LP(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: "MenuMetersPref")
}

func imageSetName(_ name: String) -> String {
    Bundle.main.localizedString(forKey: name, value: name, table: "DiskImageSet")
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted by a meter when the user asks for the preferences window.
    static let openPref = Notification.Name("openPref")
    /// Posted when a status item is removed; object is the meter bundle ID.
    static let menuExtraUnloaded = Notification.Name("menuExtraUnloaded")
}

/// Notification name used to tell one meter that its preferences changed.
func prefChangedName(_ bundleID: String) -> Notification.Name {
    Notification.Name(bundleID)
}

// MARK: - Menu helpers

/// Replaces the title of an existing menu item, creating none.
func liveUpdateMenuItemTitle(_ menu: NSMenu, _ index: Int, _ title: String) {
    guard index >= 0, index < menu.numberOfItems else { return }
    menu.item(at: index)?.title = title
}

func liveUpdateMenuItemTitleAndVisibility(_ menu: NSMenu, _ index: Int, _ title: String?, hidden: Bool) {
    guard index >= 0, index < menu.numberOfItems, let item = menu.item(at: index) else { return }
    if let title { item.title = title }
    item.isHidden = hidden
}

func forceMenuRedraw(_ menu: NSMenu) {
    // NSMenu has no public redraw API; reassigning the delegate makes AppKit
    // rebuild the menu the next time it is displayed.
    let delegate = menu.delegate
    menu.delegate = nil
    menu.delegate = delegate
}

// MARK: - Application launching

enum AppLauncher {
    @discardableResult
    static func open(bundleID: String, path: String, name: String) -> Bool {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return true
        }
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
            return true
        }
        let alert = NSAlert()
        alert.messageText = "Unable to find \(name)"
        alert.informativeText = "\(name) could not be found on this system."
        alert.runModal()
        return false
    }

    static func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Login item

enum LoginItem {
    private static let configuredKey = "LoginItemConfigured"

    /// Registers the app as a login item. Used by the preferences checkbox.
    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            NSLog("MenuMeters: unable to change login item: \(error)")
        }
    }

    static func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers the login item on the first launch only. After that the
    /// choice belongs to the user, in Preferences or in System Settings.
    static func registerOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: configuredKey) else { return }
        defaults.set(true, forKey: configuredKey)
        setEnabled(true)
    }

    /// Records that the user has made a choice, so the first-launch
    /// registration does not override it.
    static func markConfigured() {
        UserDefaults.standard.set(true, forKey: configuredKey)
    }
}

// MARK: - Activation policy

/// MenuMeters is an accessory app with no Dock icon. A window that needs the
/// Dock icon and the app menu, such as the preferences or an update alert,
/// holds a reason while it is up; the last one released returns the app to the
/// menu bar.
enum ActivationPolicy {
    private static var reasons = Set<String>()

    static func hold(_ reason: String) {
        reasons.insert(reason)
        NSApp.setActivationPolicy(.regular)
    }

    static func release(_ reason: String) {
        reasons.remove(reason)
        if reasons.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Version comparison

enum Version {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: .numeric)
    }
}
