//
//  DiskSpace.swift
//  MenuMeters
//
//  Volume list and free-space statistics.
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
//  2026-10-30  Luca Gibelli: list only browsable local volumes, without blocking on network mounts.
//

import Cocoa

struct DiskSpaceInfo {
    let name: String
    let path: String
    let device: String
    let fileSystem: String
    let icon: NSImage?
    let total: String
    let free: String
    let used: String
}

final class DiskSpace {
    private let localFileSystems: Set<String> = [
        "hfs", "apfs", "ufs", "msdos", "exfat", "ntfs", "cd9660", "cddafs", "udf"
    ]
    private let spaceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.localizesFormat = true
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    var useBaseTen = false

    func diskSpaceData() -> [DiskSpaceInfo] {
        // MNT_NOWAIT returns the kernel's cached list instead of asking every
        // file system, so an unreachable network server cannot block us.
        var mountInfo: UnsafeMutablePointer<statfs>?
        let mountCount = getmntinfo(&mountInfo, MNT_NOWAIT)
        guard mountCount > 0, let mountInfo else { return [] }

        var volumes: [DiskSpaceInfo] = []
        for index in 0..<Int(mountCount) {
            let cached = mountInfo[index]
            let fileSystem = cString(cached.f_fstypename)
            // Hidden system volumes (/System/Volumes/*, Recovery, ...) are
            // mounted "nobrowse", and Finder does not list them either.
            guard localFileSystems.contains(fileSystem),
                  cached.f_flags & UInt32(MNT_DONTBROWSE) == 0 else { continue }

            // Refresh the cached numbers, for local volumes only. Skip the
            // volume if it was unmounted, or something else mounted there,
            // since the list was taken.
            let path = cString(cached.f_mntonname)
            var mount = statfs()
            guard statfs(path, &mount) == 0, cString(mount.f_mntonname) == path,
                  cString(mount.f_fstypename) == fileSystem,
                  mount.f_flags & UInt32(MNT_DONTBROWSE) == 0 else { continue }

            let url = URL(fileURLWithPath: path, isDirectory: true)
            let volumeName = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
            let name = volumeName ?? url.lastPathComponent

            let blockSize = Double(mount.f_bsize)
            let total = Double(mount.f_blocks) * blockSize
            let free = Double(mount.f_bavail) * blockSize
            let used = (Double(mount.f_blocks) - Double(mount.f_bavail)) * blockSize

            volumes.append(DiskSpaceInfo(
                name: name,
                path: path,
                device: cString(mount.f_mntfromname),
                fileSystem: fileSystem,
                icon: NSWorkspace.shared.icon(forFile: path),
                total: String(format: L("%@ Total"), spaceString(total)),
                free: String(format: L("%@ Free"), spaceString(free)),
                used: String(format: L("%@ Used"), spaceString(used))
            ))
        }

        // Device order is stable and matches users' expectations better than
        // mount order, which changes as volumes are mounted and unmounted.
        return volumes.sorted { $0.device < $1.device }
    }

    private func spaceString(_ space: Double) -> String {
        let base: Double = useBaseTen ? 1000 : 1024
        let unit: String
        let divisor: Double
        if space > base * base * base {
            divisor = base * base * base
            unit = "GB"
        } else if space > base * base {
            divisor = base * base
            unit = "MB"
        } else {
            divisor = base
            unit = "KB"
        }
        let number = spaceFormatter.string(from: NSNumber(value: space / divisor)) ?? "0.00"
        return number + L(unit)
    }

    /// Converts a fixed-size C char array, stopping at the first NUL or at the
    /// end of the array, whichever comes first.
    private func cString<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
