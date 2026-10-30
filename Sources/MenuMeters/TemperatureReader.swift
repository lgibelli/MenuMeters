//
//  TemperatureReader.swift
//  MenuMeters
//
//  SMC (Intel) and IOHID (Apple silicon) temperature sensors.
//
//  Copyright (c) 2015-2026 The MenuMeters contributors (see the Git history)
//  The SMC key-description lookup is modified from smcread.c in VirtualSMC,
//  Copyright (c) 2017 vit9696, BSD-3-Clause.
//  The Apple Silicon sensor access is based on fermion-star/apple_sensors, which
//  is based on freedomtan/sensors, Copyright (c) 2016-2018 Koan-Sin Tan,
//  BSD-3-Clause. See Docs/Acknowledgements.md for the license texts.
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
//  2026-10-30  Luca Gibelli: matched the 80-byte SMC call layout and cached the default sensor.
//

import Cocoa
import IOKit

enum TemperatureReader {
    // MARK: - Public interface

    static func sensorNames() -> [String]? {
#if arch(x86_64)
        return IntelSMC.sensorNames()
#else
        return AppleSiliconSensors.names().sorted()
#endif
    }

    static func defaultSensor() -> String? {
        resolvedDefaultSensor
    }

    // Depends only on the hardware, so resolve it once rather than enumerating
    // every sensor on each redraw.
    private static let resolvedDefaultSensor: String? = {
        let candidate: String
#if arch(x86_64)
        candidate = "TC0P"
#else
        candidate = "SOC MTR Temp Sensor0"
#endif
        guard let names = sensorNames(), !names.isEmpty else { return candidate }
        if names.contains(candidate) { return candidate }
        if let tc = names.first(where: { $0.hasPrefix("TC") }) { return tc }
        return names.first
    }()

    static func displayName(for sensor: String) -> String {
#if arch(x86_64)
        return IntelSMC.displayName(for: sensor)
#else
        return sensor
#endif
    }

    static func temperature(sensor: String) -> Float {
#if arch(x86_64)
        return IntelSMC.temperature(sensor: sensor)
#else
        return AppleSiliconSensors.temperature(name: sensor)
#endif
    }
}

// MARK: - Apple SMC

#if arch(x86_64)
private enum IntelSMC {
    private static let kernelIndexSMC: UInt32 = 2
    private static let commandReadBytes: UInt8 = 5
    private static let commandReadIndex: UInt8 = 8
    private static let commandReadKeyInfo: UInt8 = 9

    private struct Code: Equatable {
        var bytes: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)

        init() {}
        init(_ key: String) {
            let chars = Array(key.utf8)
            if chars.count == 4 {
                bytes = (chars[3], chars[2], chars[1], chars[0])
            }
        }

        var string: String {
            String(bytes: [bytes.3, bytes.2, bytes.1, bytes.0], encoding: .ascii) ?? ""
        }

        static func == (lhs: Code, rhs: Code) -> Bool {
            lhs.bytes.0 == rhs.bytes.0 && lhs.bytes.1 == rhs.bytes.1
                && lhs.bytes.2 == rhs.bytes.2 && lhs.bytes.3 == rhs.bytes.3
        }
    }

    private struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: Int8 = 0
        var release: UInt16 = 0
    }

    private struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType = Code()
        var dataAttributes: UInt8 = 0
    }

    private struct Bytes {
        var b0: UInt8 = 0, b1: UInt8 = 0, b2: UInt8 = 0, b3: UInt8 = 0
        var b4: UInt8 = 0, b5: UInt8 = 0, b6: UInt8 = 0, b7: UInt8 = 0
        var b8: UInt8 = 0, b9: UInt8 = 0, b10: UInt8 = 0, b11: UInt8 = 0
        var b12: UInt8 = 0, b13: UInt8 = 0, b14: UInt8 = 0, b15: UInt8 = 0
        var b16: UInt8 = 0, b17: UInt8 = 0, b18: UInt8 = 0, b19: UInt8 = 0
        var b20: UInt8 = 0, b21: UInt8 = 0, b22: UInt8 = 0, b23: UInt8 = 0
        var b24: UInt8 = 0, b25: UInt8 = 0, b26: UInt8 = 0, b27: UInt8 = 0
        var b28: UInt8 = 0, b29: UInt8 = 0, b30: UInt8 = 0, b31: UInt8 = 0
    }

    /// Mirrors the 80-byte C SMCParamStruct the AppleSMC user client expects.
    private struct KeyData {
        var key = Code()
        var vers = Version()
        var pLimitData = PLimitData()
        var keyInfo = KeyInfo()
        // C pads the 9-byte keyInfo to 12 bytes; Swift does not, so pad by
        // hand to put result at 40, data8 at 42, data32 at 44 and bytes at 48.
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes = Bytes()
    }

    private struct KeyValue {
        var key = Code()
        var info = KeyInfo()
        var bytes = Bytes()
    }

    private static let dataTypeSP78 = Code("sp78")
    private static let dataTypeUInt32 = Code("ui32")

    private static func open() -> io_connect_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        let device = IOIteratorNext(iterator)
        guard device != 0 else { return nil }
        defer { IOObjectRelease(device) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(device, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        return connection
    }

    private static func call(_ connection: io_connect_t, _ input: inout KeyData,
                             _ output: inout KeyData) -> kern_return_t {
        // Never hand the kernel a struct that does not match its layout.
        guard MemoryLayout<KeyData>.size == 80 else { return kIOReturnBadArgument }
        var size = MemoryLayout<KeyData>.size
        return withUnsafePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(connection, kernelIndexSMC,
                                          inputPointer, size,
                                          outputPointer, &size)
            }
        }
    }

    private static func readKey(_ connection: io_connect_t, _ key: Code) -> KeyValue? {
        var input = KeyData()
        var output = KeyData()
        input.key = key
        input.data8 = commandReadKeyInfo
        guard call(connection, &input, &output) == KERN_SUCCESS,
              output.result == 0 else { return nil }

        var value = KeyValue()
        value.key = key
        value.info = output.keyInfo

        input = KeyData()
        output = KeyData()
        input.key = key
        input.keyInfo.dataSize = value.info.dataSize
        input.data8 = commandReadBytes
        guard call(connection, &input, &output) == KERN_SUCCESS,
              output.result == 0 else { return nil }
        value.bytes = output.bytes
        return value
    }

    private static func keyCount(_ connection: io_connect_t) -> UInt32? {
        guard let value = readKey(connection, Code("#KEY")),
              value.info.dataType == dataTypeUInt32 else { return nil }
        return UInt32(value.bytes.b0) << 24 | UInt32(value.bytes.b1) << 16
            | UInt32(value.bytes.b2) << 8 | UInt32(value.bytes.b3)
    }

    private static func key(at index: UInt32, connection: io_connect_t) -> KeyValue? {
        var input = KeyData()
        var output = KeyData()
        input.data32 = index
        input.data8 = commandReadIndex
        guard call(connection, &input, &output) == KERN_SUCCESS,
              output.result == 0 else { return nil }
        return readKey(connection, output.key)
    }

    static func sensorNames() -> [String]? {
        guard let connection = open() else { return nil }
        defer { IOServiceClose(connection) }
        guard let count = keyCount(connection) else { return nil }
        var names: [String] = []
        for index in 0..<count {
            guard let value = key(at: index, connection: connection),
                  value.info.dataType == dataTypeSP78 else { continue }
            let name = value.key.string
            if name.hasPrefix("T") { names.append(name) }
        }
        return names
    }

    private static var descriptions: [String: String] = {
        var result: [String: String] = [:]
        guard let library = dlopen("/usr/lib/libSMC.dylib", RTLD_LAZY) else { return result }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "AccumulatorPlatformStructLookupArray") else { return result }

        let lookup = symbol.assumingMemoryBound(to: UInt8.self)
        var offset = 0
        var stop = false
        while !stop, lookup[offset] != 0, lookup[offset] < 128 {
            for set in 0..<2 {
                let descriptionsPointer = lookup.advanced(by: offset + 16 + set * 8)
                    .withMemoryRebound(to: UnsafeMutableRawPointer?.self, capacity: 1) { $0.pointee }
                let count = lookup.advanced(by: offset + 32 + set * 4)
                    .withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
                guard let descriptionsPointer else { continue }
                for index in 0..<Int(count) {
                    let entry = descriptionsPointer.advanced(by: index * 272)
                    let pad1 = entry.advanced(by: 262).withMemoryRebound(to: UInt16.self, capacity: 1) { $0.pointee }
                    let pad2 = entry.advanced(by: 268).withMemoryRebound(to: UInt32.self, capacity: 1) { $0.pointee }
                    if pad1 != 0 || pad2 != 0 {
                        stop = true
                        break
                    }
                    let keyBytes = [
                        entry.load(fromByteOffset: 3, as: UInt8.self),
                        entry.load(fromByteOffset: 2, as: UInt8.self),
                        entry.load(fromByteOffset: 1, as: UInt8.self),
                        entry.load(fromByteOffset: 0, as: UInt8.self),
                    ]
                    guard let key = String(bytes: keyBytes, encoding: .ascii) else { continue }
                    let raw = UnsafeBufferPointer(start: entry.advanced(by: 5).assumingMemoryBound(to: UInt8.self),
                                                  count: 256)
                    let length = raw.prefix { $0 != 0 }.count
                    let text = String(bytes: raw.prefix(length), encoding: .utf8) ?? ""
                    result[key] = text
                }
            }
            offset += 48
        }
        return result
    }()

    static func displayName(for sensor: String) -> String {
        guard let raw = descriptions[sensor] else { return sensor }
        let cleaned = raw
            .replacingOccurrences(of: "(DegC)", with: "")
            .replacingOccurrences(of: "(\(sensor))", with: "")
        return "\(sensor): \(cleaned)"
    }

    static func temperature(sensor: String) -> Float {
        guard let connection = open() else { return -273.15 }
        defer { IOServiceClose(connection) }
        guard let value = readKey(connection, Code(sensor)),
              value.info.dataType == dataTypeSP78 else { return -273.15 }
        let raw = UInt16(value.bytes.b0) << 8 | UInt16(value.bytes.b1)
        return Float(raw) / 256.0
    }
}
#endif

// MARK: - Apple silicon IOHID sensors

#if arch(arm64)
private typealias IOHIDEventSystemClientRef = OpaquePointer

@_silgen_name("IOHIDEventSystemClientCreate")
private func MMIOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClientRef?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func MMIOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClientRef?,
                                                _ matching: CFDictionary?) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func MMIOHIDEventSystemClientCopyServices(_ client: IOHIDEventSystemClientRef?) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func MMIOHIDServiceClientCopyProperty(_ service: OpaquePointer?,
                                              _ key: CFString) -> CFTypeRef?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func MMIOHIDServiceClientCopyEvent(_ service: OpaquePointer?, _ type: Int64,
                                           _ options: Int32, _ timestamp: Int64) -> OpaquePointer?

@_silgen_name("IOHIDEventGetFloatValue")
private func MMIOHIDEventGetFloatValue(_ event: OpaquePointer?, _ field: Int32) -> Double

private enum AppleSiliconSensors {
    private static let eventSystem: IOHIDEventSystemClientRef? = MMIOHIDEventSystemClientCreate(kCFAllocatorDefault)
    private static let usagePage = 0xff00
    private static let usage = 5
    private static let temperatureEventType: Int32 = 15

    private static func services(matchingProduct product: String? = nil) -> [OpaquePointer] {
        guard let eventSystem else { return [] }
        var matching: [String: Any] = ["PrimaryUsagePage": usagePage, "PrimaryUsage": usage]
        if let product { matching["Product"] = product }
        _ = MMIOHIDEventSystemClientSetMatching(eventSystem, matching as CFDictionary)
        guard let array = MMIOHIDEventSystemClientCopyServices(eventSystem) as? [AnyObject] else { return [] }
        return array.map { OpaquePointer(Unmanaged.passUnretained($0).toOpaque()) }
    }

    static func names() -> [String] {
        services().compactMap { service in
            guard let property = MMIOHIDServiceClientCopyProperty(service, "Product" as CFString) else { return nil }
            return property as? String
        }
    }

    static func temperature(name: String) -> Float {
        guard let service = services(matchingProduct: name).first,
              let event = MMIOHIDServiceClientCopyEvent(service, Int64(temperatureEventType), 0, 0) else {
            return -273.15
        }
        let value = MMIOHIDEventGetFloatValue(event, temperatureEventType << 16)
        Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(event)).release()
        return Float(value)
    }
}
#endif
