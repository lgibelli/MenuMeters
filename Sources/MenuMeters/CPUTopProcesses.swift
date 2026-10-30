//
//  CPUTopProcesses.swift
//  MenuMeters
//
//  Snapshot of the most CPU-intensive processes.
//
//  Copyright (c) 2018 Hofi
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
//  2026-10-30  Luca Gibelli: list every user's processes via /bin/ps, sampled off the main thread.
//

import Cocoa

struct ProcessListItem {
    let pid: pid_t
    let name: String
    let cpuPercent: Double
}

final class CPUTopProcesses {
    /// Called on the main thread after each new snapshot is published.
    var onUpdate: (() -> Void)?

    private let queue = DispatchQueue(label: "MenuMeters.CPUTopProcesses", qos: .utility)
    // Main thread only.
    private var processes: [ProcessListItem] = []
    private var sampling = false

    /// Samples in the background and publishes the result on the main thread.
    /// Call on the main thread; a call while a sample is running is ignored.
    func startUpdateProcessList() {
        guard !sampling else { return }
        sampling = true
        queue.async { [weak self] in
            let entries = Self.sampleProcesses()
            DispatchQueue.main.async {
                guard let self else { return }
                self.sampling = false
                guard let entries else { return }
                self.processes = entries
                self.onUpdate?()
            }
        }
    }

    func stopUpdateProcessList() {
        // Each sample is a single ps run; keep the last result for the next open.
    }

    func runningProcesses(byCPUUsage maximum: Int) -> [ProcessListItem] {
        Array(processes.prefix(max(0, maximum)))
    }

    // MARK: - Sampling

    /// Runs the setuid `/bin/ps` (no shell): libproc cannot read the CPU time
    /// of other users' and root's processes, which are often the busiest.
    /// `pcpu` is the kernel's decaying average of recent usage, so one run is
    /// a complete sample.
    private static func sampleProcesses() -> [ProcessListItem]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // -ww: never cut names to a terminal width; -c: executable name only.
        process.arguments = ["-ww", "-A", "-c", "-o", "pid=,pcpu=,comm="]
        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("MenuMeters: unable to run ps: %@", error.localizedDescription)
            return nil
        }
        // Terminating a stuck ps closes its end of the pipe, which ends the
        // read below.
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }

        // Bounded UTF-8 conversion: the length comes from the pipe, and
        // malformed names are repaired rather than trusted.
        let output = String(decoding: data, as: UTF8.self)
        var entries: [ProcessListItem] = []
        for line in output.split(separator: "\n") {
            // "  461  31.2 WindowServer": the name is last and may contain spaces.
            let fields = line.split(separator: " ", maxSplits: 2)
            guard fields.count == 3, let pid = pid_t(fields[0]), let percent = Double(fields[1]),
                  pid != process.processIdentifier else { continue }
            entries.append(ProcessListItem(pid: pid,
                                           name: normalizedCommand(String(fields[2])),
                                           cpuPercent: percent))
        }
        return entries.sorted {
            if $0.cpuPercent != $1.cpuPercent { return $0.cpuPercent > $1.cpuPercent }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    private static func normalizedCommand(_ name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<2 where result.hasPrefix("-") {
            result.removeFirst()
        }
        return result
    }
}
