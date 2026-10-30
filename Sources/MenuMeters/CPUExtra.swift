//
//  CPUExtra.swift
//  MenuMeters
//
//  CPU menu bar meter.
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
//  2026-10-30  Luca Gibelli: live process rows, horizontal thermometer layout, PowerMate teardown.
//

import Cocoa

final class CPUExtra: MenuExtraBase {
    private let cpuInfo = CPUStats()
    private let topProcesses = CPUTopProcesses()
    private var extraMenu = NSMenu()
    private var loadHistory: [[CPULoadSample]] = []
    private var percentWidth: CGFloat = 0
    private var temperatureDisplayWidth: CGFloat = 0
    private var fgMenuThemeColor: NSColor = .labelColor
    private var userColor: NSColor = .systemBlue
    private var systemColor: NSColor = .systemRed
    private var temperatureColor: NSColor = .systemRed
    private var powerMate: PowerMate?
    private static var defaultProcessIcon: NSImage?

    override init(bundleID: String) {
        super.init(bundleID: bundleID)
        buildMenu()
        topProcesses.onUpdate = { [weak self] in self?.updateMenuWhenDown() }
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)),
                                               name: NSApplication.willTerminateNotification, object: nil)
        configFromPrefs(nil)
    }

    // MARK: - Menu

    private func buildMenu() {
        extraMenu = NSMenu(title: "")
        extraMenu.autoenablesItems = false

        addDisabled(cpuInfo.numberOfCPUs == 1 ? L("Processor:") : L("Processors:"))
        addDisabled(cpuInfo.processorDescription, indent: 1)
        addDisabled(cpuInfo.coreDescription, indent: 1)
        addDisabled(L("Uptime:"))
        addDisabled("", indent: 1)
        addDisabled(L("Tasks/Threads:"))
        addDisabled("", indent: 1)
        addDisabled(L("Load Average (1m, 5m, 15m):"))
        addDisabled("", indent: 1)
#if arch(x86_64)
        addDisabled(L("CPU power limit:"))
        addDisabled("", indent: 1)
#endif
        addDisabled(L("Top CPU Intensive Processes:"))
        for _ in 0..<MM.meterCountMax {
            addDisabled("", indent: 1)
        }

        extraMenu.addItem(.separator())
        let console = extraMenu.addItem(withTitle: L("Open Console"),
                                        action: #selector(openConsole(_:)), keyEquivalent: "")
        console.target = self
        addStandardMenuEntries(to: extraMenu)
    }

    @discardableResult
    private func addDisabled(_ title: String, indent: Int = 0) -> NSMenuItem {
        let item = extraMenu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.indentationLevel = indent
        return item
    }

    override func menu() -> NSMenu {
        liveUpdateMenuItemTitle(extraMenu, CPU.uptimeMenuIndex, Uptime.string())
        liveUpdateMenuItemTitle(extraMenu, CPU.taskInfoMenuIndex, cpuInfo.currentProcessorTasks())
        liveUpdateMenuItemTitle(extraMenu, CPU.loadInfoMenuIndex, cpuInfo.loadAverage())
#if arch(x86_64)
        if let power = cpuInfo.cpuPowerLimitStatus() {
            liveUpdateMenuItemTitle(extraMenu, CPU.powerLimitInfoMenuIndex, power)
        }
#endif

        let maximum = Prefs.shared.cpuMaxProcessCount
        let processes = maximum > 0 ? topProcesses.runningProcesses(byCPUUsage: maximum) : []
        liveUpdateMenuItemTitleAndVisibility(extraMenu, CPU.processLabelMenuIndex, nil, hidden: processes.isEmpty)

        for index in 0..<MM.meterCountMax {
            let menuIndex = CPU.processMenuIndex + index
            guard menuIndex < extraMenu.numberOfItems else { break }
            guard index < processes.count else {
                liveUpdateMenuItemTitleAndVisibility(extraMenu, menuIndex, nil, hidden: true)
                continue
            }
            let process = processes[index]
            let title = String(format: "%@ (%.1f%%)", process.name, process.cpuPercent)
            let item = extraMenu.item(at: menuIndex)!
            item.title = title
            item.isHidden = title.isEmpty

            let icon: NSImage
            if let application = NSRunningApplication(processIdentifier: process.pid), let appIcon = application.icon {
                icon = appIcon
            } else {
                if Self.defaultProcessIcon == nil {
                    Self.defaultProcessIcon = NSWorkspace.shared.icon(forFile: "/bin/bash")
                }
                icon = Self.defaultProcessIcon!
            }
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        return extraMenu
    }

    override func menuWillOpen(_ menu: NSMenu) {
        if Prefs.shared.cpuMaxProcessCount > 0 {
            // AppKit has already built the rows from the previous snapshot;
            // the new one replaces them in place when it arrives.
            topProcesses.startUpdateProcessList()
        }
        super.menuWillOpen(menu)
    }

    override func menuDidClose(_ menu: NSMenu) {
        topProcesses.stopUpdateProcessList()
        super.menuDidClose(menu)
    }

    /// Live-updates the items of the open menu.
    private func updateMenuWhenDown() {
        guard isMenuVisible else { return }
        _ = menu()
        forceMenuRedraw(extraMenu)
    }

    @objc private func openConsole(_ sender: Any?) {
        AppLauncher.open(bundleID: "com.apple.Console",
                         path: "/System/Applications/Utilities/Console.app",
                         name: "Console")
    }

    // MARK: - Preferences

    override func configFromPrefs(_ notification: Notification?) {
        configDisplay(interval: Prefs.shared.cpuInterval)
        setupColor()

        let prefs = Prefs.shared
        let displayCount = prefs.cpuAvgLowerHalfProcs ? cpuInfo.numberOfCores : cpuInfo.numberOfCPUs

        if prefs.cpuDisplayMode & CPU.displayPercent != 0 {
            let load = prefs.cpuSumAllProcsPercent ? Double(cpuInfo.numberOfCPUs) : 1
            percentWidth = ceil(percentString(load: load, color: fgMenuThemeColor).size().width)
                + CPU.percentBorderWidth
        }

        menuWidth = 0
        if prefs.cpuDisplayMode & CPU.displayHorizontalThermometer != 0 {
            menuWidth = CGFloat(prefs.cpuMenuWidth)
        } else {
            let copies: CGFloat = prefs.cpuAvgAllProcs ? 1 : CGFloat(displayCount)
            if prefs.cpuDisplayMode & CPU.displayPercent != 0 {
                menuWidth += copies * percentWidth
            }
            if prefs.cpuDisplayMode & CPU.displayGraph != 0 {
                menuWidth += copies * CGFloat(prefs.cpuGraphLength)
            }
            if prefs.cpuDisplayMode & CPU.displayThermometer != 0 {
                menuWidth += copies * CPU.thermometerWidth
            }
            if !prefs.cpuAvgAllProcs && displayCount > 1 {
                menuWidth += CGFloat(displayCount - 1) * CPU.multiProcGap
            }
        }

        if prefs.cpuShowTemperature {
            temperatureDisplayWidth = 1 + temperatureString("66.6℃").size().width
            menuWidth += temperatureDisplayWidth
        }
        if !prefs.cpuShowTemperature && prefs.cpuDisplayMode == 0 {
            menuWidth = CPU.labelOnlyWidth
        }

        configurePowerMate()
        statusItem?.button?.image = makeImage()
    }

    private func configurePowerMate() {
        let prefs = Prefs.shared
        // The meter's timer drives the LED, so hold the device only while the
        // meter runs. Releasing it turns the LED off.
        guard prefs.cpuPowerMate, statusItem != nil else {
            powerMate = nil
            return
        }
        if powerMate == nil {
            powerMate = PowerMate()
        }
        guard let powerMate else {
            NSLog("MenuMeters: unable to load PowerMate support")
            return
        }
        switch prefs.cpuPowerMateMode {
        case 0: // glow
            powerMate.stopPulse()
            powerMate.setGlow(0)
        case 2: // inverse glow
            powerMate.stopPulse()
            powerMate.setGlow(1)
        case 1: // pulse
            powerMate.setGlow(1)
            powerMate.setPulse(0)
        default: // inverse pulse
            powerMate.setGlow(1)
            powerMate.setPulse(1)
        }
    }

    override func removeStatusItem() {
        super.removeStatusItem()
        // Also reached when the user drags the meter out of the menu bar,
        // which does not go through configFromPrefs.
        powerMate = nil
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        // Nothing is deallocated at exit; release the PowerMate so its LED
        // does not keep glowing or pulsing after we quit.
        powerMate = nil
    }

    override func setupColor() {
        fgMenuThemeColor = menuBarTextColor()
        let prefs = Prefs.shared
        userColor = colorByAdjustingForLightDark(prefs.cpuUserColor)
        systemColor = colorByAdjustingForLightDark(prefs.cpuSystemColor)
        temperatureColor = colorByAdjustingForLightDark(prefs.cpuTemperatureColor)
    }

    override var baselineOffset: CGFloat {
        switch Prefs.shared.cpuPercentDisplay {
        case CPU.percentSmall: return 0.5
        case CPU.percentSplit: return 0
        default: return 1
        }
    }

    private var fontSize: CGFloat {
        switch Prefs.shared.cpuPercentDisplay {
        case CPU.percentSmall: return 11
        case CPU.percentSplit: return 9.5
        default: return 14
        }
    }

    // MARK: - Timer

    override func timerFired(_ timer: Timer) {
        let current = cpuInfo.currentLoad(sorted: Prefs.shared.cpuSortByUsage)
        guard !current.isEmpty else { return }

        let prefs = Prefs.shared
        if prefs.cpuDisplayMode & CPU.displayGraph != 0 {
            if loadHistory.count >= prefs.cpuGraphLength {
                loadHistory.removeFirst(loadHistory.count - prefs.cpuGraphLength + 1)
            }
        } else {
            loadHistory.removeAll()
        }
        loadHistory.append(current)

        if isMenuVisible {
            updateMenuWhenDown()
            // Keep the process list live while the menu is open.
            if prefs.cpuMaxProcessCount > 0 {
                topProcesses.startUpdateProcessList()
            }
        }
        if prefs.cpuPowerMate, let powerMate {
            updatePowerMate(powerMate)
        }
        super.timerFired(timer)
    }

    private func updatePowerMate(_ powerMate: PowerMate) {
        guard let current = loadHistory.last, current.count >= Int(cpuInfo.numberOfCPUs) else { return }
        var total = 0.0
        for index in 0..<Int(cpuInfo.numberOfCPUs) {
            total += current[index].system + current[index].user
        }
        total = min(1, max(0, total / Double(cpuInfo.numberOfCPUs)))

        let prefs = Prefs.shared
        switch prefs.cpuPowerMateMode {
        case 0:
            powerMate.setGlow(total, rampInterval: prefs.cpuInterval / 2)
        case 1:
            powerMate.setPulse(total)
        case 2:
            powerMate.setGlow(1 - total, rampInterval: prefs.cpuInterval / 2)
        default:
            powerMate.setPulse(1 - total)
        }
    }

    // MARK: - Rendering

    override func renderImage() -> Bool {
        guard !loadHistory.isEmpty else { return false }

        let prefs = Prefs.shared
        let cpuCount = cpuInfo.numberOfCPUs
        let stride = prefs.cpuAvgLowerHalfProcs ? max(1, cpuInfo.numberOfCPUs / cpuInfo.numberOfCores) : 1
        var renderOffset: CGFloat = 0

        if !prefs.cpuShowTemperature && prefs.cpuDisplayMode == 0 {
            let string = NSAttributedString(string: "CPU", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                .foregroundColor: fgMenuThemeColor
            ])
            string.draw(at: NSPoint(x: CPU.labelOnlyWidth - ceil(string.size().width) - 1,
                                    y: (imageHeight() - string.size().height) / 2 + baselineOffset))
            return true
        }

        if prefs.cpuShowTemperature {
            renderTemperature(at: renderOffset)
            renderOffset += temperatureDisplayWidth
        }

        if prefs.cpuDisplayMode & CPU.displayHorizontalThermometer != 0 {
            let rows = max(1, prefs.cpuHorizontalRows)
            // Lay out by displayed bar, not by CPU index, so that with a
            // stride of 2 the bars still fill every row.
            let displayCount = (Int(cpuCount) + Int(stride) - 1) / Int(stride)
            let columns = (displayCount + rows - 1) / rows
            // menuWidth also covers the temperature drawn before renderOffset.
            let columnWidth = (menuWidth - renderOffset - 1) / CGFloat(columns)
            let height = imageHeight()
            let thermometerHeight = (height - 2) / CGFloat(rows)
            for display in 0..<displayCount {
                let column = CGFloat(display / rows)
                let row = CGFloat(display % rows + 1)
                let x = renderOffset + column * columnWidth + 1
                let y = height - row * thermometerHeight - 1
                renderHorizontalThermometer(processor: UInt32(display * Int(stride)), x: x, y: y,
                                            width: columnWidth, height: thermometerHeight)
            }
        } else {
            var cpu = 0
            while cpu < cpuCount {
                if prefs.cpuDisplayMode & CPU.displayGraph != 0 {
                    renderHistoryGraph(processor: UInt32(cpu), offset: renderOffset)
                    renderOffset += CGFloat(prefs.cpuGraphLength)
                }
                if prefs.cpuDisplayMode & CPU.displayPercent != 0 {
                    if prefs.cpuPercentDisplay == CPU.percentSplit {
                        renderSplitPercent(processor: UInt32(cpu), offset: renderOffset)
                    } else {
                        renderSinglePercent(processor: UInt32(cpu), offset: renderOffset)
                    }
                    renderOffset += percentWidth
                }
                if prefs.cpuDisplayMode & CPU.displayThermometer != 0 {
                    renderThermometer(processor: UInt32(cpu), offset: renderOffset)
                    renderOffset += CPU.thermometerWidth
                }
                renderOffset += CPU.multiProcGap
                if prefs.cpuAvgAllProcs { break }
                cpu += Int(stride)
            }
        }
        return true
    }

    private func load(for processor: UInt32, at position: Int) -> (system: Double, user: Double) {
        let samples: [CPULoadSample]?
        if position == -1 {
            samples = loadHistory.last
        } else {
            samples = position < loadHistory.count ? loadHistory[position] : nil
        }
        guard let samples, Int(processor) < samples.count else { return (-1, -1) }

        var system = 0.0
        var user = 0.0
        if Prefs.shared.cpuAvgAllProcs {
            let count = min(Int(cpuInfo.numberOfCPUs), samples.count)
            guard count > 0 else { return (-1, -1) }
            for index in 0..<count {
                system += samples[index].system
                user += samples[index].user
            }
            system /= Double(count)
            user /= Double(count)
        } else {
            system = samples[Int(processor)].system
            user = samples[Int(processor)].user
        }
        return (min(1, max(0, system)), min(1, max(0, user)))
    }

    private func renderHistoryGraph(processor: UInt32, offset: CGFloat) {
        let systemPath = NSBezierPath()
        let userPath = NSBezierPath()
        systemPath.move(to: NSPoint(x: offset, y: 0))
        userPath.move(to: NSPoint(x: offset, y: 0))

        let renderHeight = imageHeight() - 0.5
        let graphLength = Prefs.shared.cpuGraphLength
        var position = 0
        while position < graphLength && position < loadHistory.count {
            let value = load(for: processor, at: position)
            let total = min(1, value.system + value.user)
            userPath.line(to: NSPoint(x: offset + CGFloat(position), y: total * renderHeight + 0.5))
            systemPath.line(to: NSPoint(x: offset + CGFloat(position), y: value.system * renderHeight + 0.5))
            position += 1
        }
        let endX = offset + CGFloat(position) - 1
        userPath.line(to: NSPoint(x: endX, y: 0))
        systemPath.line(to: NSPoint(x: endX, y: 0))

        userColor.setFill()
        userPath.fill()
        systemColor.setFill()
        systemPath.fill()
    }

    private func percentString(load: Double, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: "\(Int((load * 100).rounded()))%", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: color
        ])
    }

    private func renderSinglePercent(processor: UInt32, offset: CGFloat) {
        let value = load(for: processor, at: -1)
        guard value.system >= 0, value.user >= 0 else { return }
        var total = min(1, max(0, value.system + value.user))
        if Prefs.shared.cpuSumAllProcsPercent {
            total *= Double(cpuInfo.numberOfCPUs)
        }
        let string = percentString(load: total, color: fgMenuThemeColor)
        string.draw(at: NSPoint(x: offset + percentWidth - ceil(string.size().width) - 1,
                                y: (imageHeight() - string.size().height) / 2 + baselineOffset))
    }

    private func renderSplitPercent(processor: UInt32, offset: CGFloat) {
        let value = load(for: processor, at: -1)
        guard value.system >= 0, value.user >= 0 else { return }
        var system = value.system
        var user = value.user
        if Prefs.shared.cpuSumAllProcsPercent {
            system *= Double(cpuInfo.numberOfCPUs)
            user *= Double(cpuInfo.numberOfCPUs)
        }
        let systemString = percentString(load: system, color: systemColor)
        let userString = percentString(load: user, color: userColor)
        systemString.draw(at: NSPoint(x: offset + percentWidth - systemString.size().width - 1, y: -1))
        userString.draw(at: NSPoint(x: offset + percentWidth - userString.size().width - 1,
                                    y: floor(imageHeight() / 2) - 1))
    }

    private func temperatureString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: temperatureColor
        ])
    }

    private func renderTemperature(at offset: CGFloat) {
        let celsius = cpuInfo.cpuProximityTemperature()
        let fahrenheit = celsius * 1.8 + 32
        var text = "???"
        switch Prefs.shared.cpuTemperatureUnit {
        case 0:
            text = celsius < -100 ? "??℃" : String(format: "%.1f℃", celsius)
        case 1:
            if celsius < -100 {
                text = "??℉"
            } else if fahrenheit >= 100 {
                text = String(format: "%d℉", Int(fahrenheit))
            } else {
                text = String(format: "%.1f℉", fahrenheit)
            }
        default:
            break
        }
        let string = temperatureString(text)
        string.draw(at: NSPoint(x: temperatureDisplayWidth - ceil(string.size().width) - 1,
                                y: (imageHeight() - string.size().height) / 2 + baselineOffset))
    }

    private func renderThermometer(processor: UInt32, offset: CGFloat) {
        let value = load(for: processor, at: -1)
        guard value.system >= 0, value.user >= 0 else { return }
        let totalHeight = imageHeight() - 3

        let userRect = NSRect(x: offset + 1.5, y: 1.5, width: CPU.thermometerWidth - 3,
                              height: totalHeight * min(1, value.user + value.system))
        let systemRect = NSRect(x: offset + 1.5, y: 1.5, width: CPU.thermometerWidth - 3,
                                height: totalHeight * value.system)
        let frameRect = NSRect(x: offset + 1.5, y: 1.5, width: CPU.thermometerWidth - 3,
                               height: totalHeight)

        userColor.setFill()
        NSBezierPath(rect: userRect).fill()
        systemColor.setFill()
        NSBezierPath(rect: systemRect).fill()
        fgMenuThemeColor.withAlphaComponent(MM.borderAlpha).setStroke()
        NSBezierPath(rect: frameRect).stroke()
    }

    private func renderHorizontalThermometer(processor: UInt32, x: CGFloat, y: CGFloat,
                                             width: CGFloat, height: CGFloat) {
        let value = load(for: processor, at: -1)
        guard value.system >= 0, value.user >= 0 else { return }

        let capRect = NSRect(x: x + width - 2, y: y, width: 1, height: height - 1)
        let userRect = NSRect(x: x + 1, y: y, width: (width - 2) * min(1, value.user + value.system),
                              height: height - 1)
        let systemRect = NSRect(x: x + 1, y: y, width: (width - 2) * value.system, height: height - 1)

        userColor.setFill()
        NSBezierPath(rect: userRect).fill()
        systemColor.setFill()
        NSBezierPath(rect: systemRect).fill()
        fgMenuThemeColor.withAlphaComponent(MM.borderAlpha).setFill()
        NSBezierPath(rect: capRect).fill()
    }
}
