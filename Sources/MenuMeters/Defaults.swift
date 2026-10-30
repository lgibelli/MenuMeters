//
//  Defaults.swift
//  MenuMeters
//
//  Typed access to the historical MenuMeters preference domain.
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
//  2026-10-30  Luca Gibelli: new bundle identifier, with a one-time migration of the old preferences.
//

import Cocoa

final class Prefs {
    static let shared = Prefs()

    let defaults: UserDefaults
    private let migrationKey = "migratedLegacyPreferences"

    private init() {
        defaults = .standard
        migrateIfNecessary()
    }

    // MARK: - Primitive access

    private func loadDouble(_ key: String, low: Double, high: Double, def: Double) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else { return def }
        let value = number.doubleValue
        if value.isNaN || floor(value * 100) < floor(low * 100) || ceil(value * 100) > ceil(high * 100) {
            defaults.set(def, forKey: key)
            return def
        }
        return value
    }

    private func loadInt(_ key: String, low: Int, high: Int, def: Int) -> Int {
        guard defaults.object(forKey: key) != nil else { return def }
        let value = defaults.integer(forKey: key)
        return (value < low || value > high) ? def : value
    }

    private func loadFlags(_ key: String, valid: Int, def: Int) -> Int {
        guard defaults.object(forKey: key) != nil else { return def }
        let value = defaults.integer(forKey: key)
        return (value | valid) == valid ? value : def
    }

    private func loadBool(_ key: String, default def: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? def : defaults.bool(forKey: key)
    }

    private func loadString(_ key: String, def: String) -> String {
        defaults.string(forKey: key) ?? def
    }

    private func loadColor(_ key: String, def: NSColor) -> NSColor {
        guard let data = defaults.data(forKey: key) else { return def }
        // NSArchiver data written by MenuMeters 2.1.6 and earlier cannot be
        // decoded by the keyed-unarchiver APIs; fall back to the default color.
        return (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)) ?? def
    }

    private func saveColor(_ key: String, _ color: NSColor) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) else { return }
        defaults.set(data, forKey: key)
    }

    func synchronize() { defaults.synchronize() }

    // MARK: - Meter enablement

    func meterEnabled(_ bundleID: String) -> Bool {
        loadBool(bundleID, default: true)
    }

    func setMeterEnabled(_ bundleID: String, _ enabled: Bool) {
        defaults.set(enabled, forKey: bundleID)
    }

    // MARK: - CPU

    var cpuInterval: Double {
        get { loadDouble("CPUInterval", low: 0.5, high: 10, def: 1) }
        set { defaults.set(newValue, forKey: "CPUInterval") }
    }

    var cpuDisplayMode: Int {
        get { loadFlags("CPUDisplayMode", valid: 15, def: 1) }
        set { defaults.set(newValue, forKey: "CPUDisplayMode") }
    }

    var cpuPercentDisplay: Int {
        get { loadInt("CPUPercentDisplayMode", low: 0, high: 2, def: 1) }
        set { defaults.set(newValue, forKey: "CPUPercentDisplayMode") }
    }

    var cpuMaxProcessCount: Int {
        get { loadInt("CPUMaxProcessCount", low: 0, high: 25, def: 5) }
        set { defaults.set(newValue, forKey: "CPUMaxProcessCount") }
    }

    var cpuGraphLength: Int {
        get { loadInt("CPUGraphLength", low: 11, high: 88, def: 33) }
        set { defaults.set(newValue, forKey: "CPUGraphLength") }
    }

    var cpuHorizontalRows: Int {
        get { loadInt("CPUHorizontalRows", low: 1, high: 8, def: 2) }
        set { defaults.set(newValue, forKey: "CPUHorizontalRows") }
    }

    var cpuMenuWidth: Int {
        get { loadInt("CPUMenuWidth", low: 60, high: 400, def: 120) }
        set { defaults.set(newValue, forKey: "CPUMenuWidth") }
    }

    var cpuAvgAllProcs: Bool {
        get { loadBool("CPUAverageMultiProcs", default: false) }
        set { defaults.set(newValue, forKey: "CPUAverageMultiProcs") }
    }

    var cpuSumAllProcsPercent: Bool {
        get { loadBool("CPUSumAllProcsPercent", default: false) }
        set { defaults.set(newValue, forKey: "CPUSumAllProcsPercent") }
    }

    var cpuAvgLowerHalfProcs: Bool {
        get { loadBool("CPUAverageLowerHalfProcs", default: false) }
        set { defaults.set(newValue, forKey: "CPUAverageLowerHalfProcs") }
    }

    var cpuSortByUsage: Bool {
        get { loadBool("CPUSortByUsage", default: false) }
        set { defaults.set(newValue, forKey: "CPUSortByUsage") }
    }

    var cpuPowerMate: Bool {
        get { loadBool("CPUPowerMate", default: false) }
        set { defaults.set(newValue, forKey: "CPUPowerMate") }
    }

    var cpuPowerMateMode: Int {
        get { loadInt("CPUPowerMateMode", low: 0, high: 3, def: 0) }
        set { defaults.set(newValue, forKey: "CPUPowerMateMode") }
    }

    var cpuShowTemperature: Bool {
        get { loadBool("CPUTemperature", default: true) }
        set { defaults.set(newValue, forKey: "CPUTemperature") }
    }

    var cpuTemperatureUnit: Int {
        get { loadInt("CPUTemperatureUnit", low: 0, high: 1, def: 0) }
        set { defaults.set(newValue, forKey: "CPUTemperatureUnit") }
    }

    var cpuTemperatureSensor: String {
        get { loadString("CPUTemperatureSensor", def: "CPUTemperatureSensorDefault") }
        set { defaults.set(newValue, forKey: "CPUTemperatureSensor") }
    }

    var cpuSystemColor: NSColor {
        get { loadColor("CPUSystemColor", def: .systemRed) }
        set { saveColor("CPUSystemColor", newValue) }
    }

    var cpuUserColor: NSColor {
        get { loadColor("CPUUserColor", def: .systemBlue) }
        set { saveColor("CPUUserColor", newValue) }
    }

    var cpuTemperatureColor: NSColor {
        get { loadColor("CPUTemperatureColor", def: .systemRed) }
        set { saveColor("CPUTemperatureColor", newValue) }
    }

    // MARK: - Disk

    var diskInterval: Double {
        get { loadDouble("DiskInterval", low: 0.1, high: 5, def: 0.3) }
        set { defaults.set(newValue, forKey: "DiskInterval") }
    }

    var diskImageset: Int {
        get { loadInt("DiskImageSet", low: 0, high: Disk.imageSets.count - 1, def: 0) }
        set { defaults.set(newValue, forKey: "DiskImageSet") }
    }

    var diskSelectMode: Int {
        get { loadInt("DiskSelectMode", low: 0, high: 1, def: 0) }
        set { defaults.set(newValue, forKey: "DiskSelectMode") }
    }

    var diskSpaceForceBaseTwo: Bool {
        get { loadBool("DiskSpaceForceBaseTwo", default: false) }
        set { defaults.set(newValue, forKey: "DiskSpaceForceBaseTwo") }
    }

    // MARK: - Memory

    var memInterval: Double {
        get { loadDouble("MemInterval", low: 1, high: 60, def: 10) }
        set { defaults.set(newValue, forKey: "MemInterval") }
    }

    var memDisplayMode: Int {
        get { loadInt("MemDisplayMode", low: 1, high: 4, def: 1) }
        set { defaults.set(newValue, forKey: "MemDisplayMode") }
    }

    var memUsedFreeLabel: Bool {
        get { loadBool("MemUsedFreeLabel", default: true) }
        set { defaults.set(newValue, forKey: "MemUsedFreeLabel") }
    }

    var memPageIndicator: Bool {
        get { loadBool("MemPagingIndicator", default: false) }
        set { defaults.set(newValue, forKey: "MemPagingIndicator") }
    }

    var memPressure: Bool {
        get { loadBool("MemPressure", default: false) }
        set { defaults.set(newValue, forKey: "MemPressure") }
    }

    var memGraphLength: Int {
        get { loadInt("MemGraphLength", low: 11, high: 88, def: 33) }
        set { defaults.set(newValue, forKey: "MemGraphLength") }
    }

    var memFreeColor: NSColor {
        get { loadColor("MemFreeColor", def: NSColor(deviceRed: 0, green: 0.5, blue: 0, alpha: 1)) }
        set { saveColor("MemFreeColor", newValue) }
    }

    var memUsedColor: NSColor {
        get { loadColor("MemUsedColor", def: NSColor(deviceRed: 0.5, green: 0, blue: 0, alpha: 1)) }
        set { saveColor("MemUsedColor", newValue) }
    }

    var memActiveColor: NSColor {
        get { loadColor("MemActiveColor", def: NSColor(deviceRed: 0.5, green: 1, blue: 0, alpha: 1)) }
        set { saveColor("MemActiveColor", newValue) }
    }

    var memInactiveColor: NSColor {
        get { loadColor("MemInactiveColor", def: NSColor(deviceRed: 0.7, green: 0.7, blue: 0.7, alpha: 1)) }
        set { saveColor("MemInactiveColor", newValue) }
    }

    var memWireColor: NSColor {
        get { loadColor("MemWireColor", def: NSColor(deviceRed: 0.4, green: 0.4, blue: 1, alpha: 1)) }
        set { saveColor("MemWireColor", newValue) }
    }

    var memCompressedColor: NSColor {
        get { loadColor("MemCompressedColor", def: NSColor(deviceRed: 0.5, green: 0, blue: 0.25, alpha: 1)) }
        set { saveColor("MemCompressedColor", newValue) }
    }

    var memPageInColor: NSColor {
        get { loadColor("MemPageInColor", def: .blue) }
        set { saveColor("MemPageInColor", newValue) }
    }

    var memPageOutColor: NSColor {
        get { loadColor("MemPageOutColor", def: .red) }
        set { saveColor("MemPageOutColor", newValue) }
    }

    // MARK: - Network

    var netInterval: Double {
        get { loadDouble("NetInterval", low: 0.5, high: 20, def: 2) }
        set { defaults.set(newValue, forKey: "NetInterval") }
    }

    var netDisplayMode: Int {
        get { loadFlags("NetDisplayMode", valid: 7, def: 1) }
        set { defaults.set(newValue, forKey: "NetDisplayMode") }
    }

    var netDisplayOrientation: Int {
        get { loadInt("NetOrientation", low: 0, high: 1, def: 0) }
        set { defaults.set(newValue, forKey: "NetOrientation") }
    }

    var netScaleMode: Int {
        get { loadInt("NetScaleMode", low: 0, high: 1, def: 0) }
        set { defaults.set(newValue, forKey: "NetScaleMode") }
    }

    var netScaleCalc: Int {
        get { loadInt("NetScaleCalc", low: 0, high: 3, def: 2) }
        set { defaults.set(newValue, forKey: "NetScaleCalc") }
    }

    var netThroughputLabel: Bool {
        get { loadBool("NetThroughputLabel", default: true) }
        set { defaults.set(newValue, forKey: "NetThroughputLabel") }
    }

    var netThroughput1KBound: Bool {
        get { loadBool("NetThroughput1KBound", default: false) }
        set { defaults.set(newValue, forKey: "NetThroughput1KBound") }
    }

    var netThroughputBits: Bool {
        get { loadBool("NetThroughputBits", default: false) }
        set { defaults.set(newValue, forKey: "NetThroughputBits") }
    }

    var netGraphStyle: Int {
        get { loadInt("NetGraphStyle", low: 0, high: 3, def: 0) }
        set { defaults.set(newValue, forKey: "NetGraphStyle") }
    }

    var netGraphLength: Int {
        get { loadInt("NetGraphLength", low: 11, high: 88, def: 33) }
        set { defaults.set(newValue, forKey: "NetGraphLength") }
    }

    var netTransmitColor: NSColor {
        get { loadColor("NetTransmitColor", def: .systemGreen) }
        set { saveColor("NetTransmitColor", newValue) }
    }

    var netReceiveColor: NSColor {
        get { loadColor("NetReceiveColor", def: .systemRed) }
        set { saveColor("NetReceiveColor", newValue) }
    }

    var netInactiveColor: NSColor {
        get { loadColor("NetInactiveColor", def: .secondaryLabelColor) }
        set { saveColor("NetInactiveColor", newValue) }
    }

    var netPreferInterface: String {
        get { loadString("NetPreferInterface", def: MM.primaryInterface) }
        set { defaults.set(newValue, forKey: "NetPreferInterface") }
    }

    // MARK: - General

    var tintPercentage: Double {
        get { defaults.object(forKey: "tintPercentage") == nil ? 10 : defaults.double(forKey: "tintPercentage") }
        set { defaults.set(newValue, forKey: "tintPercentage") }
    }

    var activityMonitorSpecificPanes: Bool {
        get { loadBool("activityMonitorOpenSpecificPanes", default: false) }
        set { defaults.set(newValue, forKey: "activityMonitorOpenSpecificPanes") }
    }

    // MARK: - Migration

    private func migrateIfNecessary() {
        guard !defaults.bool(forKey: migrationKey) else { return }
        // MenuMeters 2.x and 3.0 stored their settings under the previous
        // maintainer's bundle identifier. Take them over unchanged, except for
        // the state of the Sparkle updater some of those builds carried, and
        // whether the About text was shown: this version's text explains its
        // automatic updates, so it is shown once more.
        if let previous = defaults.persistentDomain(forName: MM.legacyAppBundleID), !previous.isEmpty {
            for (key, value) in previous where !key.hasPrefix("SU") && key != "WelcomePresented" {
                defaults.set(value, forKey: key)
            }
        } else {
            importRagingMenacePreferences()
        }
        defaults.set(true, forKey: migrationKey)
        defaults.synchronize()
    }

    private func importRagingMenacePreferences() {
        // Older MenuMeters stored its settings in com.ragingmenace.MenuMeters.
        // Copy every value that differs from the bundled defaults.
        let oldPath = NSString(string: "~/Library/Preferences/\(MM.defaultsDomain).plist").expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: oldPath),
              let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            return
        }
        let bundledDefaults: [String: Any] = {
            guard let url = Bundle.main.url(forResource: MM.defaultsDomain, withExtension: "plist"),
                  let data = try? Data(contentsOf: url),
                  let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else { return [:] }
            return dict
        }()
        for (key, value) in dict {
            if let defaultValue = bundledDefaults[key],
               (value as? NSObject)?.isEqual(defaultValue) == true {
                continue
            }
            defaults.set(value, forKey: key)
        }
    }
}
