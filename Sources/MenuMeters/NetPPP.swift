//
//  NetPPP.swift
//  MenuMeters
//
//  Best-effort PPP status (pppconfd) and connection control.
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
//  2026-10-30  Luca Gibelli: pppconfd socket gets SO_NOSIGPIPE, timeouts and reconnect; Connect no longer uses unsafeBitCast.
//

import Foundation
import Darwin
import SystemConfiguration

struct PPPStatusResult {
    let status: UInt32
    let timeElapsed: UInt32?
    let timeRemaining: UInt32?
    let inBytes: UInt32?
    let outBytes: UInt32?

    var isRunning: Bool { status == NetPPP.running }
}

final class NetPPP {
    static let shared = NetPPP()

    // PPP state machine from Apple PPPLib.
    static let idle: UInt32 = 0
    static let initialize: UInt32 = 1
    static let connectLink: UInt32 = 2
    static let stateReserved: UInt32 = 3
    static let establish: UInt32 = 4
    static let authenticate: UInt32 = 5
    static let callback: UInt32 = 6
    static let network: UInt32 = 7
    static let running: UInt32 = 8
    static let terminate: UInt32 = 9
    static let disconnectLink: UInt32 = 10
    static let holdoff: UInt32 = 11
    static let onHold: UInt32 = 12
    static let waitOnBusy: UInt32 = 13

    private static let socketPath = "/var/run/pppconfd"
    private static let maxReplyLength: UInt32 = 0x10000

    private var socketFD: Int32 = -1

    private init() {
        socketFD = Self.openSocket()
    }

    private static func openSocket() -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }

        // Requests run on the main thread: a vanished configd must not raise
        // SIGPIPE, and a stalled one must not block for long.
        var noSigPipe: Int32 = 1
        var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
                         socklen_t(MemoryLayout<Int32>.size)) == 0,
              setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout,
                         socklen_t(MemoryLayout<timeval>.size)) == 0,
              setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                         socklen_t(MemoryLayout<timeval>.size)) == 0 else {
            close(fd)
            return -1
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return -1
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { destination in
                for (index, byte) in pathBytes.enumerated() {
                    destination[index] = CChar(bitPattern: byte)
                }
                destination[pathBytes.count] = 0
            }
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0 {
            close(fd)
            return -1
        }
        return fd
    }

    deinit {
        closeSocket()
    }

    private func closeSocket() {
        if socketFD >= 0 { close(socketFD) }
        socketFD = -1
    }

    // MARK: - Status

    func status(forInterfaceName name: String) -> PPPStatusResult? {
        guard let link = linkID(forInterfaceName: name) else { return nil }
        return status(forLink: link)
    }

    func status(forServiceID serviceID: String) -> PPPStatusResult? {
        guard let link = linkID(forServiceID: serviceID) else { return nil }
        return status(forLink: link)
    }

    // MARK: - Control

    func connect(serviceID: String) {
        if startConnection(serviceID: serviceID) { return }
        guard let link = linkID(forServiceID: serviceID) else { return }
        _ = execute(type: 3 /* PPP_CONNECT */, link: link)
    }

    func disconnect(serviceID: String) {
        if stopConnection(serviceID: serviceID) { return }
        guard let link = linkID(forServiceID: serviceID) else { return }
        _ = execute(type: 5 /* PPP_DISCONNECT */, link: link)
    }

    private func startConnection(serviceID: String) -> Bool {
        guard let connection = SCNetworkConnectionCreateWithServiceID(nil, serviceID as CFString,
                                                                      nil, nil) else { return false }
        // Reuse the options the system last started this service with; when
        // there are none, the service's configured defaults apply.
        let options = SCNetworkConnectionCopyUserOptions(connection)
        return SCNetworkConnectionStart(connection, options, true)
    }

    private func stopConnection(serviceID: String) -> Bool {
        guard let connection = SCNetworkConnectionCreateWithServiceID(nil, serviceID as CFString,
                                                                      nil, nil) else { return false }
        return SCNetworkConnectionStop(connection, true)
    }

    // MARK: - pppconfd

    private func linkID(forInterfaceName name: String) -> UInt32? {
        linkID(type: 14 /* PPP_GETLINKBYIFNAME */, payload: Data(name.utf8))
    }

    private func linkID(forServiceID serviceID: String) -> UInt32? {
        linkID(type: 13 /* PPP_GETLINKBYSERVICEID */, payload: Data(serviceID.utf8))
    }

    private func linkID(type: UInt16, payload: Data) -> UInt32? {
        guard let reply = execute(type: type, link: UInt32.max, payload: payload),
              reply.count == 4 else { return nil }
        return Self.uint32(reply, at: 0)
    }

    private func status(forLink link: UInt32) -> PPPStatusResult? {
        guard let reply = execute(type: 2 /* PPP_STATUS */, link: link),
              reply.count == 36,
              let status = Self.uint32(reply, at: 0) else { return nil }

        if status == Self.running {
            return PPPStatusResult(status: status,
                                   timeElapsed: Self.uint32(reply, at: 4),
                                   timeRemaining: Self.uint32(reply, at: 8),
                                   inBytes: Self.uint32(reply, at: 12),
                                   outBytes: Self.uint32(reply, at: 24))
        }
        return PPPStatusResult(status: status, timeElapsed: nil, timeRemaining: nil,
                               inBytes: nil, outBytes: nil)
    }

    private func execute(type: UInt16, link: UInt32 = 0,
                         payload: Data = Data()) -> Data? {
        // struct ppp_msg_hdr: flags, type, result, cookie, link, length.
        var message = Data()
        Self.appendUInt16(0, to: &message)
        Self.appendUInt16(type, to: &message)
        Self.appendUInt32(0, to: &message)
        Self.appendUInt32(0, to: &message)
        Self.appendUInt32(link, to: &message)
        Self.appendUInt32(UInt32(payload.count), to: &message)
        message.append(payload)

        // A connection made before configd restarted fails on first use, so
        // an I/O failure on a reused socket is retried once on a new one.
        while true {
            let reused = socketFD >= 0
            if !reused { socketFD = Self.openSocket() }
            guard socketFD >= 0 else { return nil }
            let reply = exchange(message)
            if socketFD >= 0 || !reused { return reply }
        }
    }

    /// One request and its reply. Any I/O failure closes the socket, since a
    /// timed out or partial reply leaves the stream out of step.
    private func exchange(_ message: Data) -> Data? {
        guard writeAll(message), let headerData = readExactly(20),
              let result = Self.uint32(headerData, at: 4),
              let length = Self.uint32(headerData, at: 16),
              length <= Self.maxReplyLength,
              let reply = readExactly(Int(length)) else {
            closeSocket()
            return nil
        }
        guard length > 0, result == 0 else { return nil }
        return reply
    }

    private func writeAll(_ data: Data) -> Bool {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return Darwin.write(socketFD, base.advanced(by: offset), data.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            if written == 0 { return false }
            offset += written
        }
        return true
    }

    private func readExactly(_ count: Int) -> Data? {
        guard socketFD >= 0, count >= 0 else { return nil }
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let received = data.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return Darwin.read(socketFD, base.advanced(by: offset), count - offset)
            }
            if received < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if received == 0 { return nil }
            offset += received
        }
        return data
    }

    // MARK: - Byte helpers

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
