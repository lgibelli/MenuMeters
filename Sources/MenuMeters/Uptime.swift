//
//  Uptime.swift
//  MenuMeters
//
//  Reader for the system uptime.
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
//  2026-10-30  Luca Gibelli: restored the license notice.
//

import Cocoa

enum Uptime {
    static func string() -> String {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0 else {
            return String(format: L("%02ld:%02ld:%02ld"), 0, 0, 0)
        }

        var remaining = max(0, time(nil) - bootTime.tv_sec)
        let days = remaining / 86_400
        remaining %= 86_400
        let hours = remaining / 3_600
        remaining %= 3_600
        let minutes = remaining / 60
        let seconds = remaining % 60

        if days > 1 {
            return String(format: L("%ld days %02ld:%02ld:%02ld"), days, hours, minutes, seconds)
        }
        if days == 1 {
            return String(format: L("%ld day %02ld:%02ld:%02ld"), days, hours, minutes, seconds)
        }
        return String(format: L("%02ld:%02ld:%02ld"), hours, minutes, seconds)
    }
}
