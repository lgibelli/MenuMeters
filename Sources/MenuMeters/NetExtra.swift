//
//  NetExtra.swift
//  MenuMeters
//
//  Network menu bar meter.
//
//  Copyright (c) 2002-2014 Alex Harper
//  Copyright (c) 2015-2026 The MenuMeters contributors (see the Git history)
//  Number formatting based on code contributed by Mike Fischer.
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
//  2026-10-30  Luca Gibelli: refill one menu in place, re-baseline when sampling starts, list IPv6-only addresses, drop dead app items.
//

import Cocoa

final class NetExtra: MenuExtraBase {
    private let netConfig = NetConfig()
    private let netStats = NetStats()
    private let pppControl = NetPPP.shared

    private let extraMenu: NSMenu = {
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        return menu
    }()
    private let bytesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.localizesFormat = true
        formatter.format = "###0.0"
        return formatter
    }()
    private let prettyIntFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.localizesFormat = true
        formatter.format = "#,##0"
        return formatter
    }()
    private let throughputFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

    private var txColor: NSColor = .systemGreen
    private var rxColor: NSColor = .systemRed
    private var inactiveColor: NSColor = .secondaryLabelColor
    private var upArrow = NSBezierPath()
    private var downArrow = NSBezierPath()
    private var throughputLabelWidth: CGFloat = 0

    // NetStats takes its first baseline when it is created, just above.
    private var lastSampleDate: Date? = Date()
    private var netHistoryData: [[String: NetInterfaceStats]] = []
    private var netHistoryIntervals: [TimeInterval] = []
    private var preferredInterfaceConfig: NetInterfaceConfig?
    private var updateMenuItems: [String: InterfaceUpdateItems] = [:]

    private final class InterfaceUpdateItems {
        var pppStatusItem: NSMenuItem?
        var deltaOutItem: NSMenuItem?
        var deltaInItem: NSMenuItem?
        var totalOutItem: NSMenuItem?
        var totalInItem: NSMenuItem?
        var peakItem: NSMenuItem?
        var throughInterface: String?

        var isEmpty: Bool {
            pppStatusItem == nil && deltaOutItem == nil && deltaInItem == nil
                && totalOutItem == nil && totalInItem == nil && peakItem == nil
                && throughInterface == nil
        }
    }

    override init(bundleID: String) {
        super.init(bundleID: bundleID)
        configFromPrefs(nil)
    }

    // MARK: - Preferences

    override func configFromPrefs(_ notification: Notification?) {
        let prefs = Prefs.shared
        if statusItem == nil && prefs.meterEnabled(bundleID) {
            // Sampling (re)starts below: take a fresh baseline so the first
            // sample does not span the time the meter was off.
            _ = netStats.netStats(forInterval: 0)
            lastSampleDate = Date()
        }
        configDisplay(interval: prefs.netInterval)
        setupColor()

        let txLabel = labelString("Tx:", color: txColor)
        let rxLabel = labelString("Rx:", color: rxColor)
        throughputLabelWidth = max(txLabel.size().width, rxLabel.size().width)

        var arrowOffset: CGFloat = 0
        if prefs.netDisplayMode & Net.displayGraph != 0 {
            arrowOffset = CGFloat(prefs.netGraphLength) + Net.gap
        }
        buildArrows(offset: arrowOffset, viewHeight: height())

        menuWidth = 0
        var displayCount = 0
        if prefs.netDisplayMode & Net.displayGraph != 0 {
            menuWidth += CGFloat(prefs.netGraphLength)
            displayCount += 1
        }
        if prefs.netDisplayMode & Net.displayArrows != 0 {
            menuWidth += Net.arrowWidth
            displayCount += 1
        }
        if prefs.netDisplayMode & Net.displayThroughput != 0 {
            displayCount += 1
            if prefs.netThroughputLabel {
                menuWidth += ceil(throughputLabelWidth)
            }
            let units = prefs.netThroughputBits
                ? ["b/s", "Kb/s", "Mb/s", "Gb/s"]
                : ["B/s", "KB/s", "MB/s", "GB/s"]
            var suffixMaxWidth: CGFloat = 0
            for unit in units {
                let string = NSAttributedString(string: "999.9\(L(unit))",
                                                attributes: [.font: throughputFont])
                suffixMaxWidth = max(suffixMaxWidth, string.size().width)
            }
            menuWidth += ceil(suffixMaxWidth)
        }
        if displayCount > 0 {
            menuWidth += CGFloat(displayCount - 1) * Net.gap
        }

        statusItem?.button?.image = makeImage()
    }

    override func setupColor() {
        let prefs = Prefs.shared
        txColor = colorByAdjustingForLightDark(prefs.netTransmitColor)
        rxColor = colorByAdjustingForLightDark(prefs.netReceiveColor)
        inactiveColor = colorByAdjustingForLightDark(prefs.netInactiveColor)
    }

    private func buildArrows(offset: CGFloat, viewHeight: CGFloat) {
        let width = Net.arrowWidth
        upArrow = NSBezierPath()
        upArrow.move(to: NSPoint(x: offset + width / 2 + 0.5, y: viewHeight - 3.5))
        upArrow.line(to: NSPoint(x: offset + 0.5, y: viewHeight - 7.5))
        upArrow.line(to: NSPoint(x: offset + 2.5, y: viewHeight - 7.5))
        upArrow.line(to: NSPoint(x: offset + 2.5, y: viewHeight - 10.5))
        upArrow.line(to: NSPoint(x: offset + width - 2.5, y: viewHeight - 10.5))
        upArrow.line(to: NSPoint(x: offset + width - 2.5, y: viewHeight - 7.5))
        upArrow.line(to: NSPoint(x: offset + width - 0.5, y: viewHeight - 7.5))
        upArrow.close()
        upArrow.lineWidth = 0.6

        downArrow = NSBezierPath()
        downArrow.move(to: NSPoint(x: offset + width / 2 + 0.5, y: 2.5))
        downArrow.line(to: NSPoint(x: offset + 0.5, y: 6.5))
        downArrow.line(to: NSPoint(x: offset + 2.5, y: 6.5))
        downArrow.line(to: NSPoint(x: offset + 2.5, y: 9.5))
        downArrow.line(to: NSPoint(x: offset + width - 2.5, y: 9.5))
        downArrow.line(to: NSPoint(x: offset + width - 2.5, y: 6.5))
        downArrow.line(to: NSPoint(x: offset + width - 0.5, y: 6.5))
        downArrow.close()
        downArrow.lineWidth = 0.6
    }

    private func labelString(_ key: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: L(key), attributes: [
            .font: throughputFont,
            .foregroundColor: color
        ])
    }

    // MARK: - Formatting

    private func scaleDown(_ value: inout Double, base: Int, limit: Int) -> Int {
        var exponent = 0
        if base > 1 {
            while value >= Double(base) && exponent < limit {
                value /= Double(base)
                exponent += 1
            }
        }
        return exponent
    }

    private func throughputString(bytesPerSecond bps: Double) -> String {
        throughputString(bytesPerSecond: bps, withSpace: true)
    }

    private func throughputString(bytesPerSecond bps: Double, withSpace: Bool) -> String {
        var labels = ["B/s", "KB/s", "MB/s", "GB/s"]
        var kilo = 1024
        var value = bps
        if Prefs.shared.netThroughputBits {
            labels = ["b/s", "Kb/s", "Mb/s", "Gb/s"]
            kilo = 1000
            value *= 8
        }
        if value < Double(kilo) && Prefs.shared.netThroughput1KBound {
            value = 0
        }

        let index = scaleDown(&value, base: kilo, limit: labels.count - 1)
        let format = (index == 0 || value >= 1000) ? "%.0f" : "%.1f"
        let number = String(format: format, value)
        return number + (withSpace ? " " : "") + L(labels[index])
    }

    private func throughputString(bytes: Double, interval: TimeInterval) -> String {
        guard interval > 0 else { return throughputString(bytesPerSecond: 0, withSpace: true) }
        return throughputString(bytesPerSecond: bytes / interval, withSpace: true)
    }

    private func menubarThroughputString(bytes: Double, interval: TimeInterval) -> String {
        guard interval > 0 else { return throughputString(bytesPerSecond: 0, withSpace: false) }
        return throughputString(bytesPerSecond: bytes / interval, withSpace: false)
    }

    private func trafficString(number: Double, label: String) -> String {
        var labels = ["B", "KB", "MB", "GB", "TB"]
        var kilo = 1024
        var value = number
        if Prefs.shared.netThroughputBits {
            labels = ["b", "Kb", "Mb", "Gb", "Tb"]
            kilo = 1000
            value *= 8
        }

        let index = scaleDown(&value, base: kilo, limit: labels.count - 1)
        let format = index == 0 ? "%.0f %@" : "%.1f %@"
        let scaled = String(format: format, value, L(labels[index]))
        let unscaled = throughputString(bytes: number)
        return "\(label) \(scaled) (\(unscaled))"
    }

    private func throughputString(bytes: Double) -> String {
        var value = bytes
        var unit = "bytes"
        if Prefs.shared.netThroughputBits {
            value *= 8
            unit = "bits"
        }
        let pretty = prettyIntFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        return "\(pretty) \(L(unit))"
    }
    // MARK: - Menu

    override func menu() -> NSMenu {
        buildMenu()
        return extraMenu
    }

    private func buildMenu() {
        preferredInterfaceConfig = netConfig.interfaceConfig(for: Prefs.shared.netPreferInterface)
        updateMenuItems = [:]

        // AppKit keeps displaying the menu it already has, so refill that one.
        let menu = extraMenu
        menu.removeAllItems()

        if let hostname = netConfig.computerName() {
            addDisabled(hostname, to: menu)
            menu.addItem(.separator())
        }

        let detailsList = netConfig.interfaceDetails()
        if detailsList.isEmpty {
            addDisabled(L("No Active Interfaces"), to: menu)
        } else {
            for details in detailsList {
                appendInterface(details, to: menu)
            }
        }

        menu.addItem(.separator())
        let prefsItem = menu.addItem(withTitle: L("Open Network Preferences"),
                                     action: #selector(openNetworkPrefs(_:)), keyEquivalent: "")
        prefsItem.target = self
        addStandardMenuEntries(to: menu)
    }

    @discardableResult
    private func addDisabled(_ title: String, indent: Int = 0, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.indentationLevel = indent
        return item
    }

    private func appendInterface(_ details: NetInterfaceDetails, to menu: NSMenu) {
        let prefs = Prefs.shared
        let updateInfo = InterfaceUpdateItems()

        var isActiveInterface = details.linkActive ?? true
        if let ppp = details.pppStatus, ppp.status == NetPPP.idle {
            isActiveInterface = false
        }

        // Link speed is only shown when we believe the interface is active.
        var speed: String?
        if let linkSpeed = details.linkSpeed, isActiveInterface {
            if linkSpeed < 0 {
                speed = nil
            } else if linkSpeed > 1_000_000_000 {
                speed = String(format: " %.0f %@", linkSpeed / 1_000_000_000, L("Gbps"))
            } else if linkSpeed > 1_000_000 {
                speed = String(format: " %.0f %@", linkSpeed / 1_000_000, L("Mbps"))
            } else {
                let number = bytesFormatter.string(from: NSNumber(value: linkSpeed / 1000))
                    ?? String(format: "%.1f", linkSpeed / 1000)
                speed = " \(number) \(L("Kbps"))"
            }
        }

        var description = details.name
        if let device = details.deviceName, !description.hasSuffix("(\(device))") {
            if let pppName = details.pppDeviceName {
                description += " (\(device), \(pppName))"
            } else {
                description += " (\(device))"
            }
        }
        if speed != nil || details.connectionType != nil {
            description += " -"
            if let connectionType = details.connectionType {
                description += " \(connectionType)"
            }
            if let speed {
                description += speed
            }
        }
        let titleItem = menu.addItem(withTitle: description, action: nil, keyEquivalent: "")

        // PPP status
        if let ppp = details.pppStatus {
            let label = details.connectionType.map { "\($0):" } ?? L("PPP:")
            addDisabled(label, indent: 1, to: menu)

            let statusItem: NSMenuItem
            switch ppp.status {
            case NetPPP.idle:
                statusItem = addDisabled(L("Not Connected"), indent: 2, to: menu)
            case NetPPP.running:
                if let elapsed = ppp.timeElapsed {
                    let hours = elapsed / 3600
                    var remainder = elapsed % 3600
                    let minutes = remainder / 60
                    remainder %= 60
                    statusItem = addDisabled(String(format: L("Connected %02d:%02d:%02d"),
                                                    hours, minutes, remainder),
                                             indent: 2, to: menu)
                } else {
                    statusItem = addDisabled(L("Connected"), indent: 2, to: menu)
                }
            case NetPPP.terminate, NetPPP.disconnectLink:
                statusItem = addDisabled(L("Disconnecting..."), indent: 1, to: menu)
            default:
                statusItem = addDisabled(L("Connecting..."), indent: 2, to: menu)
            }
            updateInfo.pppStatusItem = statusItem
        }

        // TCP/IP
        var tcpStart = menu.numberOfItems
        if !details.ipv4Addresses.isEmpty && !details.ipv6Addresses.isEmpty {
            addDisabled(L("IPv4:"), indent: 2, to: menu)
            for address in details.ipv4Addresses {
                addDisabled(address, indent: 3, to: menu)
            }
            addDisabled(L("IPv6:"), indent: 2, to: menu)
            for address in details.ipv6Addresses {
                addDisabled(address, indent: 3, to: menu)
            }
        } else if !details.ipv4Addresses.isEmpty || !details.ipv6Addresses.isEmpty {
            for address in details.ipv4Addresses + details.ipv6Addresses {
                addDisabled(address, indent: 2, to: menu)
            }
        } else {
            addDisabled(L("Inactive"), indent: 2, to: menu)
            tcpStart = -1
        }
        if tcpStart > 0 {
            let item = menu.insertItem(withTitle: L("TCP/IP:"), action: nil,
                                       keyEquivalent: "", at: tcpStart)
            item.isEnabled = false
            item.indentationLevel = 1
        }

        // AppleTalk
        if let netID = details.appleTalkNetID {
            addDisabled(L("AppleTalk:"), indent: 1, to: menu)
            let text = String(format: L("Net: %@ Node: %@ Zone: %@"),
                              netID,
                              details.appleTalkNodeID ?? "",
                              details.appleTalkZone ?? "")
            addDisabled(text, indent: 1, to: menu)
        }

        // Throughput
        let sampleInterval = netHistoryIntervals.last
        var throughputInterface = details.deviceName
        if let pppName = details.pppDeviceName,
           !(details.deviceName ?? "").hasPrefix("en") {
            throughputInterface = pppName
        }
        let throughputDetails = throughputInterface.flatMap { netHistoryData.last?[$0] }

        if isActiveInterface, let sampleInterval,
           throughputInterface != nil, let stats = throughputDetails {
            addDisabled(L("Throughput:"), indent: 1, to: menu)
            let txItem = addDisabled("\(L("Tx:")) \(throughputString(bytes: Double(stats.deltaOut), interval: sampleInterval))",
                                     indent: 2, to: menu)
            updateInfo.deltaOutItem = txItem
            let rxItem = addDisabled("\(L("Rx:")) \(throughputString(bytes: Double(stats.deltaIn), interval: sampleInterval))",
                                     indent: 2, to: menu)
            updateInfo.deltaInItem = rxItem

            addDisabled(L("Peak Throughput:"), indent: 1, to: menu)
            let peakItem = addDisabled(throughputString(bytesPerSecond: stats.peak, withSpace: true),
                                       indent: 2, to: menu)
            updateInfo.peakItem = peakItem

            addDisabled(L("Traffic Totals:"), indent: 1, to: menu)
            let totalOutItem = addDisabled(trafficString(number: Double(stats.totalOut), label: L("Tx:")),
                                           indent: 2, to: menu)
            updateInfo.totalOutItem = totalOutItem
            let totalInItem = addDisabled(trafficString(number: Double(stats.totalIn), label: L("Rx:")),
                                          indent: 2, to: menu)
            updateInfo.totalInItem = totalInItem

            updateInfo.throughInterface = throughputInterface
        }

        if !updateInfo.isEmpty {
            updateMenuItems[details.serviceID] = updateInfo
        }

        // Per-interface submenu
        let submenu = NSMenu(title: "")
        submenu.autoenablesItems = false
        titleItem.submenu = submenu

        if let ppp = details.pppStatus {
            let canConnect = ppp.status == NetPPP.idle
                || ppp.status == NetPPP.terminate
                || ppp.status == NetPPP.disconnectLink
            let control = submenu.addItem(withTitle: canConnect ? L("Connect") : L("Disconnect"),
                                          action: canConnect ? #selector(pppConnect(_:))
                                                             : #selector(pppDisconnect(_:)),
                                          keyEquivalent: "")
            control.target = self
            control.representedObject = details.serviceID
            submenu.addItem(.separator())
        }

        var hadInterfaceSelector = false
        if details.isPrimary {
            let item = submenu.addItem(withTitle: L("Display primary interface"),
                                       action: #selector(switchDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MM.primaryInterface
            item.isEnabled = prefs.netPreferInterface != MM.primaryInterface
            hadInterfaceSelector = true
        }
        if let device = details.deviceName {
            let item = submenu.addItem(withTitle: L("Display this interface"),
                                       action: #selector(switchDisplay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device
            item.isEnabled = device != prefs.netPreferInterface
            hadInterfaceSelector = true
        }
        if hadInterfaceSelector {
            submenu.addItem(.separator())
        }

        if prefs.netPreferInterface == MM.primaryInterface && details.isPrimary {
            titleItem.state = .on
        } else if let config = preferredInterfaceConfig {
            let names = [details.deviceName, details.pppDeviceName].compactMap { $0 }
            if names.contains(config.name) || names.contains(config.statName) {
                titleItem.state = .on
            }
        }

        let copy4 = submenu.addItem(withTitle: L("Copy IPv4 address"),
                                    action: #selector(copyAddress(_:)), keyEquivalent: "")
        copy4.target = self
        copy4.representedObject = details.ipv4Addresses
        copy4.isEnabled = !details.ipv4Addresses.isEmpty
        if !details.ipv6Addresses.isEmpty {
            let copy6 = submenu.addItem(withTitle: L("Copy IPv6 address"),
                                        action: #selector(copyAddress(_:)), keyEquivalent: "")
            copy6.target = self
            copy6.representedObject = details.ipv6Addresses
        }
        if let throughputInterface {
            let reset = submenu.addItem(withTitle: L("Reset traffic totals"),
                                        action: #selector(resetTotals(_:)), keyEquivalent: "")
            reset.target = self
            reset.representedObject = throughputInterface
        }
    }

    // MARK: - Menu actions

    @objc private func openNetworkPrefs(_ sender: Any?) {
        let legacyURL = URL(fileURLWithPath: "/System/Library/PreferencePanes/Network.prefPane")
        if FileManager.default.fileExists(atPath: legacyURL.path),
           NSWorkspace.shared.open(legacyURL) {
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        NSLog("MenuMeterNet unable to launch the Network Preferences.")
    }

    @objc private func resetTotals(_ sender: Any?) {
        guard let interfaceName = (sender as? NSMenuItem)?.representedObject as? String else { return }
        netStats.resetTotals(forInterface: interfaceName)
    }

    @objc private func switchDisplay(_ sender: Any?) {
        guard let interfaceName = (sender as? NSMenuItem)?.representedObject as? String,
              let config = netConfig.interfaceConfig(for: interfaceName) else { return }
        preferredInterfaceConfig = config
        Prefs.shared.netPreferInterface = interfaceName
        statusItem?.button?.image = makeImage()
        NotificationCenter.default.post(name: Notification.Name(MM.prefsBundleID),
                                        object: MM.prefChange)
    }

    @objc private func copyAddress(_ sender: Any?) {
        guard let addresses = (sender as? NSMenuItem)?.representedObject as? [String],
              !addresses.isEmpty else {
            NSLog("MenuMeterNet unable to copy IP addresses to clipboard.")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(addresses.joined(separator: ", "), forType: .string)
    }

    @objc private func pppConnect(_ sender: Any?) {
        guard let serviceID = (sender as? NSMenuItem)?.representedObject as? String else { return }
        pppControl.connect(serviceID: serviceID)
    }

    @objc private func pppDisconnect(_ sender: Any?) {
        guard let serviceID = (sender as? NSMenuItem)?.representedObject as? String else { return }
        pppControl.disconnect(serviceID: serviceID)
    }

    // MARK: - Timer

    override func timerFired(_ timer: Timer) {
        let prefs = Prefs.shared
        preferredInterfaceConfig = netConfig.interfaceConfig(for: prefs.netPreferInterface)

        var currentSampleInterval = prefs.netInterval
        if let lastSampleDate {
            currentSampleInterval = -lastSampleDate.timeIntervalSinceNow
        }

        if let netLoad = netStats.netStats(forInterval: currentSampleInterval) {
            if prefs.netDisplayMode & Net.displayGraph != 0 {
                let length = prefs.netGraphLength
                if netHistoryData.count >= length {
                    netHistoryData.removeFirst(netHistoryData.count - length + 1)
                }
                if netHistoryIntervals.count >= length {
                    netHistoryIntervals.removeFirst(netHistoryIntervals.count - length + 1)
                }
            } else {
                netHistoryData.removeAll()
                netHistoryIntervals.removeAll()
            }
            netHistoryData.append(netLoad)
            netHistoryIntervals.append(currentSampleInterval)
            lastSampleDate = Date()
        }

        if isMenuVisible {
            updateMenuWhenDown()
        }
        super.timerFired(timer)
    }

    private func pppStatusTitle(_ status: PPPStatusResult) -> String {
        switch status.status {
        case NetPPP.idle:
            return L("Not Connected")
        case NetPPP.running:
            if let elapsed = status.timeElapsed {
                let hours = elapsed / 3600
                var remainder = elapsed % 3600
                let minutes = remainder / 60
                remainder %= 60
                return String(format: L("Connected %02d:%02d:%02d"), hours, minutes, remainder)
            }
            return L("Connected")
        case NetPPP.terminate, NetPPP.disconnectLink:
            return L("Disconnecting...")
        default:
            return L("Connecting...")
        }
    }

    private func updateMenuWhenDown() {
        let detailsList = netConfig.interfaceDetails()
        guard !detailsList.isEmpty else { return }

        for details in detailsList {
            guard let updateInfo = updateMenuItems[details.serviceID] else { continue }

            if let item = updateInfo.pppStatusItem, let ppp = details.pppStatus {
                item.title = pppStatusTitle(ppp)
            }

            guard let interfaceName = updateInfo.throughInterface,
                  let stats = netHistoryData.last?[interfaceName],
                  let interval = netHistoryIntervals.last else { continue }

            updateInfo.deltaOutItem?.title =
                "\(L("Tx:")) \(throughputString(bytes: Double(stats.deltaOut), interval: interval))"
            updateInfo.deltaInItem?.title =
                "\(L("Rx:")) \(throughputString(bytes: Double(stats.deltaIn), interval: interval))"
            updateInfo.totalOutItem?.title =
                trafficString(number: Double(stats.totalOut), label: L("Tx:"))
            updateInfo.totalInItem?.title =
                trafficString(number: Double(stats.totalIn), label: L("Rx:"))
            updateInfo.peakItem?.title = throughputString(bytesPerSecond: stats.peak)
        }
        forceMenuRedraw(extraMenu)
    }

    // MARK: - Rendering

    override func renderImage() -> Bool {
        guard !netHistoryData.isEmpty else { return false }
        let mode = Prefs.shared.netDisplayMode
        if mode & Net.displayGraph != 0 { renderGraph() }
        if mode & Net.displayArrows != 0 { renderActivity() }
        if mode & Net.displayThroughput != 0 { renderThroughput() }
        return true
    }

    private func scaleFactor() -> Double {
        var factor = 0.0
        switch Prefs.shared.netScaleMode {
        case Net.scaleInterfaceSpeed:
            if let config = preferredInterfaceConfig {
                factor = config.speed / 8
            }
        case Net.scalePeakTraffic:
            if let config = preferredInterfaceConfig,
               let first = netHistoryData.first,
               let stats = first[config.statName] {
                factor = stats.peak
            }
        default:
            break
        }
        if factor > 0 {
            switch Prefs.shared.netScaleCalc {
            case Net.scaleSquareRoot:
                factor = sqrt(factor)
            case Net.scaleCubeRoot:
                factor = cbrt(factor)
            case Net.scaleLog:
                factor = log(factor)
            default:
                break
            }
        }
        return factor
    }

    private func scaledValue(_ value: Double, factor: Double) -> Double {
        let scaled: Double
        switch Prefs.shared.netScaleCalc {
        case Net.scaleSquareRoot:
            scaled = sqrt(value)
        case Net.scaleCubeRoot:
            scaled = cbrt(value)
        case Net.scaleLog:
            scaled = log(value)
        default:
            scaled = value
        }
        return scaled / factor
    }

    private func renderGraph() {
        guard let config = preferredInterfaceConfig else { return }
        let prefs = Prefs.shared
        let style = prefs.netGraphStyle
        let rxOnTop = prefs.netDisplayOrientation == Net.orientRxTx
        let viewHeight = imageHeight()
        let graphHeight = floor((viewHeight - 1) / 2)

        let topPath = NSBezierPath()
        let bottomPath = NSBezierPath()
        if style == Net.graphOpposed || style == Net.graphInverseOpposed {
            bottomPath.move(to: NSPoint(x: 0, y: 0))
            bottomPath.line(to: NSPoint(x: 0, y: 0.5))
            topPath.move(to: NSPoint(x: 0, y: viewHeight))
            topPath.line(to: NSPoint(x: 0, y: viewHeight - 0.5))
        } else if style == Net.graphCentered {
            topPath.move(to: NSPoint(x: 0, y: graphHeight + 1))
            topPath.line(to: NSPoint(x: 0, y: graphHeight + 1.5))
            bottomPath.move(to: NSPoint(x: 0, y: graphHeight))
            bottomPath.line(to: NSPoint(x: 0, y: graphHeight - 0.5))
        } else {
            topPath.move(to: NSPoint(x: 0, y: graphHeight + 1))
            topPath.line(to: NSPoint(x: 0, y: graphHeight + 1.5))
            bottomPath.move(to: NSPoint(x: 0, y: 0))
            bottomPath.line(to: NSPoint(x: 0, y: 0.5))
        }

        let factor = scaleFactor()
        let renderHeight = graphHeight - 0.5
        var renderPosition = 0

        while renderPosition < prefs.netGraphLength {
            guard renderPosition < netHistoryData.count,
                  renderPosition < netHistoryIntervals.count else { break }
            let entry = netHistoryData[renderPosition]
            let interval = netHistoryIntervals[renderPosition]
            renderPosition += 1
            guard factor > 0, interval > 0, let stats = entry[config.statName] else { continue }

            var txValue = scaledValue(Double(stats.deltaOut) / interval, factor: factor)
            var rxValue = scaledValue(Double(stats.deltaIn) / interval, factor: factor)
            txValue = min(1, max(0, txValue))
            rxValue = min(1, max(0, rxValue))

            let x = CGFloat(renderPosition - 1)
            if style == Net.graphInverseOpposed {
                if rxOnTop {
                    topPath.line(to: NSPoint(x: x, y: viewHeight - (rxValue * renderHeight) - 0.5))
                    bottomPath.line(to: NSPoint(x: x, y: (txValue * renderHeight) + 0.5))
                } else {
                    topPath.line(to: NSPoint(x: x, y: viewHeight - (txValue * renderHeight) - 0.5))
                    bottomPath.line(to: NSPoint(x: x, y: (rxValue * renderHeight) + 0.5))
                }
            } else if style == Net.graphOpposed {
                if rxOnTop {
                    topPath.line(to: NSPoint(x: x, y: viewHeight - (txValue * renderHeight) - 0.5))
                    bottomPath.line(to: NSPoint(x: x, y: (rxValue * renderHeight) + 0.5))
                } else {
                    topPath.line(to: NSPoint(x: x, y: viewHeight - (rxValue * renderHeight) - 0.5))
                    bottomPath.line(to: NSPoint(x: x, y: (txValue * renderHeight) + 0.5))
                }
            } else if style == Net.graphCentered {
                if rxOnTop {
                    topPath.line(to: NSPoint(x: x, y: (rxValue * renderHeight) + graphHeight + 1.5))
                    bottomPath.line(to: NSPoint(x: x, y: graphHeight - (txValue * renderHeight) - 0.5))
                } else {
                    topPath.line(to: NSPoint(x: x, y: (txValue * renderHeight) + graphHeight + 1.5))
                    bottomPath.line(to: NSPoint(x: x, y: graphHeight - (rxValue * renderHeight) - 0.5))
                }
            } else {
                if rxOnTop {
                    topPath.line(to: NSPoint(x: x, y: (rxValue * renderHeight) + graphHeight + 1.5))
                    bottomPath.line(to: NSPoint(x: x, y: (txValue * renderHeight) + 0.5))
                } else {
                    topPath.line(to: NSPoint(x: x, y: (txValue * renderHeight) + graphHeight + 1.5))
                    bottomPath.line(to: NSPoint(x: x, y: (rxValue * renderHeight) + 0.5))
                }
            }
        }

        let endX = CGFloat(max(0, renderPosition - 1))
        if style == Net.graphOpposed || style == Net.graphInverseOpposed {
            topPath.line(to: NSPoint(x: endX, y: viewHeight - 0.5))
            topPath.line(to: NSPoint(x: endX, y: viewHeight))
            bottomPath.line(to: NSPoint(x: endX, y: 0.5))
            bottomPath.line(to: NSPoint(x: endX, y: 0))
        } else if style == Net.graphCentered {
            topPath.line(to: NSPoint(x: endX, y: graphHeight + 1.5))
            topPath.line(to: NSPoint(x: endX, y: graphHeight + 1))
            bottomPath.line(to: NSPoint(x: endX, y: graphHeight - 0.5))
            bottomPath.line(to: NSPoint(x: endX, y: graphHeight))
        } else {
            topPath.line(to: NSPoint(x: endX, y: graphHeight + 1.5))
            topPath.line(to: NSPoint(x: endX, y: graphHeight + 1))
            bottomPath.line(to: NSPoint(x: endX, y: 0.5))
            bottomPath.line(to: NSPoint(x: endX, y: 0))
        }

        if !config.isUp {
            inactiveColor.setFill()
            topPath.fill()
            bottomPath.fill()
        } else if rxOnTop {
            rxColor.setFill()
            topPath.fill()
            txColor.setFill()
            bottomPath.fill()
        } else {
            rxColor.setFill()
            bottomPath.fill()
            txColor.setFill()
            topPath.fill()
        }
    }

    private func renderActivity() {
        guard let config = preferredInterfaceConfig else { return }
        let factor = scaleFactor()
        var txValue = 0.0
        var rxValue = 0.0

        if let stats = netHistoryData.last?[config.statName],
           let interval = netHistoryIntervals.last,
           interval > 0, factor > 0 {
            txValue = scaledValue(Double(stats.deltaOut) / interval, factor: factor)
            rxValue = scaledValue(Double(stats.deltaIn) / interval, factor: factor)
        }
        txValue = min(1, max(0, txValue))
        rxValue = min(1, max(0, rxValue))

        if config.isUp {
            if Prefs.shared.netDisplayOrientation == Net.orientRxTx {
                rxColor.withAlphaComponent(rxValue).setFill()
                upArrow.fill()
                rxColor.setStroke()
                upArrow.stroke()
                txColor.withAlphaComponent(txValue).setFill()
                downArrow.fill()
                txColor.setStroke()
                downArrow.stroke()
            } else {
                txColor.withAlphaComponent(txValue).setFill()
                upArrow.fill()
                txColor.setStroke()
                upArrow.stroke()
                rxColor.withAlphaComponent(rxValue).setFill()
                downArrow.fill()
                rxColor.setStroke()
                downArrow.stroke()
            }
        } else {
            inactiveColor.setStroke()
            upArrow.stroke()
            downArrow.stroke()
        }
    }

    private func renderThroughput() {
        let config = preferredInterfaceConfig
        let interfaceUp = config?.isUp == true
        var txValue = 0.0
        var rxValue = 0.0
        if interfaceUp, let config, let stats = netHistoryData.last?[config.statName] {
            txValue = Double(stats.deltaOut)
            rxValue = Double(stats.deltaIn)
        }
        txValue = max(0, txValue)
        rxValue = max(0, rxValue)

        var sampleInterval = Prefs.shared.netInterval
        if let interval = netHistoryIntervals.last, interval > 0 {
            sampleInterval = interval
        }

        let txString = menubarThroughputString(bytes: txValue, interval: sampleInterval)
        let rxString = menubarThroughputString(bytes: rxValue, interval: sampleInterval)
        let txText = NSAttributedString(string: txString, attributes: [
            .font: throughputFont,
            .foregroundColor: interfaceUp ? txColor : inactiveColor
        ])
        let rxText = NSAttributedString(string: rxString, attributes: [
            .font: throughputFont,
            .foregroundColor: interfaceUp ? rxColor : inactiveColor
        ])

        let prefs = Prefs.shared
        if prefs.netThroughputLabel {
            var labelOffset: CGFloat = 0
            if prefs.netDisplayMode & Net.displayGraph != 0 {
                labelOffset += CGFloat(prefs.netGraphLength) + Net.gap
            }
            if prefs.netDisplayMode & Net.displayArrows != 0 {
                labelOffset += Net.arrowWidth + Net.gap
            }
            let txLabel = labelString("Tx:", color: interfaceUp ? txColor : inactiveColor)
            let rxLabel = labelString("Rx:", color: interfaceUp ? rxColor : inactiveColor)
            if prefs.netDisplayOrientation == Net.orientRxTx {
                rxLabel.draw(at: NSPoint(x: labelOffset, y: floor(imageHeight() / 2) - 2))
                txLabel.draw(at: NSPoint(x: labelOffset, y: -1))
            } else {
                txLabel.draw(at: NSPoint(x: labelOffset, y: floor(imageHeight() / 2) - 2))
                rxLabel.draw(at: NSPoint(x: labelOffset, y: -1))
            }
        }

        if prefs.netDisplayOrientation == Net.orientRxTx {
            rxText.draw(at: NSPoint(x: ceil(menuWidth - rxText.size().width),
                                    y: floor(imageHeight() / 2) - 1))
            txText.draw(at: NSPoint(x: ceil(menuWidth - txText.size().width), y: -1))
        } else {
            txText.draw(at: NSPoint(x: ceil(menuWidth - txText.size().width),
                                    y: floor(imageHeight() / 2) - 1))
            rxText.draw(at: NSPoint(x: ceil(menuWidth - rxText.size().width), y: -1))
        }
    }
}
