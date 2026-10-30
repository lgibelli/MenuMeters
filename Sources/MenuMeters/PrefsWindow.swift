//
//  PrefsWindow.swift
//  MenuMeters
//
//  The five-tab preferences window, built programmatically.
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
//  2026-10-30  Luca Gibelli: login item and update controls; meter changes are always announced.
//

import Cocoa
import ApplicationServices
import ServiceManagement

final class PrefsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSTabViewDelegate {
    private let prefs = Prefs.shared
    private let aboutFile: String
    private let netConfig = NetConfig()
    private var powerMateAvailable = false

    private var prefTabs: NSTabView!
    private var aboutView: NSTextView!

    // CPU
    private var cpuMeterToggle: NSButton!
    private var cpuPercentage: NSButton!
    private var cpuGraph: NSButton!
    private var cpuThermometer: NSButton!
    private var cpuHorizontalThermometer: NSButton!
    private var cpuTemperatureToggle: NSButton!
    private var cpuTemperatureUnit: NSPopUpButton!
    private var cpuInterval: NSSlider!
    private var cpuIntervalDisplay: NSTextField!
    private var cpuPercentMode: NSPopUpButton!
    private var cpuMaxProcessCount: NSSlider!
    private var cpuMaxProcessCountCountLabel: NSTextField!
    private var cpuGraphWidth: NSSlider!
    private var cpuGraphWidthLabel: NSTextField!
    private var cpuHorizontalRows: NSSlider!
    private var cpuHorizontalRowsLabel: NSTextField!
    private var cpuMenuWidth: NSSlider!
    private var cpuMenuWidthLabel: NSTextField!
    private var cpuMultipleCPU: NSPopUpButton!
    private var cpuPowerMate: NSButton!
    private var cpuPowerMateMode: NSPopUpButton!
    private var cpuUserColor: NSColorWell!
    private var cpuSystemColor: NSColorWell!
    private var cpuTemperatureColor: NSColorWell!
    private var cpuUserColorLabel: NSTextField!
    private var cpuSystemColorLabel: NSTextField!
    private var cpuTemperatureSensor: NSPopUpButton!

    // Disk
    private var diskMeterToggle: NSButton!
    private var diskImageSet: NSPopUpButton!
    private var diskInterval: NSSlider!
    private var diskIntervalDisplay: NSTextField!
    private var diskSelectMode: NSPopUpButton!

    // Memory
    private var memMeterToggle: NSButton!
    private var memDisplayMode: NSPopUpButton!
    private var memInterval: NSSlider!
    private var memIntervalDisplay: NSTextField!
    private var memFreeUsedLabeling: NSButton!
    private var memPageIndicator: NSButton!
    private var memPressureMode: NSButton!
    private var memGraphWidth: NSSlider!
    private var memGraphWidthLabel: NSTextField!
    private var memActiveColor: NSColorWell!
    private var memInactiveColor: NSColorWell!
    private var memWiredColor: NSColorWell!
    private var memCompressedColor: NSColorWell!
    private var memFreeColor: NSColorWell!
    private var memUsedColor: NSColorWell!
    private var memPageinColor: NSColorWell!
    private var memPageinColorLabel: NSTextField!
    private var memPageoutColor: NSColorWell!
    private var memPageoutColorLabel: NSTextField!

    // Network
    private var netMeterToggle: NSButton!
    private var netDisplayMode: NSPopUpButton!
    private var netDisplayOrientation: NSPopUpButton!
    private var netPreferInterface: NSPopUpButton!
    private var netScaleMode: NSPopUpButton!
    private var netScaleModeLabel: NSTextField!
    private var netScaleCalc: NSPopUpButton!
    private var netScaleCalcLabel: NSTextField!
    private var netInterval: NSSlider!
    private var netIntervalDisplay: NSTextField!
    private var netThroughputLabeling: NSButton!
    private var netThroughput1KBound: NSButton!
    private var netThroughputBits: NSButton!
    private var netGraphStyle: NSPopUpButton!
    private var netGraphStyleLabel: NSTextField!
    private var netGraphWidth: NSSlider!
    private var netGraphWidthLabel: NSTextField!
    private var netTxColor: NSColorWell!
    private var netRxColor: NSColorWell!
    private var netInactiveColor: NSColorWell!

    // About
    private var activityMonitorPaneCheckbox: NSButton!
    private var loginItemCheckbox: NSButton!
    private var automaticUpdatesCheckbox: NSButton!
    private var checkForUpdatesButton: NSButton!
    private var tintPercentageSlider: NSSlider!

    private let updater: Updater?

    init(aboutFile: String, updater: Updater?) {
        self.aboutFile = aboutFile
        self.updater = updater
        super.init(window: nil)
        setUp()
        updater?.onAvailabilityChange = { [weak self] in self?.updateUpdateControls() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        netConfig.onChange = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func setUp() {
        netConfig.onChange = { [weak self] in
            self?.updateNetInterfaceMenu()
            self?.updateNetworkControls()
        }

        window = buildWindow()
        window?.delegate = self

        populateDiskImageSets()
        configureIntervalFormatters()
        updateTemperatureSensors()
        refreshPowerMateAvailability()
        updateMeterToggles()
        updateNetInterfaceMenu()
        updateAllControls()
        setupAboutTab()
        setupAboutControls()
        setupToolbar()
        installObservers()

        if noMenuMeterLoaded {
            promotePreferences()
        }
    }

    // MARK: - Window construction

    private func buildWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 119, y: 174, width: 594, height: 673),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = LP("MenuMeters")
        window.isReleasedWhenClosed = false
        window.delegate = self

        prefTabs = NSTabView(frame: NSRect(x: 13, y: 11, width: 568, height: 652))
        prefTabs.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(prefTabs)

        buildCPUTab()
        buildDiskTab()
        buildMemoryTab()
        buildNetworkTab()
        buildAboutTab()
        return window
    }

    private func addTab(identifier: String, label key: String, containerFrame: NSRect) -> NSView {
        let item = NSTabViewItem(identifier: identifier)
        item.label = LP(key)
        let tabView = NSView(frame: NSRect(x: 10, y: 33, width: 548, height: 606))
        tabView.autoresizingMask = [.width, .height]
        let container = NSView(frame: containerFrame)
        container.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        tabView.addSubview(container)
        item.view = tabView
        prefTabs.addTabViewItem(item)
        return container
    }

    private func buildCPUTab() {
        let container = addTab(identifier: "cpu", label: "CPU",
                               containerFrame: NSRect(x: 0, y: -3, width: 554, height: 626))

        cpuPowerMateMode = popup(container, NSRect(x: 317, y: 90, width: 216, height: 26),
                                 ["glow", "pulse", "inverse glow", "inverse pulse"], 2,
                                 #selector(cpuPrefChange(_:)))
        cpuPowerMate = checkbox(container, "PowerMate shows CPU usage as",
                                NSRect(x: 87, y: 94, width: 225, height: 21),
                                #selector(cpuPrefChange(_:)))
        separator(container, NSRect(x: 68, y: 75, width: 464, height: 5))
        _ = label(container, "Colors", NSRect(x: 18, y: 69, width: 45, height: 17))
        separator(container, NSRect(x: 130, y: 326, width: 401, height: 5))
        _ = label(container, "Graph Display", NSRect(x: 17, y: 326, width: 107, height: 17))
        separator(container, NSRect(x: 227, y: 208, width: 303, height: 5))
        _ = label(container, "Horizontal Thermometer Display", NSRect(x: 17, y: 203, width: 211, height: 21))
        separator(container, NSRect(x: 146, y: 386, width: 385, height: 5))
        _ = label(container, "Percentage Display", NSRect(x: 17, y: 385, width: 124, height: 17))
        cpuGraphWidthLabel = label(container, "Graph width:", NSRect(x: 85, y: 298, width: 160, height: 17))
        cpuHorizontalRowsLabel = label(container, "Horizontal Rows:", NSRect(x: 84, y: 170, width: 115, height: 22))
        _ = label(container, "Display percentage as:", NSRect(x: 85, y: 359, width: 148, height: 17))
        cpuGraphWidth = slider(container, NSRect(x: 251, y: 294, width: 279, height: 18),
                               11, 88, 33, 8, true, false, .small, #selector(cpuPrefChange(_:)))
        cpuHorizontalRows = slider(container, NSRect(x: 251, y: 172, width: 279, height: 18),
                                   1, 8, 4, 8, true, false, .small, #selector(cpuPrefChange(_:)))
        cpuMenuWidthLabel = label(container, "Horizontal Width:", NSRect(x: 85, y: 146, width: 148, height: 22))
        cpuMenuWidth = slider(container, NSRect(x: 250, y: 148, width: 280, height: 18),
                              60, 400, 120, 8, false, false, .small, #selector(cpuPrefChange(_:)))
        _ = label(container, "System", NSRect(x: 226, y: 58, width: 100, height: 14), .center, 11)
        _ = label(container, "User", NSRect(x: 86, y: 58, width: 100, height: 14), .center, 11)
        cpuUserColor = colorWell(container, NSRect(x: 110, y: 20, width: 53, height: 30),
                                 #selector(cpuPrefChange(_:)))
        cpuSystemColor = colorWell(container, NSRect(x: 250, y: 20, width: 53, height: 30),
                                   #selector(cpuPrefChange(_:)))
        cpuIntervalDisplay = label(container, "x", NSRect(x: 183, y: 453, width: 54, height: 17), .center)
        _ = label(container, "Update interval (seconds):", NSRect(x: 18, y: 453, width: 168, height: 17))
        cpuInterval = slider(container, NSRect(x: 249, y: 444, width: 283, height: 24),
                             0.5, 10, 1.5, 20, true, true, .regular,
                             #selector(liveUpdateInterval(_:)))
        cpuMeterToggle = checkbox(container, "Display CPU Menu Meter",
                                  NSRect(x: 19, y: 571, width: 227, height: 27),
                                  #selector(cpuPrefChange(_:)))
        separator(container, NSRect(x: 130, y: 267, width: 402, height: 5))
        _ = label(container, "Process Display", NSRect(x: 18, y: 267, width: 106, height: 17))
        cpuMaxProcessCount = slider(container, NSRect(x: 250, y: 235, width: 280, height: 18),
                                    0, 25, 5, 26, true, true, .small,
                                    #selector(cpuPrefChange(_:)))
        cpuMaxProcessCountCountLabel = label(container, "(%d)", NSRect(x: 202, y: 239, width: 35, height: 17),
                                             .right)
        _ = label(container, "Temperature", NSRect(x: 360, y: 58, width: 100, height: 14), .center, 11)
        cpuTemperatureColor = colorWell(container, NSRect(x: 384, y: 20, width: 53, height: 30),
                                        #selector(cpuPrefChange(_:)))
        _ = label(container, "Misc", NSRect(x: 18, y: 117, width: 125, height: 22))
        _ = label(container, "Show:", NSRect(x: 84, y: 410, width: 121, height: 22))
        cpuMultipleCPU = popup(container, NSRect(x: 248, y: 408, width: 285, height: 26),
                               ["all cores, including hyperthreaded ones", "physical cores only",
                                "the average of all cores", "the sum of all cores", "all cores sorted"],
                               0, #selector(cpuPrefChange(_:)))
        separator(container, NSRect(x: 69, y: 125, width: 462, height: 5))
        _ = label(container, "Processes to show:", NSRect(x: 84, y: 240, width: 161, height: 16))
        cpuTemperatureToggle = checkbox(container, "Show CPU Temperature in",
                                        NSRect(x: 248, y: 524, width: 181, height: 18),
                                        #selector(cpuPrefChange(_:)))
        cpuPercentMode = popup(container, NSRect(x: 249, y: 353, width: 284, height: 26),
                               ["Total (large text)", "Total (medium text)",
                                "User and System (small text)"],
                               2, #selector(cpuPrefChange(_:)))
        cpuTemperatureUnit = popup(container, NSRect(x: 433, y: 518, width: 99, height: 26),
                                   ["℃", "℉"], 0, #selector(cpuPrefChange(_:)))
        cpuHorizontalThermometer = checkbox(container, "Horizontal bar",
                                            NSRect(x: 382, y: 550, width: 140, height: 18),
                                            #selector(cpuPrefChange(_:)))
        cpuThermometer = checkbox(container, "Vertical bar",
                                  NSRect(x: 382, y: 573, width: 140, height: 18),
                                  #selector(cpuPrefChange(_:)))
        cpuGraph = checkbox(container, "Graph", NSRect(x: 248, y: 550, width: 140, height: 18),
                            #selector(cpuPrefChange(_:)))
        cpuPercentage = checkbox(container, "Percentage", NSRect(x: 248, y: 574, width: 140, height: 18),
                                 #selector(cpuPrefChange(_:)))
        cpuTemperatureSensor = popup(container, NSRect(x: 326, y: 488, width: 206, height: 25),
                                     [], -1, #selector(cpuPrefChange(_:)))
        _ = label(container, "Sensor:", NSRect(x: 269, y: 489, width: 63, height: 22))
    }

    private func buildDiskTab() {
        let container = addTab(identifier: "internaldrive", label: "Disk",
                               containerFrame: NSRect(x: 0, y: 52, width: 554, height: 571))
        _ = label(container, "(Holding the Option key will reverse the behavior)",
                  NSRect(x: 21, y: 391, width: 511, height: 13), .center, 10)
        diskSelectMode = popup(container, NSRect(x: 284, y: 409, width: 241, height: 26),
                               ["opens the volume", "unmounts/ejects the volume"], 0,
                               #selector(diskPrefChange(_:)))
        _ = label(container, "Selecting a volume from the disk menu",
                  NSRect(x: 29, y: 414, width: 251, height: 17), .right)
        _ = label(container, "Update interval (seconds):", NSRect(x: 18, y: 486, width: 168, height: 17))
        diskImageSet = popup(container, NSRect(x: 273, y: 516, width: 262, height: 26),
                             ["ImageSet"], 0, #selector(diskPrefChange(_:)))
        diskInterval = slider(container, NSRect(x: 19, y: 454, width: 515, height: 24),
                              0.1, 5, 0.3, 50, true, true, .regular,
                              #selector(liveUpdateInterval(_:)))
        diskIntervalDisplay = label(container, "x", NSRect(x: 183, y: 486, width: 54, height: 17), .center)
        diskMeterToggle = checkbox(container, "Display Disk Activity Menu Meter",
                                   NSRect(x: 19, y: 516, width: 251, height: 27),
                                   #selector(diskPrefChange(_:)))
    }

    private func buildMemoryTab() {
        let container = addTab(identifier: "memorychip", label: "Memory",
                               containerFrame: NSRect(x: 0, y: 52, width: 554, height: 571))
        memPageIndicator = checkbox(container, "Show paging activity indicator",
                                    NSRect(x: 171, y: 390, width: 302, height: 18),
                                    #selector(memPrefChange(_:)))
        separator(container, NSRect(x: 75, y: 415, width: 457, height: 5))
        _ = label(container, "General", NSRect(x: 18, y: 414, width: 189, height: 17))
        memFreeUsedLabeling = checkbox(container, "Show Used/Free labels",
                                       NSRect(x: 171, y: 370, width: 302, height: 18),
                                       #selector(memPrefChange(_:)))
        memInterval = slider(container, NSRect(x: 19, y: 454, width: 515, height: 24),
                             1, 60, 15, 60, true, true, .regular,
                             #selector(liveUpdateInterval(_:)))
        _ = label(container, "Update interval (seconds):", NSRect(x: 18, y: 486, width: 168, height: 17))
        memDisplayMode = popup(container, NSRect(x: 273, y: 516, width: 262, height: 26),
                               ["Usage Chart", "Usage Bar", "Usage History Graph", "Used/Free Totals"],
                               0, #selector(memPrefChange(_:)))
        memIntervalDisplay = label(container, "x", NSRect(x: 183, y: 486, width: 54, height: 17), .center)
        memMeterToggle = checkbox(container, "Display Memory Menu Meter",
                                  NSRect(x: 19, y: 516, width: 251, height: 27),
                                  #selector(memPrefChange(_:)))
        memInactiveColor = colorWell(container, NSRect(x: 299, y: 178, width: 53, height: 30),
                                     #selector(memPrefChange(_:)))
        memWiredColor = colorWell(container, NSRect(x: 210, y: 178, width: 53, height: 30),
                                  #selector(memPrefChange(_:)))
        memActiveColor = colorWell(container, NSRect(x: 121, y: 178, width: 53, height: 30),
                                   #selector(memPrefChange(_:)))
        _ = label(container, "Active", NSRect(x: 97, y: 216, width: 100, height: 14), .center, 11)
        _ = label(container, "Inactive", NSRect(x: 275, y: 216, width: 100, height: 14), .center, 11)
        _ = label(container, "Wired", NSRect(x: 186, y: 216, width: 100, height: 14), .center, 11)
        memCompressedColor = colorWell(container, NSRect(x: 385, y: 178, width: 53, height: 30),
                                       #selector(memPrefChange(_:)))
        _ = label(container, "Compressed", NSRect(x: 362, y: 216, width: 96, height: 14), .center, 11)
        memUsedColor = colorWell(container, NSRect(x: 299, y: 42, width: 53, height: 30),
                                 #selector(memPrefChange(_:)))
        _ = label(container, "Free", NSRect(x: 221, y: 80, width: 35, height: 14), .left, 11)
        _ = label(container, "Used", NSRect(x: 308, y: 80, width: 44, height: 14), .left, 11)
        memFreeColor = colorWell(container, NSRect(x: 210, y: 42, width: 53, height: 30),
                                 #selector(memPrefChange(_:)))
        separator(container, NSRect(x: 140, y: 317, width: 392, height: 5))
        memGraphWidth = slider(container, NSRect(x: 172, y: 282, width: 299, height: 17),
                               11, 88, 33, 8, true, false, .small,
                               #selector(memPrefChange(_:)))
        _ = label(container, "Graph Display", NSRect(x: 18, y: 319, width: 116, height: 17))
        memGraphWidthLabel = label(container, "Graph width:", NSRect(x: 30, y: 289, width: 137, height: 17), .right)
        separator(container, NSRect(x: 68, y: 243, width: 464, height: 5))
        _ = label(container, "Colors", NSRect(x: 18, y: 242, width: 45, height: 17))
        memPressureMode = checkbox(container, "Display memory pressure",
                                   NSRect(x: 170, y: 352, width: 303, height: 18),
                                   #selector(memPrefChange(_:)))
        memPageoutColorLabel = label(container, "Pageout", NSRect(x: 275, y: 146, width: 100, height: 14),
                                     .center, 11)
        memPageoutColor = colorWell(container, NSRect(x: 299, y: 108, width: 53, height: 30),
                                    #selector(memPrefChange(_:)))
        memPageinColorLabel = label(container, "Pagein", NSRect(x: 186, y: 146, width: 100, height: 14),
                                    .center, 11)
        memPageinColor = colorWell(container, NSRect(x: 210, y: 108, width: 53, height: 30),
                                   #selector(memPrefChange(_:)))
    }

    private func buildNetworkTab() {
        let container = addTab(identifier: "network", label: "Network",
                               containerFrame: NSRect(x: 0, y: 52, width: 554, height: 571))
        netInactiveColor = colorWell(container, NSRect(x: 341, y: 31, width: 53, height: 30),
                                     #selector(netPrefChange(_:)))
        _ = label(container, "Inactive", NSRect(x: 317, y: 69, width: 100, height: 14), .center, 11)
        netDisplayOrientation = popup(container, NSRect(x: 222, y: 385, width: 172, height: 26),
                                      ["Transmit/Receive", "Receive/Transmit"], 0,
                                      #selector(netPrefChange(_:)))
        _ = label(container, "Display orientation:", NSRect(x: 94, y: 390, width: 128, height: 17), .right)
        netScaleCalc = popup(container, NSRect(x: 222, y: 307, width: 172, height: 26),
                             ["Linear", "Square root", "Cube root", "Logarithmic"], 0,
                             #selector(netPrefChange(_:)))
        netScaleCalcLabel = label(container, "Display scaling:", NSRect(x: 30, y: 313, width: 192, height: 17),
                                  .right)
        netScaleMode = popup(container, NSRect(x: 222, y: 333, width: 172, height: 26),
                             ["Interface speed", "Peak traffic"], 0,
                             #selector(netPrefChange(_:)))
        netScaleModeLabel = label(container, "Display scales to:", NSRect(x: 30, y: 339, width: 192, height: 17),
                                  .right)
        separator(container, NSRect(x: 75, y: 415, width: 457, height: 4))
        _ = label(container, "General", NSRect(x: 18, y: 416, width: 64, height: 15))
        netPreferInterface = popup(container, NSRect(x: 222, y: 359, width: 273, height: 26),
                                   ["Primary (automatic)"], 0, #selector(netPrefChange(_:)))
        _ = label(container, "Display prefers interface:", NSRect(x: 30, y: 365, width: 192, height: 17),
                  .right)
        separator(container, NSRect(x: 68, y: 89, width: 464, height: 5))
        _ = label(container, "Colors", NSRect(x: 18, y: 88, width: 45, height: 17))
        separator(container, NSRect(x: 140, y: 193, width: 392, height: 5))
        _ = label(container, "Graph Display", NSRect(x: 18, y: 193, width: 115, height: 16))
        separator(container, NSRect(x: 153, y: 272, width: 379, height: 5))
        _ = label(container, "Throughput Display", NSRect(x: 18, y: 271, width: 130, height: 17))
        netGraphStyle = popup(container, NSRect(x: 162, y: 156, width: 165, height: 26),
                              ["Standard", "Centered", "Opposed", "Inverse Opposed"], 0,
                              #selector(netPrefChange(_:)))
        netGraphWidthLabel = label(container, "Graph width:", NSRect(x: 74, y: 135, width: 86, height: 17),
                                   .right)
        netGraphStyleLabel = label(container, "Graph style:", NSRect(x: 80, y: 162, width: 80, height: 17),
                                   .right)
        netThroughputBits = checkbox(container, "Show bits per second",
                                     NSRect(x: 163, y: 250, width: 317, height: 18),
                                     #selector(netPrefChange(_:)))
        netThroughputLabeling = checkbox(container, "Show throughput labels (Tx/Rx)",
                                         NSRect(x: 163, y: 210, width: 317, height: 18),
                                         #selector(netPrefChange(_:)))
        netRxColor = colorWell(container, NSRect(x: 251, y: 31, width: 53, height: 30),
                               #selector(netPrefChange(_:)))
        netGraphWidth = slider(container, NSRect(x: 165, y: 128, width: 313, height: 18),
                               11, 88, 33, 8, true, false, .small,
                               #selector(netPrefChange(_:)))
        netTxColor = colorWell(container, NSRect(x: 161, y: 31, width: 53, height: 30),
                               #selector(netPrefChange(_:)))
        _ = label(container, "Receive", NSRect(x: 227, y: 69, width: 100, height: 14), .center, 11)
        _ = label(container, "Transmit", NSRect(x: 138, y: 69, width: 100, height: 14), .center, 11)
        _ = label(container, "Update interval (seconds):", NSRect(x: 18, y: 486, width: 168, height: 17))
        netDisplayMode = popup(container, NSRect(x: 273, y: 516, width: 262, height: 26),
                               ["Arrows", "Throughput", "Arrows and Throughput", "Graph",
                                "Graph and Arrows", "Graph and Throughput",
                                "Graph, Arrows and Throughput"], 6,
                               #selector(netPrefChange(_:)))
        netMeterToggle = checkbox(container, "Display Network Menu Meter",
                                  NSRect(x: 19, y: 516, width: 251, height: 27),
                                  #selector(netPrefChange(_:)))
        netIntervalDisplay = label(container, "x", NSRect(x: 183, y: 486, width: 54, height: 17), .center)
        netInterval = slider(container, NSRect(x: 19, y: 454, width: 515, height: 25),
                             0.5, 20, 2, 40, true, true, .regular,
                             #selector(liveUpdateInterval(_:)))
        netThroughput1KBound = checkbox(container, "Ignore values below 1K/s",
                                        NSRect(x: 163, y: 230, width: 317, height: 18),
                                        #selector(netPrefChange(_:)))
    }

    private func buildAboutTab() {
        let item = NSTabViewItem(identifier: "info.circle")
        item.label = LP("About")
        let tabView = NSView(frame: NSRect(x: 10, y: 33, width: 548, height: 606))
        tabView.autoresizingMask = [.width, .height]

        let scroll = NSScrollView(frame: NSRect(x: -3, y: 180, width: 554, height: 423))
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 554, height: 423))
        textView.minSize = NSSize(width: 0, height: 423)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.textContainer?.containerSize = NSSize(width: 554,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        aboutView = textView
        tabView.addSubview(scroll)

        let footer = NSView(frame: NSRect(x: -3, y: -3, width: 554, height: 185))
        footer.autoresizingMask = [.maxXMargin, .maxYMargin]
        tabView.addSubview(footer)

        _ = label(footer, "Color tint:", NSRect(x: 25, y: 142, width: 195, height: 16),
                  .right, 13, .labelColor)
        _ = label(footer, "original", NSRect(x: 233, y: 159, width: 109, height: 16),
                  .left, 13, .secondaryLabelColor)
        _ = label(footer, "Activity monitor:", NSRect(x: 25, y: 112, width: 195, height: 16),
                  .right, 13, .labelColor)
        activityMonitorPaneCheckbox = checkbox(footer, "Opens specific panes",
                                               NSRect(x: 230, y: 111, width: 306, height: 18),
                                               #selector(showAlertConcerningSystemEventsEtc(_:)))
        tintPercentageSlider = slider(footer, NSRect(x: 230, y: 136, width: 306, height: 28),
                                      0, 100, 10, 0, false, true, .regular,
                                      #selector(tintPercentageChanged(_:)))
        _ = label(footer, "pure black/white", NSRect(x: 427, y: 159, width: 109, height: 16),
                  .right, 13, .secondaryLabelColor)
        _ = label(footer, "Startup:", NSRect(x: 25, y: 82, width: 195, height: 16),
                  .right, 13, .labelColor)
        loginItemCheckbox = checkbox(footer, "Launch MenuMeters at login",
                                     NSRect(x: 230, y: 81, width: 306, height: 18),
                                     #selector(loginItemChanged(_:)))
        _ = label(footer, "Updates:", NSRect(x: 25, y: 52, width: 195, height: 16),
                  .right, 13, .labelColor)
        automaticUpdatesCheckbox = checkbox(footer, "Check for updates automatically",
                                            NSRect(x: 230, y: 51, width: 306, height: 18),
                                            #selector(automaticUpdatesChanged(_:)))
        checkForUpdatesButton = NSButton(title: LP("Check Now"), target: self,
                                         action: #selector(checkForUpdatesNow(_:)))
        checkForUpdatesButton.frame = NSRect(x: 224, y: 14, width: 140, height: 32)
        checkForUpdatesButton.font = .systemFont(ofSize: 13)
        footer.addSubview(checkForUpdatesButton)

        item.view = tabView
        prefTabs.addTabViewItem(item)
    }

    // MARK: - Control factories

    private func label(_ parent: NSView, _ key: String, _ frame: NSRect,
                       _ alignment: NSTextAlignment = .left, _ size: CGFloat = 13,
                       _ color: NSColor = .controlTextColor) -> NSTextField {
        let field = NSTextField(labelWithString: LP(key))
        field.frame = frame
        field.alignment = alignment
        field.font = .systemFont(ofSize: size)
        field.textColor = color
        field.lineBreakMode = .byClipping
        parent.addSubview(field)
        return field
    }

    private func checkbox(_ parent: NSView, _ key: String, _ frame: NSRect,
                          _ action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: LP(key), target: self, action: action)
        button.frame = frame
        button.font = .systemFont(ofSize: 13)
        parent.addSubview(button)
        return button
    }

    private func popup(_ parent: NSView, _ frame: NSRect, _ keys: [String],
                       _ selectedIndex: Int, _ action: Selector) -> NSPopUpButton {
        let button = NSPopUpButton(frame: frame, pullsDown: false)
        button.font = .systemFont(ofSize: 13)
        button.addItems(withTitles: keys.map(LP))
        if selectedIndex >= 0 && selectedIndex < keys.count {
            button.selectItem(at: selectedIndex)
        }
        button.target = self
        button.action = action
        parent.addSubview(button)
        return button
    }

    private func slider(_ parent: NSView, _ frame: NSRect, _ minValue: Double,
                        _ maxValue: Double, _ value: Double, _ tickMarks: Int,
                        _ tickOnly: Bool, _ continuous: Bool, _ size: NSControl.ControlSize,
                        _ action: Selector) -> NSSlider {
        let slider = NSSlider(frame: frame)
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.doubleValue = value
        slider.numberOfTickMarks = tickMarks
        slider.allowsTickMarkValuesOnly = tickOnly
        slider.isContinuous = continuous
        slider.controlSize = size
        slider.target = self
        slider.action = action
        parent.addSubview(slider)
        return slider
    }

    private func colorWell(_ parent: NSView, _ frame: NSRect, _ action: Selector) -> NSColorWell {
        let well = NSColorWell(frame: frame)
        well.supportsAlpha = true
        well.target = self
        well.action = action
        parent.addSubview(well)
        return well
    }

    private func separator(_ parent: NSView, _ frame: NSRect) {
        let box = NSBox(frame: frame)
        box.boxType = .separator
        parent.addSubview(box)
    }

    // MARK: - Toolbar

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "MenuMetersPreferencesToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window?.toolbar = toolbar
        window?.toolbarStyle = .preference
        prefTabs.tabViewType = .noTabsNoBorder
        prefTabs.delegate = self
        if let identifier = prefTabs.selectedTabViewItem?.identifier as? String {
            window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(identifier)
        }
    }

    private var tabToolbarIdentifiers: [NSToolbarItem.Identifier] {
        prefTabs.tabViewItems.compactMap {
            ($0.identifier as? String).map { NSToolbarItem.Identifier($0) }
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabToolbarIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabToolbarIdentifiers
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        tabToolbarIdentifiers
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tabItem = prefTabs.tabViewItems.first(where: {
            ($0.identifier as? String) == itemIdentifier.rawValue
        }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tabItem.label
        item.paletteLabel = tabItem.label
        item.image = NSImage(systemSymbolName: itemIdentifier.rawValue, accessibilityDescription: "")
        item.target = self
        item.action = #selector(toolbarSelection(_:))
        return item
    }

    @objc private func toolbarSelection(_ sender: NSToolbarItem) {
        guard let item = prefTabs.tabViewItems.first(where: {
            ($0.identifier as? String) == sender.itemIdentifier.rawValue
        }) else { return }
        prefTabs.selectTabViewItem(item)
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let identifier = tabViewItem?.identifier as? String else { return }
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(identifier)
    }

    // MARK: - Public actions

    @objc func openAbout(_ sender: Any?) {
        selectTab(4)
        promotePreferences()
    }

    func showPreferences() {
        promotePreferences()
    }

    private func promotePreferences() {
        ActivationPolicy.hold("preferences")
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func selectTab(_ index: Int) {
        guard index >= 0, index < prefTabs.numberOfTabViewItems else { return }
        prefTabs.selectTabViewItem(at: index)
    }

    @objc private func openPrefs(_ notification: Notification) {
        if let meter = notification.object as? MenuExtraBase {
            switch meter.bundleID {
            case MM.diskBundleID: selectTab(1)
            case MM.memBundleID: selectTab(2)
            case MM.netBundleID: selectTab(3)
            default: selectTab(0)
            }
        }
        promotePreferences()
    }

    @objc private func menuExtraUnloaded(_ notification: Notification) {
        guard let bundleID = notification.object as? String else { return }
        prefs.setMeterEnabled(bundleID, false)
        updateMeterToggles()
        if noMenuMeterLoaded {
            promotePreferences()
        }
    }

    @objc private func menuExtraChangedPrefs(_ notification: Notification?) {
        updateAllControls()
    }

    // MARK: - Window delegate

    func windowWillClose(_ notification: Notification) {
        if !noMenuMeterLoaded {
            ActivationPolicy.release("preferences")
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshPowerMateAvailability()
        updateLoginItemControl()
        updateUpdateControls()
        updateNetInterfaceMenu()
        updateAllControls()
    }

    // MARK: - General setup

    private func installObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(openPrefs(_:)), name: .openPref, object: nil)
        center.addObserver(self, selector: #selector(menuExtraUnloaded(_:)),
                           name: .menuExtraUnloaded, object: nil)
        center.addObserver(self, selector: #selector(menuExtraChangedPrefs(_:)),
                           name: Notification.Name(MM.prefsBundleID), object: MM.prefChange)
    }

    private func populateDiskImageSets() {
        diskImageSet.removeAllItems()
        diskImageSet.addItems(withTitles: Disk.imageSets.map { imageSetName($0) })
        diskImageSet.selectItem(at: prefs.diskImageset)
    }

    private func configureIntervalFormatters() {
        let formatter = NumberFormatter()
        formatter.localizesFormat = true
        formatter.format = "###0.0\u{2009}s"
        cpuIntervalDisplay.formatter = formatter
        diskIntervalDisplay.formatter = formatter
        netIntervalDisplay.formatter = formatter
    }

    private func updateMeterToggles() {
        cpuMeterToggle?.state = prefs.meterEnabled(MM.cpuBundleID) ? .on : .off
        diskMeterToggle?.state = prefs.meterEnabled(MM.diskBundleID) ? .on : .off
        memMeterToggle?.state = prefs.meterEnabled(MM.memBundleID) ? .on : .off
        netMeterToggle?.state = prefs.meterEnabled(MM.netBundleID) ? .on : .off
    }

    private var noMenuMeterLoaded: Bool {
        !MM.allMeterIDs.contains { prefs.meterEnabled($0) }
    }

    private func setMeterEnabled(_ bundleID: String, _ enabled: Bool) {
        prefs.setMeterEnabled(bundleID, enabled)
        NotificationCenter.default.post(name: Notification.Name(bundleID), object: MM.prefChange)
        updateMeterToggles()
        if !enabled && noMenuMeterLoaded {
            promotePreferences()
        }
    }

    /// Delivered even to a disabled meter: it may still own hardware, such as
    /// the PowerMate, that has to follow the change.
    private func notifyMeter(_ bundleID: String) {
        NotificationCenter.default.post(name: Notification.Name(bundleID), object: MM.prefChange)
    }

    private func updateAllControls() {
        updateMeterToggles()
        updateCPUControls()
        updateDiskControls()
        updateMemoryControls()
        updateNetworkControls()
    }

    private func isSender(_ sender: Any?, _ control: NSControl) -> Bool {
        (sender as? NSControl) === control
    }

    private func updateTemperatureSensors() {
        cpuTemperatureSensor.removeAllItems()
        guard let sensorNames = TemperatureReader.sensorNames(), !sensorNames.isEmpty else {
            cpuTemperatureSensor.isEnabled = false
            return
        }
        for name in sensorNames {
            let item = NSMenuItem(title: TemperatureReader.displayName(for: name),
                                  action: nil, keyEquivalent: "")
            item.toolTip = name
            cpuTemperatureSensor.menu?.addItem(item)
        }

        let saved = prefs.cpuTemperatureSensor
        let resolved = saved == "CPUTemperatureSensorDefault"
            ? TemperatureReader.defaultSensor() : saved
        if let resolved,
           let index = cpuTemperatureSensor.itemArray.firstIndex(where: { $0.toolTip == resolved }) {
            cpuTemperatureSensor.selectItem(at: index)
            cpuTemperatureSensor.isEnabled = true
            return
        }

        prefs.cpuTemperatureSensor = "CPUTemperatureSensorDefault"
        if let fallback = TemperatureReader.defaultSensor(),
           let index = cpuTemperatureSensor.itemArray.firstIndex(where: { $0.toolTip == fallback }) {
            cpuTemperatureSensor.selectItem(at: index)
        } else if cpuTemperatureSensor.numberOfItems > 0 {
            cpuTemperatureSensor.selectItem(at: 0)
        }
        cpuTemperatureSensor.isEnabled = true
    }

    private func refreshPowerMateAvailability() {
        powerMateAvailable = PowerMate.isAttached()
        cpuPowerMate?.isEnabled = powerMateAvailable
        cpuPowerMateMode?.isEnabled = powerMateAvailable
    }

    private func setupAboutTab() {
        guard let url = Bundle.main.url(forResource: aboutFile, withExtension: "rtf"),
              let text = try? NSMutableAttributedString(url: url, options: [:],
                                                        documentAttributes: nil) else { return }
        text.addAttribute(.foregroundColor, value: NSColor.textColor,
                          range: NSRange(location: 0, length: text.length))
        aboutView.textStorage?.append(text)
        aboutView.textContainerInset = NSSize(width: 12, height: 8)
    }

    private func setupAboutControls() {
        tintPercentageSlider.doubleValue = prefs.tintPercentage
        activityMonitorPaneCheckbox.state = prefs.activityMonitorSpecificPanes ? .on : .off
        updateLoginItemControl()
        updateUpdateControls()
    }

    /// The login item can also be changed in System Settings, so this follows
    /// the system's state rather than a preference of our own.
    private func updateLoginItemControl() {
        loginItemCheckbox.state = LoginItem.isEnabled() ? .on : .off
    }

    @objc private func loginItemChanged(_ sender: Any?) {
        let enabled = loginItemCheckbox.state == .on
        LoginItem.markConfigured()
        LoginItem.setEnabled(enabled)
        if enabled && SMAppService.mainApp.status == .requiresApproval {
            // Turned off in System Settings before: only the user can turn it
            // back on there.
            SMAppService.openSystemSettingsLoginItems()
        }
        updateLoginItemControl()
    }

    /// Sparkle owns the automatic-check setting and knows when a check is
    /// already running; the controls only mirror it.
    private func updateUpdateControls() {
        guard let automaticUpdatesCheckbox, let checkForUpdatesButton else { return }
        automaticUpdatesCheckbox.isEnabled = updater != nil
        automaticUpdatesCheckbox.state = updater?.automaticallyChecksForUpdates == true ? .on : .off
        checkForUpdatesButton.isEnabled = updater?.canCheckForUpdates == true
    }

    @objc private func automaticUpdatesChanged(_ sender: Any?) {
        updater?.automaticallyChecksForUpdates = automaticUpdatesCheckbox.state == .on
        updateUpdateControls()
    }

    @objc private func checkForUpdatesNow(_ sender: Any?) {
        updater?.checkForUpdates()
    }

    @objc private func tintPercentageChanged(_ sender: Any?) {
        prefs.tintPercentage = tintPercentageSlider.doubleValue
    }

    @objc private func showAlertConcerningSystemEventsEtc(_ sender: Any?) {
        let enabled = activityMonitorPaneCheckbox.state == .on
        prefs.activityMonitorSpecificPanes = enabled
        guard enabled else { return }

        let alert = NSAlert()
        alert.messageText = "MenuMeters needs Accessibility permission"
        alert.addButton(withTitle: "OK")
        alert.informativeText = "To switch to a specific Activity Monitor pane, MenuMeters simulates a click on the pane's toolbar button. macOS will ask you to allow MenuMeters to control your computer using Accessibility features. You can change this later in System Settings > Privacy & Security > Accessibility."
        alert.runModal()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Per-meter preference updates

    @objc private func liveUpdateInterval(_ sender: Any?) {
        if isSender(sender, cpuInterval) {
            prefs.cpuInterval = cpuInterval.doubleValue
            cpuIntervalDisplay.doubleValue = cpuInterval.doubleValue
            notifyMeter(MM.cpuBundleID)
        } else if isSender(sender, diskInterval) {
            prefs.diskInterval = diskInterval.doubleValue
            diskIntervalDisplay.doubleValue = diskInterval.doubleValue
            notifyMeter(MM.diskBundleID)
        } else if isSender(sender, memInterval) {
            prefs.memInterval = memInterval.doubleValue
            memIntervalDisplay.intValue = Int32(memInterval.doubleValue)
            notifyMeter(MM.memBundleID)
        } else if isSender(sender, netInterval) {
            prefs.netInterval = netInterval.doubleValue
            netIntervalDisplay.doubleValue = netInterval.doubleValue
            notifyMeter(MM.netBundleID)
        }
    }

    @objc private func cpuPrefChange(_ sender: Any?) {
        if isSender(sender, cpuMeterToggle) {
            setMeterEnabled(MM.cpuBundleID, cpuMeterToggle.state == .on)
            return
        }

        if isSender(sender, cpuPercentage) || isSender(sender, cpuGraph)
            || isSender(sender, cpuThermometer) || isSender(sender, cpuHorizontalThermometer) {
            prefs.cpuDisplayMode = displayModeFromControls()
        } else if isSender(sender, cpuTemperatureToggle) {
            prefs.cpuShowTemperature = cpuTemperatureToggle.state == .on
        } else if isSender(sender, cpuTemperatureUnit) {
            prefs.cpuTemperatureUnit = cpuTemperatureUnit.indexOfSelectedItem
        } else if isSender(sender, cpuTemperatureSensor) {
            let sensor = cpuTemperatureSensor.selectedItem?.toolTip ?? ""
            prefs.cpuTemperatureSensor = sensor == TemperatureReader.defaultSensor()
                ? "CPUTemperatureSensorDefault" : sensor
        } else if isSender(sender, cpuInterval) {
            prefs.cpuInterval = cpuInterval.doubleValue
        } else if isSender(sender, cpuPercentMode) {
            prefs.cpuPercentDisplay = cpuPercentMode.indexOfSelectedItem
        } else if isSender(sender, cpuMaxProcessCount) {
            prefs.cpuMaxProcessCount = Int(cpuMaxProcessCount.doubleValue.rounded())
        } else if isSender(sender, cpuGraphWidth) {
            prefs.cpuGraphLength = Int(cpuGraphWidth.doubleValue.rounded())
        } else if isSender(sender, cpuHorizontalRows) {
            prefs.cpuHorizontalRows = Int(cpuHorizontalRows.doubleValue.rounded())
        } else if isSender(sender, cpuMenuWidth) {
            prefs.cpuMenuWidth = Int(cpuMenuWidth.doubleValue.rounded())
        } else if isSender(sender, cpuMultipleCPU) {
            applyCPUType(index: cpuMultipleCPU.indexOfSelectedItem)
        } else if isSender(sender, cpuPowerMate) {
            prefs.cpuPowerMate = cpuPowerMate.state == .on
        } else if isSender(sender, cpuPowerMateMode) {
            prefs.cpuPowerMateMode = cpuPowerMateMode.indexOfSelectedItem
        } else if isSender(sender, cpuUserColor) {
            prefs.cpuUserColor = cpuUserColor.color
        } else if isSender(sender, cpuSystemColor) {
            prefs.cpuSystemColor = cpuSystemColor.color
        } else if isSender(sender, cpuTemperatureColor) {
            prefs.cpuTemperatureColor = cpuTemperatureColor.color
        } else if sender == nil && !isMultiProcessor {
            prefs.cpuAvgAllProcs = false
            prefs.cpuSumAllProcsPercent = false
        }

        updateCPUControls()
        notifyMeter(MM.cpuBundleID)
    }

    private func displayModeFromControls() -> Int {
        var mode = 0
        if cpuPercentage.state == .on { mode |= CPU.displayPercent }
        if cpuGraph.state == .on { mode |= CPU.displayGraph }
        if cpuThermometer.state == .on { mode |= CPU.displayThermometer }
        if cpuHorizontalThermometer.state == .on { mode |= CPU.displayHorizontalThermometer }
        return mode
    }

    private func applyCPUType(index: Int) {
        prefs.cpuAvgLowerHalfProcs = index == 1
        prefs.cpuAvgAllProcs = index == 2 || index == 3
        prefs.cpuSumAllProcsPercent = index == 3
        prefs.cpuSortByUsage = index == 4
    }

    private var isMultiProcessor: Bool {
        ProcessInfo.processInfo.processorCount > 1
    }

    private func updateCPUControls() {
        let mode = prefs.cpuDisplayMode
        cpuPercentage.state = mode & CPU.displayPercent != 0 ? .on : .off
        cpuGraph.state = mode & CPU.displayGraph != 0 ? .on : .off
        cpuThermometer.state = mode & CPU.displayThermometer != 0 ? .on : .off
        cpuHorizontalThermometer.state = mode & CPU.displayHorizontalThermometer != 0 ? .on : .off

        let horizontal = cpuHorizontalThermometer.state == .on
        cpuPercentage.isEnabled = !horizontal
        cpuGraph.isEnabled = !horizontal
        cpuThermometer.isEnabled = !horizontal

        cpuTemperatureToggle.state = prefs.cpuShowTemperature ? .on : .off
        cpuTemperatureUnit.selectItem(at: prefs.cpuTemperatureUnit)
        cpuInterval.doubleValue = prefs.cpuInterval
        cpuPercentMode.selectItem(at: prefs.cpuPercentDisplay)
        cpuMaxProcessCount.doubleValue = Double(prefs.cpuMaxProcessCount)
        cpuMaxProcessCountCountLabel.stringValue = String(format: LP("(%d)"), prefs.cpuMaxProcessCount)
        cpuGraphWidth.doubleValue = Double(prefs.cpuGraphLength)
        cpuHorizontalRows.doubleValue = Double(prefs.cpuHorizontalRows)
        cpuMenuWidth.doubleValue = Double(prefs.cpuMenuWidth)
        cpuMultipleCPU.selectItem(at: cpuTypeIndex)
        cpuPowerMate.state = prefs.cpuPowerMate ? .on : .off
        cpuPowerMateMode.selectItem(at: prefs.cpuPowerMateMode)
        cpuUserColor.color = prefs.cpuUserColor
        cpuSystemColor.color = prefs.cpuSystemColor
        cpuTemperatureColor.color = prefs.cpuTemperatureColor
        cpuIntervalDisplay.doubleValue = cpuInterval.doubleValue

        cpuGraphWidth.isEnabled = cpuGraph.state == .on
        cpuGraphWidthLabel.textColor = cpuGraphWidth.isEnabled ? .controlTextColor : .disabledControlTextColor
        cpuHorizontalRows.isEnabled = horizontal
        cpuHorizontalRowsLabel.textColor = horizontal ? .controlTextColor : .disabledControlTextColor
        cpuMenuWidth.isEnabled = horizontal
        cpuMenuWidthLabel.textColor = horizontal ? .controlTextColor : .disabledControlTextColor
        cpuUserColorLabel?.textColor = .controlTextColor
        cpuSystemColorLabel?.textColor = .controlTextColor
    }

    private var cpuTypeIndex: Int {
        if prefs.cpuSortByUsage { return 4 }
        if prefs.cpuSumAllProcsPercent { return 3 }
        if prefs.cpuAvgAllProcs { return 2 }
        if prefs.cpuAvgLowerHalfProcs { return 1 }
        return 0
    }

    @objc private func diskPrefChange(_ sender: Any?) {
        if isSender(sender, diskMeterToggle) {
            setMeterEnabled(MM.diskBundleID, diskMeterToggle.state == .on)
            return
        }
        if isSender(sender, diskImageSet) {
            prefs.diskImageset = diskImageSet.indexOfSelectedItem
        } else if isSender(sender, diskInterval) {
            prefs.diskInterval = diskInterval.doubleValue
        } else if isSender(sender, diskSelectMode) {
            prefs.diskSelectMode = diskSelectMode.indexOfSelectedItem
        }
        updateDiskControls()
        notifyMeter(MM.diskBundleID)
    }

    private func updateDiskControls() {
        diskImageSet.selectItem(at: prefs.diskImageset)
        diskInterval.doubleValue = prefs.diskInterval
        diskIntervalDisplay.doubleValue = diskInterval.doubleValue
        diskSelectMode.selectItem(at: prefs.diskSelectMode)
    }

    @objc private func memPrefChange(_ sender: Any?) {
        if isSender(sender, memMeterToggle) {
            setMeterEnabled(MM.memBundleID, memMeterToggle.state == .on)
            return
        }
        if isSender(sender, memDisplayMode) {
            prefs.memDisplayMode = memDisplayMode.indexOfSelectedItem + 1
        } else if isSender(sender, memInterval) {
            prefs.memInterval = memInterval.doubleValue
        } else if isSender(sender, memFreeUsedLabeling) {
            prefs.memUsedFreeLabel = memFreeUsedLabeling.state == .on
        } else if isSender(sender, memPageIndicator) {
            prefs.memPageIndicator = memPageIndicator.state == .on
        } else if isSender(sender, memPressureMode) {
            prefs.memPressure = memPressureMode.state == .on
        } else if isSender(sender, memGraphWidth) {
            prefs.memGraphLength = Int(memGraphWidth.doubleValue.rounded())
        } else if isSender(sender, memActiveColor) {
            prefs.memActiveColor = memActiveColor.color
        } else if isSender(sender, memInactiveColor) {
            prefs.memInactiveColor = memInactiveColor.color
        } else if isSender(sender, memWiredColor) {
            prefs.memWireColor = memWiredColor.color
        } else if isSender(sender, memCompressedColor) {
            prefs.memCompressedColor = memCompressedColor.color
        } else if isSender(sender, memFreeColor) {
            prefs.memFreeColor = memFreeColor.color
        } else if isSender(sender, memUsedColor) {
            prefs.memUsedColor = memUsedColor.color
        } else if isSender(sender, memPageinColor) {
            prefs.memPageInColor = memPageinColor.color
        } else if isSender(sender, memPageoutColor) {
            prefs.memPageOutColor = memPageoutColor.color
        }
        updateMemoryControls()
        notifyMeter(MM.memBundleID)
    }

    private func updateMemoryControls() {
        let mode = prefs.memDisplayMode
        memDisplayMode.selectItem(at: max(0, mode - 1))
        memInterval.doubleValue = prefs.memInterval
        memFreeUsedLabeling.state = prefs.memUsedFreeLabel ? .on : .off
        memPageIndicator.state = prefs.memPageIndicator ? .on : .off
        memPressureMode.state = prefs.memPressure ? .on : .off
        memGraphWidth.doubleValue = Double(prefs.memGraphLength)
        memActiveColor.color = prefs.memActiveColor
        memInactiveColor.color = prefs.memInactiveColor
        memWiredColor.color = prefs.memWireColor
        memCompressedColor.color = prefs.memCompressedColor
        memFreeColor.color = prefs.memFreeColor
        memUsedColor.color = prefs.memUsedColor
        memPageinColor.color = prefs.memPageInColor
        memPageoutColor.color = prefs.memPageOutColor
        memIntervalDisplay.intValue = Int32(memInterval.doubleValue.rounded())

        memFreeUsedLabeling.isEnabled = mode == Mem.displayNumber
        memGraphWidth.isEnabled = mode == Mem.displayGraph
        memGraphWidthLabel.textColor = memGraphWidth.isEnabled
            ? .controlTextColor : .disabledControlTextColor

        let paging = memPageIndicator.state == .on
        memPageinColor.isEnabled = paging
        memPageoutColor.isEnabled = paging
        memPageinColorLabel.textColor = paging ? .controlTextColor : .disabledControlTextColor
        memPageoutColorLabel.textColor = paging ? .controlTextColor : .disabledControlTextColor
    }

    @objc private func netPrefChange(_ sender: Any?) {
        if isSender(sender, netMeterToggle) {
            setMeterEnabled(MM.netBundleID, netMeterToggle.state == .on)
            return
        }
        if isSender(sender, netDisplayMode) {
            prefs.netDisplayMode = netDisplayMode.indexOfSelectedItem + 1
        } else if isSender(sender, netDisplayOrientation) {
            prefs.netDisplayOrientation = netDisplayOrientation.indexOfSelectedItem
        } else if isSender(sender, netScaleMode) {
            prefs.netScaleMode = netScaleMode.indexOfSelectedItem
        } else if isSender(sender, netScaleCalc) {
            prefs.netScaleCalc = netScaleCalc.indexOfSelectedItem
        } else if isSender(sender, netInterval) {
            prefs.netInterval = netInterval.doubleValue
        } else if isSender(sender, netThroughputLabeling) {
            prefs.netThroughputLabel = netThroughputLabeling.state == .on
        } else if isSender(sender, netThroughput1KBound) {
            prefs.netThroughput1KBound = netThroughput1KBound.state == .on
        } else if isSender(sender, netThroughputBits) {
            prefs.netThroughputBits = netThroughputBits.state == .on
        } else if isSender(sender, netGraphStyle) {
            prefs.netGraphStyle = netGraphStyle.indexOfSelectedItem
        } else if isSender(sender, netGraphWidth) {
            prefs.netGraphLength = Int(netGraphWidth.doubleValue.rounded())
        } else if isSender(sender, netTxColor) {
            prefs.netTransmitColor = netTxColor.color
        } else if isSender(sender, netRxColor) {
            prefs.netReceiveColor = netRxColor.color
        } else if isSender(sender, netInactiveColor) {
            prefs.netInactiveColor = netInactiveColor.color
        } else if isSender(sender, netPreferInterface) {
            if netPreferInterface.indexOfSelectedItem == 0 {
                prefs.netPreferInterface = MM.primaryInterface
            } else if let device = netPreferInterface.selectedItem?.representedObject as? String {
                prefs.netPreferInterface = device
            } else {
                prefs.netPreferInterface = MM.primaryInterface
            }
        }
        updateNetworkControls()
        notifyMeter(MM.netBundleID)
    }

    private func updateNetworkControls() {
        let mode = prefs.netDisplayMode
        netDisplayMode.selectItem(at: max(0, mode - 1))
        netDisplayOrientation.selectItem(at: prefs.netDisplayOrientation)
        netScaleMode.selectItem(at: prefs.netScaleMode)
        netScaleCalc.selectItem(at: prefs.netScaleCalc)
        netInterval.doubleValue = prefs.netInterval
        netThroughputLabeling.state = prefs.netThroughputLabel ? .on : .off
        netThroughput1KBound.state = prefs.netThroughput1KBound ? .on : .off
        netThroughputBits.state = prefs.netThroughputBits ? .on : .off
        netGraphStyle.selectItem(at: prefs.netGraphStyle)
        netGraphWidth.doubleValue = Double(prefs.netGraphLength)
        netTxColor.color = prefs.netTransmitColor
        netRxColor.color = prefs.netReceiveColor
        netInactiveColor.color = prefs.netInactiveColor
        netIntervalDisplay.doubleValue = netInterval.doubleValue

        if prefs.netPreferInterface == MM.primaryInterface {
            netPreferInterface.selectItem(at: 0)
        } else if let index = netPreferInterface.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == prefs.netPreferInterface
        }) {
            netPreferInterface.selectItem(at: index)
        } else {
            netPreferInterface.selectItem(at: 0)
            prefs.netPreferInterface = MM.primaryInterface
        }

        let throughput = mode & Net.displayThroughput != 0
        netThroughputLabeling.isEnabled = throughput
        netThroughput1KBound.isEnabled = throughput
        netThroughputBits.isEnabled = throughput

        let graph = mode & Net.displayGraph != 0
        netGraphStyle.isEnabled = graph
        netGraphWidth.isEnabled = graph
        netGraphStyleLabel.textColor = graph ? .controlTextColor : .disabledControlTextColor
        netGraphWidthLabel.textColor = graph ? .controlTextColor : .disabledControlTextColor

        let scaled = mode & Net.displayArrows != 0 || mode & Net.displayGraph != 0
        netScaleMode.isEnabled = scaled
        netScaleCalc.isEnabled = scaled
        netScaleModeLabel.textColor = scaled ? .controlTextColor : .disabledControlTextColor
        netScaleCalcLabel.textColor = scaled ? .controlTextColor : .disabledControlTextColor
    }

    private func updateNetInterfaceMenu() {
        while netPreferInterface.numberOfItems > 1 {
            netPreferInterface.removeItem(at: netPreferInterface.numberOfItems - 1)
        }

        for detail in netConfig.interfaceDetails() {
            guard let device = detail.deviceName ?? detail.pppDeviceName else { continue }
            let title: String
            if let ppp = detail.pppDeviceName, ppp != device {
                title = "\(detail.name) (\(device), \(ppp))"
            } else {
                title = "\(detail.name) (\(device))"
            }
            if let item = netPreferInterface.menu?.addItem(withTitle: title, action: nil, keyEquivalent: "") {
                item.representedObject = device
            }
        }

        let preferred = prefs.netPreferInterface
        if preferred != MM.primaryInterface,
           let index = netPreferInterface.itemArray.firstIndex(where: {
               ($0.representedObject as? String) == preferred
           }) {
            netPreferInterface.selectItem(at: index)
        } else if preferred != MM.primaryInterface {
            netPreferInterface.selectItem(at: 0)
            prefs.netPreferInterface = MM.primaryInterface
        } else {
            netPreferInterface.selectItem(at: 0)
        }
    }
}
