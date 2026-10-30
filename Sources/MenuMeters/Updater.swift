//
//  Updater.swift
//  MenuMeters
//
//  Automatic updates, via Sparkle.
//
//  Copyright (c) 2026 Luca Gibelli
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
//  2026-10-30  Luca Gibelli: added, adapted from the Idlewild updater.
//

import Cocoa
import Sparkle

/// Checks for, downloads and installs updates.
///
/// The trust anchor is not the feed. Each archive must carry an Ed25519
/// signature made with the private key that only the release machine holds,
/// and the app inside must be signed by the same team as the copy already
/// running. Whoever controls the web server can serve a different appcast, and
/// Sparkle will refuse everything in it.
///
/// The feed URL, the public key and the check interval live in Info.plist.
/// Sparkle keeps the user's choice about automatic checks in the defaults, so
/// there is deliberately no second copy of that setting here.
final class Updater: NSObject {
    private let reminders = UpdateReminders()
    private let controller: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?

    /// Called on the main thread when a check becomes possible or stops being
    /// possible, for controls that follow `canCheckForUpdates`.
    var onAvailabilityChange: (() -> Void)?

    override init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: reminders)
        super.init()
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates) { [weak self] _, _ in
            DispatchQueue.main.async { self?.onAvailabilityChange?() }
        }
    }

    /// False while a check or an installation is already running.
    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    /// What the preferences checkbox reads and writes, so the checkbox and
    /// Sparkle's own alerts cannot disagree about it.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// "Check for Updates…" for the app menu. The controller is the target, so
    /// AppKit asks it whether the item is enabled.
    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for Updates…",
                              action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                              keyEquivalent: "")
        item.target = controller
        return item
    }
}

/// Gentle reminders. Sparkle asks every app without a Dock icon for these, and
/// warns in the log when it does not get them.
///
/// MenuMeters lives in the menu bar and may not steal focus, so a scheduled
/// update alert would open behind whatever the user is doing and could go
/// unseen for days. While an update is shown the app joins the Dock, which lets
/// the alert come to the front and makes it reachable with Command-Tab, and the
/// Dock icon is badged until the user has seen it. Both are undone when the
/// update session ends.
final class UpdateReminders: NSObject, SPUStandardUserDriverDelegate {
    private static let activationReason = "update"

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        ActivationPolicy.hold(Self.activationReason)
        // A check the user asked for already has their attention.
        guard !state.userInitiated else { return }
        NSApp.dockTile.badgeLabel = "1"
        NSApp.requestUserAttention(.informationalRequest)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        NSApp.dockTile.badgeLabel = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.dockTile.badgeLabel = nil
        ActivationPolicy.release(Self.activationReason)
    }
}
