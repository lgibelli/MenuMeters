//
//  CPUStats.swift
//  MenuMeters
//
//  CPU description, load ticks and task statistics.
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
//  2026-10-30  Luca Gibelli: fixed the cpu_ticks state indexes, so load no longer reads ~100%.
//

import Cocoa
import IOKit
import IOKit.pwr_mgt

struct CPULoadSample {
    var system: Double = 0
    var user: Double = 0
}

final class CPUStats {
    let cpuName: String
    let clockSpeed: String
    let numberOfCPUs: UInt32
    let numberOfCores: UInt32
    let packageCount: UInt32

    private let machHost = mach_host_self()
    private var processorSet: processor_set_name_t = 0
    private var priorTicks: [processor_cpu_load_info_data_t] = []
    private let twoDigitFloatFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.localizesFormat = true
        formatter.format = "0.00"
        return formatter
    }()

    init() {
        cpuName = Self.prettyCPUName()
        clockSpeed = Self.clockSpeedString(formatter: twoDigitFloatFormatter)

        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        numberOfCPUs = sysctlbyname("hw.ncpu", &value, &size, nil, 0) == 0 && value > 0 ? UInt32(value) : 1

        value = 0
        size = MemoryLayout<Int32>.size
        let physical = sysctlbyname("hw.physicalcpu", &value, &size, nil, 0) == 0 && value > 0 ? UInt32(value) : 0
        numberOfCores = physical == 0 ? numberOfCPUs : physical

        value = 0
        size = MemoryLayout<Int32>.size
        let packages = sysctlbyname("hw.packages", &value, &size, nil, 0) == 0 && value > 0 ? UInt32(value) : 0
        packageCount = packages == 0 ? 1 : packages

        processor_set_default(machHost, &processorSet)

        var processorCount: natural_t = 0
        var tickInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let err = host_processor_info(machHost, PROCESSOR_CPU_LOAD_INFO, &processorCount, &tickInfo, &infoCount)
        if err == KERN_SUCCESS, let tickInfo {
            let ticks = UnsafeRawPointer(tickInfo)
                .bindMemory(to: processor_cpu_load_info_data_t.self, capacity: Int(processorCount))
            priorTicks = Array(UnsafeBufferPointer(start: ticks, count: Int(processorCount)))
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: tickInfo)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<natural_t>.size))
        }
    }

    // MARK: - Description

    private static func prettyCPUName() -> String {
        var buffer = [CChar](repeating: 0, count: 64)
        var size = buffer.count
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "???" }
        var name = String(cString: buffer)
        if let range = name.range(of: "@") { name = String(name[..<range.lowerBound]) }
        if let range = name.range(of: "CPU") { name = String(name[..<range.lowerBound]) }
        name = name.replacingOccurrences(of: "(TM)", with: "™")
            .replacingOccurrences(of: "(R)", with: "®")
        var machine = [CChar](repeating: 0, count: 64)
        var machineSize = machine.count
        if sysctlbyname("hw.machine", &machine, &machineSize, nil, 0) == 0 {
            name += " (\(String(cString: machine)))"
        }
        return name
    }

    private static func clockSpeedString(formatter: NumberFormatter) -> String {
        var clockRate: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        var mib: [Int32] = [CTL_HW, HW_CPU_FREQ]
        if sysctl(&mib, 2, &clockRate, &size, nil, 0) != 0 {
            let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                      IOServiceMatching("IOPlatformExpertDevice"))
            if service != 0 {
                if let data = IORegistryEntryCreateCFProperty(service, "clock-frequency" as CFString,
                                                              kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                   data.count >= 4 {
                    clockRate = data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).byteSwapped } * 1000
                }
                IOObjectRelease(service)
            }
        }
        if clockRate > 1_000_000_000 {
            let ghz = Double(clockRate) / 1_000_000_000
            let text = formatter.string(from: NSNumber(value: ghz)) ?? String(format: "%.2f", ghz)
            return "\(text)GHz"
        }
        return "\(clockRate / 1_000_000)MHz"
    }

    var packages: String {
        packageCount == 1 ? "" : "\(packageCount)x "
    }

    var processorDescription: String {
        "\(packages)\(cpuName) @ \(clockSpeed)"
    }

    var coreDescription: String {
        var hyperinfo = ""
        if numberOfCPUs != numberOfCores {
            hyperinfo = String(format: L(" (%@ hyperthreads per core)"), String(numberOfCPUs / numberOfCores))
        }
        let cores = String(format: L("%@%@ physical cores"), packages, String(numberOfCores / packageCount))
        return cores + hyperinfo
    }

    // MARK: - Load information

    func currentProcessorTasks() -> String {
        var loadInfo = processor_set_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<processor_set_load_info>.size / MemoryLayout<natural_t>.size)
        let err = withUnsafeMutablePointer(to: &loadInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                processor_set_statistics(processorSet, PROCESSOR_SET_LOAD_INFO, $0, &count)
            }
        }
        guard err == KERN_SUCCESS else { return L(MM.noInfoMessage) }
        return String(format: L("%d tasks, %d threads"), loadInfo.task_count, loadInfo.thread_count)
    }

    func loadAverage() -> String {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return L(MM.noInfoMessage) }
        let values = loads.map { twoDigitFloatFormatter.string(from: NSNumber(value: $0)) ?? String(format: "%.2f", $0) }
        return String(format: L("%@, %@, %@"), values[0], values[1], values[2])
    }

    func currentLoad(sorted: Bool) -> [CPULoadSample] {
        var processorCount: natural_t = 0
        var tickInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let err = host_processor_info(machHost, PROCESSOR_CPU_LOAD_INFO, &processorCount, &tickInfo, &infoCount)
        guard err == KERN_SUCCESS, let tickInfo else { return [] }

        let ticks = UnsafeRawPointer(tickInfo)
            .bindMemory(to: processor_cpu_load_info_data_t.self, capacity: Int(processorCount))
        let count = Int(processorCount)

        if priorTicks.count != count {
            priorTicks = Array(repeating: processor_cpu_load_info_data_t(), count: count)
        }

        var loads: [CPULoadSample] = []
        loads.reserveCapacity(count)
        for index in 0..<count {
            let current = ticks[index]
            let prior = priorTicks[index]
            // cpu_ticks is indexed by CPU_STATE_USER (0), CPU_STATE_SYSTEM (1),
            // CPU_STATE_IDLE (2) and CPU_STATE_NICE (3); nice time counts as user.
            let user = UInt64(current.cpu_ticks.0 &- prior.cpu_ticks.0)
                + UInt64(current.cpu_ticks.3 &- prior.cpu_ticks.3)
            let system = UInt64(current.cpu_ticks.1 &- prior.cpu_ticks.1)
            let idle = UInt64(current.cpu_ticks.2 &- prior.cpu_ticks.2)
            let total = system + user + idle
            let normalize = total < 1 ? 1.0 : 1.0 / Double(total)
            loads.append(CPULoadSample(system: Double(system) * normalize,
                                       user: Double(user) * normalize))
        }

        priorTicks = Array(UnsafeBufferPointer(start: ticks, count: count))
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: tickInfo)),
                      vm_size_t(infoCount) * vm_size_t(MemoryLayout<natural_t>.size))

        guard sorted else { return loads }
        return loads.sorted { ($0.system + $0.user) > ($1.system + $1.user) }
    }

    // MARK: - Temperature and power

    func cpuProximityTemperature() -> Float {
        var sensor = Prefs.shared.cpuTemperatureSensor
        if sensor == "CPUTemperatureSensorDefault" {
            sensor = TemperatureReader.defaultSensor() ?? "TC0P"
        }
        return TemperatureReader.temperature(sensor: sensor)
    }

    func cpuPowerLimitStatus() -> String? {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyCPUPowerStatus(&unmanaged) == KERN_SUCCESS, let dictionary = unmanaged?.takeRetainedValue() else {
            return nil
        }
        let values = dictionary as NSDictionary
        guard let speed = values[kIOPMCPUPowerLimitProcessorSpeedKey],
              let scheduler = values[kIOPMCPUPowerLimitSchedulerTimeKey] else { return nil }
        return String(format: L("speed %@%%, scheduler %@%%"), "\(speed)", "\(scheduler)")
    }
}
