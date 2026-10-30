//
//  MemExtra.swift
//  MenuMeters
//
//  Memory menu bar meter.
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
//  2026-10-30  Luca Gibelli: fixed cache hit rate and pressure display; menu no longer advances samples.
//

import Cocoa

final class MemExtra: MenuExtraBase {
    private let memory = MemStats()
    private var extraMenu = NSMenu()
    private var history: [MemSample] = []
    private var swapStats: SwapSample?
    private var textWidth: CGFloat = 0
    private var numberLabelWidth: CGFloat = 0
    private var fgMenuThemeColor: NSColor = .labelColor
    private var freeColor: NSColor = .green
    private var usedColor: NSColor = .red
    private var activeColor: NSColor = .green
    private var inactiveColor: NSColor = .gray
    private var wireColor: NSColor = .blue
    private var compressedColor: NSColor = .purple
    private var pageInColor: NSColor = .blue
    private var pageOutColor: NSColor = .red

    private lazy var floatMBFormatter = Self.formatter("#,##0.0\(L("MB"))")
    private lazy var intMBFormatter = Self.formatter("#,##0\(L("MB"))")
    private lazy var integerFormatter = Self.formatter("#,##0")
    private lazy var percentFormatter = Self.formatter("##0.0%")

    override init(bundleID: String) {
        super.init(bundleID: bundleID)
        buildMenu()
        configFromPrefs(nil)
    }

    // MARK: - Menu

    private func buildMenu() {
        extraMenu = NSMenu(title: "")
        extraMenu.autoenablesItems = false

        addDisabled(L("Memory Usage:"))
        addDisabled("", indent: 1)
        addDisabled(L("Memory Pages:"))
        addDisabled("", indent: 1)
        addDisabled("", indent: 1)
        addDisabled("", indent: 1)
        addDisabled(L("VM Statistics:"))
        addDisabled("", indent: 1)
        addDisabled("", indent: 1)
        addDisabled("", indent: 1)
        addDisabled(L("Memory Pressure:"))
        addDisabled("", indent: 1)
        addDisabled(L("Swap Files:"))
        addDisabled("", indent: 1)
        addDisabled("", indent: 1)
        addDisabled("", indent: 1)
        extraMenu.addItem(.separator())
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
        if let stats = memory.swapStats() {
            swapStats = stats
        }
        // Take a read-only snapshot: the paging baselines and the graph
        // history advance only on the timer.
        if let stats = memory.memSnapshot() ?? history.last {
            updateMenuContent(stats)
        }
        return extraMenu
    }

    private func updateMenuContent(_ stats: MemSample) {
        guard let swap = swapStats else { return }

        let usage = String(format: L("%@ used, %@ free, %@ total"),
                           floatMB(stats.usedMB), floatMB(stats.freeMB), intMB(stats.totalMB))
        liveUpdateMenuItemTitle(extraMenu, Mem.usageMenuIndex, usage)

        let wired = String(format: L("%@ active, %@ wired"),
                           floatMB(stats.activeMB), floatMB(stats.wireMB))
        liveUpdateMenuItemTitle(extraMenu, Mem.activeWiredMenuIndex, wired)

        let inactive = String(format: L("%@ inactive, %@ free"),
                              floatMB(stats.inactiveMB), floatMB(stats.freePageMB))
        liveUpdateMenuItemTitle(extraMenu, Mem.inactiveFreeMenuIndex, inactive)

        let compressed = String(format: L("%@ compressed (%@)"),
                                floatMB(stats.compressedMB), floatMB(stats.uncompressedMB))
        liveUpdateMenuItemTitle(extraMenu, Mem.compressedMenuIndex, compressed)

        let paging = String(format: L("%@ pageins, %@ pageouts"),
                            integer(stats.pageIns), integer(stats.pageOuts))
        liveUpdateMenuItemTitle(extraMenu, Mem.pageInfoMenuIndex, paging)

        // A fraction: the "%" in the formatter's pattern multiplies by 100.
        let hitRate = stats.lookups == 0 ? 0 : Double(stats.hits) / Double(stats.lookups)
        let cache = String(format: L("%@ cache lookups, %@ cache hits (%@)"),
                           integer(stats.lookups), integer(stats.hits), percent(hitRate))
        liveUpdateMenuItemTitle(extraMenu, Mem.cacheInfoMenuIndex, cache)

        let faults = String(format: L("%@ page faults, %@ copy-on-writes"),
                            integer(stats.faults), integer(stats.cowFaults))
        liveUpdateMenuItemTitle(extraMenu, Mem.faultInfoMenuIndex, faults)

        let pressure = String(format: L("%@%%\t(level %@)"),
                              "\(stats.pressure)", "\(stats.pressureLevel)")
        liveUpdateMenuItemTitle(extraMenu, Mem.pressureInfoMenuIndex, pressure)

        let swapFormat: String
        if swap.encrypted {
            swapFormat = swap.count == 1 ? L("%@ encrypted swap file present in %@")
                                         : L("%@ encrypted swap files present in %@")
        } else {
            swapFormat = swap.count == 1 ? L("%@ swap file present in %@")
                                         : L("%@ swap files present in %@")
        }
        liveUpdateMenuItemTitle(extraMenu, Mem.swapCountMenuIndex,
                                String(format: swapFormat, integer(UInt64(swap.count)), swap.path))

        let peakFormat = swap.peakCount == 1 ? L("%@ swap file at peak usage")
                                             : L("%@ swap files at peak usage")
        liveUpdateMenuItemTitle(extraMenu, Mem.swapPeakMenuIndex,
                                String(format: peakFormat, integer(UInt64(swap.peakCount))))

        liveUpdateMenuItemTitle(extraMenu, Mem.swapSizeMenuIndex,
                                String(format: L("%@ total swap space (%@ used)"),
                                       intMB(Double(swap.sizeMB)), intMB(Double(swap.usedMB))))
    }

    // MARK: - Preferences

    override func configFromPrefs(_ notification: Notification?) {
        configDisplay(interval: Prefs.shared.memInterval)
        setupColor()

        let prefs = Prefs.shared
        var mbLength: CGFloat = 0
        if prefs.memDisplayMode == Mem.displayNumber {
            mbLength = ceil(attributedLabel(L("MB"), color: fgMenuThemeColor).size().width)
        }
        numberLabelWidth = max(attributedLabel(L("U:"), color: usedColor).size().width,
                               attributedLabel(L("F:"), color: freeColor).size().width)

        menuWidth = 0
        switch prefs.memDisplayMode {
        case Mem.displayPie:
            menuWidth = Mem.pieWidth
        case Mem.displayNumber:
            let total = UInt64(memory.memSnapshot()?.totalMB ?? 0)
            let base: CGFloat
            if total >= 10_000 {
                base = Mem.numberExtraLongWidth
            } else if total >= 1_000 {
                base = Mem.numberLongWidth
            } else {
                base = Mem.numberShortWidth
            }
            textWidth = base + mbLength
            menuWidth = textWidth
            if prefs.memUsedFreeLabel {
                menuWidth += ceil(numberLabelWidth)
                textWidth += ceil(numberLabelWidth)
            }
        case Mem.displayBar:
            menuWidth = Mem.thermometerWidth
        case Mem.displayGraph:
            menuWidth = CGFloat(prefs.memGraphLength)
        default:
            break
        }
        if prefs.memPageIndicator {
            menuWidth += Mem.pagingWidth + Mem.pagingGap
        }

        statusItem?.button?.image = makeImage()
    }

    override func setupColor() {
        fgMenuThemeColor = menuBarTextColor()
        let prefs = Prefs.shared
        freeColor = colorByAdjustingForLightDark(prefs.memFreeColor)
        usedColor = colorByAdjustingForLightDark(prefs.memUsedColor)
        activeColor = colorByAdjustingForLightDark(prefs.memActiveColor)
        inactiveColor = colorByAdjustingForLightDark(prefs.memInactiveColor)
        wireColor = colorByAdjustingForLightDark(prefs.memWireColor)
        compressedColor = colorByAdjustingForLightDark(prefs.memCompressedColor)
        pageInColor = colorByAdjustingForLightDark(prefs.memPageInColor)
        pageOutColor = colorByAdjustingForLightDark(prefs.memPageOutColor)
    }

    // MARK: - Timer

    override func timerFired(_ timer: Timer) {
        guard refreshHistory() else { return }
        if isMenuVisible {
            updateMenuWhenDown()
        }
        super.timerFired(timer)
    }

    @discardableResult
    private func refreshHistory() -> Bool {
        guard let current = memory.memStats() else { return false }
        let prefs = Prefs.shared
        if prefs.memDisplayMode == Mem.displayGraph {
            if history.count >= prefs.memGraphLength {
                history.removeFirst(history.count - prefs.memGraphLength + 1)
            }
        } else {
            history.removeAll()
        }
        history.append(current)
        return true
    }

    private func updateMenuWhenDown() {
        if let stats = memory.swapStats() {
            swapStats = stats
        }
        if let stats = history.last {
            updateMenuContent(stats)
        }
        forceMenuRedraw(extraMenu)
    }

    // MARK: - Rendering

    override func renderImage() -> Bool {
        guard let stats = history.last else { return false }
        let prefs = Prefs.shared

        switch prefs.memDisplayMode {
        case Mem.displayPie:
            renderPie(stats)
        case Mem.displayNumber:
            renderNumbers(stats)
        case Mem.displayBar:
            if prefs.memPressure {
                renderPressureBar(stats)
            } else {
                renderBar(stats)
            }
        case Mem.displayGraph:
            if prefs.memPressure {
                renderPressureHistory()
            } else {
                renderMemHistory()
            }
        default:
            break
        }

        if prefs.memPageIndicator {
            renderPageIndicator(stats)
        }
        return true
    }

    private func renderPie(_ stats: MemSample) {
        let total = max(1, CGFloat(stats.totalMB))
        var wire = CGFloat(stats.wireMB)
        var active = CGFloat(stats.activeMB)
        var compressed = CGFloat(stats.compressedMB)
        var inactive = CGFloat(stats.inactiveMB)
        wire = min(max(0, wire), total)
        active = min(max(0, active), total)
        compressed = min(max(0, compressed), total)
        inactive = min(max(0, inactive), total)

        let center = NSPoint(x: Mem.pieWidth / 2, y: imageHeight() / 2)
        let radius = Mem.pieWidth / 2
        var totalArc: CGFloat = 0

        func wedge(_ value: CGFloat, color: NSColor) {
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius,
                           startAngle: 360 * totalArc + 90,
                           endAngle: 360 * (value / total + totalArc) + 90,
                           clockwise: false)
            path.line(to: center)
            color.setFill()
            path.fill()
            totalArc += value / total
        }

        wedge(wire, color: wireColor)
        wedge(active, color: activeColor)
        wedge(compressed, color: compressedColor)
        wedge(inactive, color: inactiveColor)

        fgMenuThemeColor.withAlphaComponent(MM.borderAlpha).setStroke()
        if totalArc < 1 {
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius - 0.5,
                           startAngle: 360 * totalArc + 90,
                           endAngle: 450,
                           clockwise: false)
            path.lineWidth = 0.6
            path.stroke()
        }
    }

    private func renderNumbers(_ stats: MemSample) {
        let used = max(0, stats.usedMB)
        let free = max(0, stats.freeMB)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

        let usedString = NSAttributedString(string: String(format: "%.0f%@", used, L("MB")),
                                            attributes: [.font: font, .foregroundColor: usedColor])
        let freeString = NSAttributedString(string: String(format: "%.0f%@", free, L("MB")),
                                            attributes: [.font: font, .foregroundColor: freeColor])

        if Prefs.shared.memUsedFreeLabel {
            attributedLabel(L("U:"), color: usedColor).draw(at: NSPoint(x: 0, y: floor(imageHeight() / 2) - 1))
            attributedLabel(L("F:"), color: freeColor).draw(at: NSPoint(x: 0, y: -1))
        }
        usedString.draw(at: NSPoint(x: textWidth - round(usedString.size().width),
                                    y: floor(imageHeight() / 2) - 1))
        freeString.draw(at: NSPoint(x: textWidth - round(freeString.size().width), y: -1))
    }

    private func renderPressureBar(_ stats: MemSample) {
        let pressure = max(0, CGFloat(stats.pressure) / 100)
        let totalHeight = imageHeight() - 3
        let width = Mem.thermometerWidth - 3

        activeColor.setFill()
        NSBezierPath(rect: NSRect(x: 1.5, y: 1.5, width: width,
                                  height: totalHeight * pressure)).fill()

        fgMenuThemeColor.withAlphaComponent(MM.borderAlpha).setStroke()
        NSBezierPath(rect: NSRect(x: 1.5, y: 1.5, width: width, height: totalHeight)).stroke()
    }

    private func renderBar(_ stats: MemSample) {
        let total = max(1, CGFloat(stats.totalMB))
        let wire = min(max(0, CGFloat(stats.wireMB)), total)
        let active = min(max(0, CGFloat(stats.activeMB)), total)
        let compressed = min(max(0, CGFloat(stats.compressedMB)), total)
        let inactive = min(max(0, CGFloat(stats.inactiveMB)), total)
        let height = imageHeight() - 3
        let width = Mem.thermometerWidth - 3
        let rect = { (fraction: CGFloat) in
            NSRect(x: 1.5, y: 1.5, width: width, height: height * fraction)
        }

        inactiveColor.setFill()
        NSBezierPath(rect: rect((wire + active + compressed + inactive) / total)).fill()
        compressedColor.setFill()
        NSBezierPath(rect: rect((wire + active + compressed) / total)).fill()
        activeColor.setFill()
        NSBezierPath(rect: rect((wire + active) / total)).fill()
        wireColor.setFill()
        NSBezierPath(rect: rect(wire / total)).fill()

        fgMenuThemeColor.withAlphaComponent(MM.borderAlpha).setStroke()
        NSBezierPath(rect: NSRect(x: 1.5, y: 1.5, width: width, height: height)).stroke()
    }

    private func renderPressureHistory() {
        let renderHeight = imageHeight()
        let path = NSBezierPath()
        path.move(to: .zero)

        var position = 0
        while position < Prefs.shared.memGraphLength && position < history.count {
            let pressure = min(100, max(0, history[position].pressure))
            path.line(to: NSPoint(x: CGFloat(position),
                                  y: CGFloat(pressure) / 100 * renderHeight))
            position += 1
        }
        path.line(to: NSPoint(x: CGFloat(position - 1), y: 0))

        activeColor.setFill()
        path.fill()
    }

    private func renderMemHistory() {
        let renderHeight = imageHeight()
        let wirePath = NSBezierPath()
        let activePath = NSBezierPath()
        let compressedPath = NSBezierPath()
        let inactivePath = NSBezierPath()
        for path in [wirePath, activePath, compressedPath, inactivePath] {
            path.move(to: .zero)
        }

        var position = 0
        while position < Prefs.shared.memGraphLength && position < history.count {
            let sample = history[position]
            let total = max(1, CGFloat(sample.totalMB))
            let wire = min(max(0, CGFloat(sample.wireMB)), total)
            let active = min(max(0, CGFloat(sample.activeMB)), total)
            let compressed = min(max(0, CGFloat(sample.compressedMB)), total)
            let inactive = min(max(0, CGFloat(sample.inactiveMB)), total)
            let x = CGFloat(position)
            inactivePath.line(to: NSPoint(x: x, y: min(1, (inactive + compressed + active + wire) / total) * renderHeight))
            compressedPath.line(to: NSPoint(x: x, y: min(1, (compressed + active + wire) / total) * renderHeight))
            activePath.line(to: NSPoint(x: x, y: min(1, (active + wire) / total) * renderHeight))
            wirePath.line(to: NSPoint(x: x, y: wire / total * renderHeight))
            position += 1
        }
        let endX = CGFloat(position - 1)
        for path in [wirePath, activePath, compressedPath, inactivePath] {
            path.line(to: NSPoint(x: endX, y: 0))
        }

        inactiveColor.setFill()
        inactivePath.fill()
        compressedColor.setFill()
        compressedPath.fill()
        activeColor.setFill()
        activePath.fill()
        wireColor.setFill()
        wirePath.fill()
    }

    private func renderPageIndicator(_ stats: MemSample) {
        let height = imageHeight()
        let dark = isDark()
        let center = Mem.pagingWidth / 2 + (menuWidth - Mem.pagingWidth) - 0.5

        let bottom = NSBezierPath()
        bottom.move(to: NSPoint(x: center, y: 1))
        bottom.line(to: NSPoint(x: center + 5, y: 5))
        bottom.line(to: NSPoint(x: center - 5, y: 5))
        bottom.close()
        if stats.deltaPageIns > 0 {
            pageInColor.setFill()
        } else if dark {
            NSColor.darkGray.setFill()
        } else {
            pageInColor.withAlphaComponent(0.25).setFill()
        }
        bottom.fill()

        let top = NSBezierPath()
        top.move(to: NSPoint(x: center, y: height - 1))
        top.line(to: NSPoint(x: center + 5, y: height - 5))
        top.line(to: NSPoint(x: center - 5, y: height - 5))
        top.close()
        if stats.deltaPageOuts > 0 {
            pageOutColor.setFill()
        } else if dark {
            NSColor.darkGray.setFill()
        } else {
            pageOutColor.withAlphaComponent(0.25).setFill()
        }
        top.fill()

        let total = stats.deltaPageIns + stats.deltaPageOuts
        let text = total >= 1000 ? "1k+" : "\(total)"
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: fgMenuThemeColor
        ])
        string.draw(at: NSPoint(x: menuWidth - Mem.pagingWidth +
                                round((Mem.pagingWidth - string.size().width) / 2),
                                y: 4))
    }

    // MARK: - Formatting

    private static func formatter(_ format: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.localizesFormat = true
        formatter.format = format
        return formatter
    }

    private func floatMB(_ value: Double) -> String {
        floatMBFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value) + L("MB")
    }

    private func intMB(_ value: Double) -> String {
        intMBFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value) + L("MB")
    }

    private func integer(_ value: UInt64) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func percent(_ value: Double) -> String {
        percentFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f%%", value * 100)
    }

    private func attributedLabel(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: color
        ])
    }
}
