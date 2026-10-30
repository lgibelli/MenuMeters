//
//  MemStats.swift
//  MenuMeters
//
//  Virtual memory, swap and memory-pressure statistics.
//
//  Copyright (c) 2002-2014 Alex Harper
//  Copyright (c) 2015-2026 The MenuMeters contributors (see the Git history)
//  Swap usage and encryption based on a patch from Michael Nordmeyer.
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
//  2026-10-30  Luca Gibelli: report memory pressure, not availability; add read-only snapshots.
//

import Cocoa

struct MemSample {
    let totalMB: Double
    let freeMB: Double
    let usedMB: Double
    let activeMB: Double
    let inactiveMB: Double
    let wireMB: Double
    let freePageMB: Double
    let compressedMB: Double
    let uncompressedMB: Double
    let hits: UInt64
    let lookups: UInt64
    let pageIns: UInt64
    let pageOuts: UInt64
    let faults: UInt64
    let cowFaults: UInt64
    let deltaPageIns: UInt64
    let deltaPageOuts: UInt64
    /// Memory pressure in percent (0...100). The kernel reports the opposite,
    /// the percentage of memory available, as kern.memorystatus_level.
    let pressure: Int32
    let pressureLevel: Int32
}

struct SwapSample {
    let path: String
    let count: UInt32
    let peakCount: UInt32
    let sizeMB: UInt64
    let usedMB: UInt64
    let encrypted: Bool
}

final class MemStats {
    private let host = mach_host_self()
    private var lastPageIn: UInt64 = 0
    private var lastPageOut: UInt64 = 0
    private var peakSwapFiles: UInt32 = 0
    private var swapPath: String?
    private var swapPrefix = "swapfile"

    init() {
        // Prime the paging counters so the first graph sample has a delta.
        _ = memStats()
    }

    // MARK: - Memory

    /// Samples memory and advances the page-in/out baselines, so the next
    /// sample's deltas start here. Only the meter's timer should call this.
    func memStats() -> MemSample? {
        guard let sample = memSnapshot() else { return nil }
        lastPageIn = sample.pageIns
        lastPageOut = sample.pageOuts
        return sample
    }

    /// Samples memory without touching the page-in/out baselines; the deltas
    /// are relative to the last `memStats()` call.
    func memSnapshot() -> MemSample? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size /
                                           MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let deltaIn = stats.pageins >= lastPageIn ? stats.pageins - lastPageIn : stats.pageins
        let deltaOut = stats.pageouts >= lastPageOut ? stats.pageouts - lastPageOut : stats.pageouts

        let pageSize = UInt64(vm_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wire = UInt64(stats.wire_count) * pageSize
        let free = UInt64(stats.free_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let uncompressed = UInt64(stats.total_uncompressed_pages_in_compressor) * pageSize
        let mb = 1_048_576.0

        return MemSample(
            totalMB: Double(active + inactive + wire + free + compressed) / mb,
            freeMB: Double(free + inactive) / mb,
            usedMB: Double(active + wire + compressed) / mb,
            activeMB: Double(active) / mb,
            inactiveMB: Double(inactive) / mb,
            wireMB: Double(wire) / mb,
            freePageMB: Double(free) / mb,
            compressedMB: Double(compressed) / mb,
            uncompressedMB: Double(uncompressed) / mb,
            hits: stats.hits,
            lookups: stats.lookups,
            pageIns: stats.pageins,
            pageOuts: stats.pageouts,
            faults: stats.faults,
            cowFaults: stats.cow_faults,
            deltaPageIns: deltaIn,
            deltaPageOuts: deltaOut,
            pressure: sysctlInt("kern.memorystatus_level").map { 100 - min(100, max(0, $0)) } ?? 0,
            pressureLevel: sysctlInt("kern.memorystatus_vm_pressure_level") ?? 0
        )
    }

    // MARK: - Swap

    func swapStats() -> SwapSample? {
        if swapPath == nil {
            initializeSwapPath()
        }
        guard let swapPath else { return nil }

        var count: UInt32 = 0
        var size: UInt64 = 0
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: swapPath, isDirectory: &isDirectory), isDirectory.boolValue,
           let enumerator = fileManager.enumerator(atPath: swapPath) {
            for case let entry as String in enumerator where entry.hasPrefix(swapPrefix) {
                let fullPath = (swapPath as NSString).appendingPathComponent(entry)
                var entryIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: fullPath, isDirectory: &entryIsDirectory),
                      !entryIsDirectory.boolValue,
                      let attributes = try? fileManager.attributesOfItem(atPath: fullPath),
                      let fileSize = attributes[.size] as? NSNumber else { continue }
                count += 1
                size += fileSize.uint64Value
            }
        }
        peakSwapFiles = max(peakSwapFiles, count)

        var used: UInt64 = 0
        var encrypted = false
        var usage = xsw_usage()
        var usageSize = MemoryLayout<xsw_usage>.size
        var mib: [Int32] = [CTL_VM, 5] // VM_SWAPUSAGE
        if sysctl(&mib, 2, &usage, &usageSize, nil, 0) == 0 {
            used = usage.xsu_used
            encrypted = usage.xsu_encrypted != 0
        }

        return SwapSample(path: swapPath,
                          count: count,
                          peakCount: peakSwapFiles,
                          sizeMB: size / 1_048_576,
                          usedMB: used / 1_048_576,
                          encrypted: encrypted)
    }

    // MARK: - Private

    private func initializeSwapPath() {
        var buffer = [CChar](repeating: 0, count: 1024)
        var size = buffer.count
        if sysctlbyname("vm.swapfileprefix", &buffer, &size, nil, 0) == 0,
           let prefix = String(validatingUTF8: buffer), !prefix.isEmpty {
            swapPrefix = (prefix as NSString).lastPathComponent
            swapPath = (prefix as NSString).deletingLastPathComponent + "/"
        } else {
            swapPath = "/private/var/vm/"
            swapPrefix = "swapfile"
        }
    }

    private func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }
}
