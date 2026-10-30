//
//  NetConfig.swift
//  MenuMeters
//
//  SystemConfiguration and IOKit reader for network service details.
//
//  Copyright (c) 2002-2014 Alex Harper
//  Copyright (c) 2015-2026 The MenuMeters contributors (see the Git history)
//  Interface up detection based on a patch contributed by Da Woon Jung.
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
//  2026-10-30  Luca Gibelli: ifconfig link speed without a shell, off the main thread; PPP up state not cached when unknown.
//

import Cocoa
import SystemConfiguration
import IOKit

struct NetInterfaceConfig {
    let serviceID: String
    let statName: String
    let speed: Double
    let name: String
    let isUp: Bool
}

struct NetInterfaceDetails {
    let serviceID: String
    var isPrimary = false
    var name = "Unknown Interface"
    var deviceName: String?
    var pppDeviceName: String?
    var connectionType: String?
    var isPPPService = false
    var pppStatus: PPPStatusResult?
    var ipv4Addresses: [String] = []
    var ipv6Addresses: [String] = []
    var appleTalkNetID: String?
    var appleTalkNodeID: String?
    var appleTalkZone: String?
    var linkActive: Bool?
    var linkSpeed: Double?
}

/// SystemConfiguration notification callback. The context is an unretained
/// NetConfig instance owned by the network menu extra.
private func netConfigChanged(store: SCDynamicStore?, changedKeys: CFArray?,
                              info: UnsafeMutableRawPointer?) {
    guard let info else { return }
    Unmanaged<NetConfig>.fromOpaque(info).takeUnretainedValue().configChanged()
}

final class NetConfig {
    /// Called on the main queue when SystemConfiguration reports a change.
    var onChange: (() -> Void)?

    private let ppp = NetPPP.shared
    private var store: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?
    private var masterPort: mach_port_t = 0

    // SystemConfiguration is slow enough that the original meter cached
    // almost everything and dropped the caches on SC notifications.
    private var cachedDetails: [NetInterfaceDetails]?
    private var cachedPrimaryName: String?
    private var cachedPrimaryService: String?
    private var cachedServiceToName: [String: String] = [:]
    private var cachedNameToService: [String: String] = [:]
    private var cachedServiceSpeed: [String: Double] = [:]
    private var cachedUnderlying: [String: String] = [:]
    private var cachedInterfaceUp: [String: Bool] = [:]
    // When to ask again about a PPP service whose status could not be read.
    private var pppRetryAfter: [String: Date] = [:]

    // ifconfig link speeds by interface name, looked up off the main thread.
    // Configuration changes mark them stale, and a stale speed is still
    // served until its refresh completes.
    private var ifconfigSpeeds: [String: Double] = [:]
    private var staleIfconfigSpeeds: Set<String> = []
    private var ifconfigLookupsInFlight: Set<String> = []
    // Bumped by clearCaches(), to recognize lookups started before a change.
    private var ifconfigGeneration = 0

    init() {
        var context = SCDynamicStoreContext(version: 0,
                                            info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil,
                                            release: nil,
                                            copyDescription: nil)
        if let store = SCDynamicStoreCreate(nil, "MenuMeterNetConfig" as CFString,
                                            netConfigChanged, &context) {
            self.store = store
            let keys = ["State:/Network/Global/IPv4",
                        "Setup:/Network/Global/IPv4",
                        "State:/Network/Interface"] as CFArray
            let patterns = ["State:/Network/Interface.*"] as CFArray
            if SCDynamicStoreSetNotificationKeys(store, keys, patterns),
               let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
                runLoopSource = source
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            } else {
                NSLog("MenuMeterNetConfig unable to install notification keys.")
            }
        } else {
            NSLog("MenuMeterNetConfig unable to establish configd session.")
        }

        var port: mach_port_t = 0
        if IOMainPort(0, &port) == KERN_SUCCESS {
            masterPort = port
        } else {
            NSLog("MenuMeterNetConfig unable to establish IOKit port.")
        }

        // Prime the caches while startup is cheap.
        _ = interfaceDetails()
        _ = primaryInterfaceName()
        _ = primaryServiceID()
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }

    // MARK: - Public data

    func computerName() -> String? {
        guard let store else { return nil }
        return SCDynamicStoreCopyComputerName(store, nil) as String?
    }

    func interfaceConfig(for name: String?) -> NetInterfaceConfig? {
        if let name, name != MM.primaryInterface,
           let service = serviceForInterfaceName(name) {
            guard let statName = underlyingInterfaceNameForServiceID(service) else { return nil }
            return NetInterfaceConfig(serviceID: service,
                                      statName: statName,
                                      speed: speedForServiceID(service),
                                      name: name,
                                      isUp: interfaceNameIsUp(statName))
        }

        guard let service = primaryServiceID() else { return nil }
        let statName = underlyingInterfaceNameForServiceID(service)
        let primaryName = primaryInterfaceName()
        guard let underlying = statName ?? primaryName else { return nil }
        return NetInterfaceConfig(serviceID: service,
                                  statName: underlying,
                                  speed: speedForServiceID(service),
                                  name: MM.primaryInterface,
                                  isUp: interfaceNameIsUp(underlying))
    }

    func interfaceDetails() -> [NetInterfaceDetails] {
        if let cached = cachedDetails {
            var refreshed = cached
            // Includes services whose status could not be read before, but
            // asks about those at most every 10 seconds: if pppconfd stops
            // answering, each request waits for its timeout on the main thread.
            for index in refreshed.indices where refreshed[index].isPPPService {
                let serviceID = refreshed[index].serviceID
                let unknown = refreshed[index].pppStatus == nil
                if unknown, let retry = pppRetryAfter[serviceID], retry > Date() { continue }
                if let status = ppp.status(forServiceID: serviceID) {
                    refreshed[index].pppStatus = status
                    pppRetryAfter[serviceID] = nil
                } else if unknown {
                    pppRetryAfter[serviceID] = Date().addingTimeInterval(10)
                }
            }
            cachedDetails = refreshed
            return refreshed
        }

        guard let servicesDict = sysconfigValue("Setup:/Network/Global/IPv4"),
              var services = servicesDict["ServiceOrder"] as? [String] else { return [] }

        let primaryService = primaryServiceID()
        if let primaryService, let index = services.firstIndex(of: primaryService), index != 0 {
            let service = services.remove(at: index)
            services.insert(service, at: 0)
        }

        var detailsList: [NetInterfaceDetails] = []
        for serviceID in services {
            var displayName: String?
            if let serviceDict = sysconfigValue("Setup:/Network/Service/\(serviceID)"),
               let definedName = serviceDict["UserDefinedName"] as? String {
                displayName = definedName
            }

            guard let interfaceDict = sysconfigValue("Setup:/Network/Service/\(serviceID)/Interface") else {
                continue
            }
            if displayName == nil {
                if let definedName = interfaceDict["UserDefinedName"] as? String {
                    displayName = definedName
                } else if let hardware = interfaceDict["Hardware"] as? String {
                    displayName = hardware
                } else {
                    displayName = "Unknown Interface"
                }
            }

            var detail = NetInterfaceDetails(serviceID: serviceID)
            detail.isPrimary = (primaryService == serviceID)
            detail.name = displayName ?? "Unknown Interface"
            detail.deviceName = interfaceDict["DeviceName"] as? String
            detail.connectionType = (interfaceDict["SubType"] as? String)
                ?? (interfaceDict["Type"] as? String)

            let statePPP = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
            if let pppName = statePPP?["InterfaceName"] as? String {
                detail.pppDeviceName = pppName
            }
            if sysconfigValue("Setup:/Network/Service/\(serviceID)/PPP") != nil {
                detail.isPPPService = true
                detail.pppStatus = ppp.status(forServiceID: serviceID)
            }

            if let ipDict = sysconfigValue("State:/Network/Service/\(serviceID)/IPv4") {
                detail.ipv4Addresses = stringArray(ipDict["Addresses"])
            }
            // The service's own addresses: the interface's would include its
            // link-local address, and for PPP those of the transport.
            if let ipDict = sysconfigValue("State:/Network/Service/\(serviceID)/IPv6") {
                detail.ipv6Addresses = stringArray(ipDict["Addresses"])
            }

            if let device = detail.deviceName,
               let appletalk = sysconfigValue("State:/Network/Interface/\(device)/AppleTalk"),
               appletalk["NetworkID"] != nil,
               appletalk["NodeID"] != nil,
               appletalk["DefaultZone"] != nil {
                detail.appleTalkNetID = displayText(appletalk["NetworkID"])
                detail.appleTalkNodeID = displayText(appletalk["NodeID"])
                detail.appleTalkZone = displayText(appletalk["DefaultZone"])
            }

            if let device = detail.deviceName,
               let link = sysconfigValue("State:/Network/Interface/\(device)/Link") {
                detail.linkActive = boolValue(link["Active"])
            }

            if let device = detail.deviceName {
                if device.hasPrefix("en") {
                    detail.linkSpeed = speedForInterfaceName(device)
                } else if device == "modem",
                          let modem = sysconfigValue("State:/Network/Service/\(serviceID)/Modem"),
                          modem["ConnectSpeed"] != nil {
                    let pppDict = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
                    if uint32Value(pppDict?["Status"]) == NetPPP.running,
                       let speed = doubleValue(pppDict?["ConnectSpeed"]) {
                        detail.linkSpeed = speed
                    }
                }
            }

            detailsList.append(detail)
        }

        cachedDetails = detailsList
        return detailsList
    }

    func primaryInterfaceName() -> String? {
        if let cachedPrimaryName { return cachedPrimaryName }
        guard let ipDict = sysconfigValue("State:/Network/Global/IPv4"),
              let name = ipDict["PrimaryInterface"] as? String else { return nil }
        cachedPrimaryName = name
        return name
    }

    func primaryServiceID() -> String? {
        if let cachedPrimaryService { return cachedPrimaryService }
        guard let ipDict = sysconfigValue("State:/Network/Global/IPv4"),
              let service = ipDict["PrimaryService"] as? String else { return nil }
        cachedPrimaryService = service
        return service
    }

    func interfaceNameForServiceID(_ serviceID: String?) -> String? {
        guard let serviceID else { return nil }
        if let cached = cachedServiceToName[serviceID] { return cached }

        let interfaceDict = sysconfigValue("Setup:/Network/Service/\(serviceID)/Interface")
        let pppDict = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
        if let pppName = pppDict?["InterfaceName"] as? String {
            cachedServiceToName[serviceID] = pppName
            return pppName
        }
        if let device = interfaceDict?["DeviceName"] as? String {
            cachedServiceToName[serviceID] = device
            return device
        }
        return nil
    }

    func serviceForInterfaceName(_ interfaceName: String) -> String? {
        if let cached = cachedNameToService[interfaceName] { return cached }
        guard let services = serviceOrder() else { return nil }

        for serviceID in services {
            let interfaceDict = sysconfigValue("Setup:/Network/Service/\(serviceID)/Interface")
            if interfaceDict?["DeviceName"] as? String == interfaceName {
                cachedNameToService[interfaceName] = serviceID
                return serviceID
            }
            let pppDict = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
            if pppDict?["InterfaceName"] as? String == interfaceName {
                cachedNameToService[interfaceName] = serviceID
                return serviceID
            }
        }
        return nil
    }

    func speedForServiceID(_ serviceID: String?) -> Double {
        guard let serviceID else { return -1 }
        if let cached = cachedServiceSpeed[serviceID] { return cached }

        let modemDict = sysconfigValue("State:/Network/Service/\(serviceID)/Modem")
        let pppDict = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
        if modemDict != nil {
            if let connectSpeed = doubleValue(modemDict?["ConnectSpeed"]),
               uint32Value(pppDict?["Status"]) == NetPPP.running {
                cachedServiceSpeed[serviceID] = connectSpeed
                return connectSpeed
            }
            return 56000
        }

        if let interfaceName = interfaceNameForServiceID(serviceID),
           interfaceName.hasPrefix("en") {
            let speed = speedForInterfaceName(interfaceName)
            cachedServiceSpeed[serviceID] = speed
            return speed
        }

        return -1
    }

    func underlyingInterfaceNameForServiceID(_ serviceID: String?) -> String? {
        guard let serviceID else { return nil }
        if let cached = cachedUnderlying[serviceID] { return cached }

        let interfaceDict = sysconfigValue("Setup:/Network/Service/\(serviceID)/Interface")
        let pppDict = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
        if let pppName = pppDict?["InterfaceName"] as? String {
            if let device = interfaceDict?["DeviceName"] as? String, device.hasPrefix("en") {
                cachedUnderlying[serviceID] = device
                return device
            }
            cachedUnderlying[serviceID] = pppName
            return pppName
        }
        if let device = interfaceDict?["DeviceName"] as? String {
            cachedUnderlying[serviceID] = device
            return device
        }
        return nil
    }

    func interfaceNameIsUp(_ interfaceName: String?) -> Bool {
        guard let interfaceName else { return false }
        if let cached = cachedInterfaceUp[interfaceName] { return cached }

        if interfaceName.hasPrefix("en") {
            let linkDict = sysconfigValue("State:/Network/Interface/\(interfaceName)/Link")
            if let active = boolValue(linkDict?["Active"]) {
                cachedInterfaceUp[interfaceName] = active
                return active
            }
        } else if interfaceName.hasPrefix("ppp") {
            if let status = ppp.status(forInterfaceName: interfaceName) {
                let running = status.status == NetPPP.running
                cachedInterfaceUp[interfaceName] = running
                return running
            }
            // pppconfd cannot report on it: ask the interface, without
            // caching, so pppconfd is asked again next time.
            return Self.interfaceIsUpAndRunning(interfaceName)
        }

        // Interfaces without explicit link state are assumed active.
        return true
    }

    /// IFF_UP and IFF_RUNNING from the interface flags. False when there is no
    /// such interface.
    private static func interfaceIsUpAndRunning(_ interfaceName: String) -> Bool {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0 else { return false }
        defer { freeifaddrs(addressList) }
        var pointer = addressList
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next
            guard String(cString: interface.ifa_name) == interfaceName else { continue }
            let wanted = UInt32(IFF_UP | IFF_RUNNING)
            return interface.ifa_flags & wanted == wanted
        }
        return false
    }

    // MARK: - Link speed

    func speedForInterfaceName(_ interfaceName: String) -> Double {
        if let ioKitSpeed = speedForInterfaceNameViaIOKit(interfaceName) {
            return ioKitSpeed
        }
        return speedForInterfaceNameViaIfConfig(interfaceName)
    }

    private func speedForInterfaceNameViaIOKit(_ interfaceName: String) -> Double? {
        guard masterPort != 0 else { return nil }
        var iterator: io_iterator_t = 0
        guard let matching = IOBSDNameMatching(masterPort, 0, interfaceName) else { return nil }
        IOServiceGetMatchingServices(masterPort, matching, &iterator)
        guard iterator != 0 else { return nil }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return -1 }
        defer { IOObjectRelease(entry) }

        var controller: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &controller) == KERN_SUCCESS,
              controller != 0 else { return -1 }
        defer { IOObjectRelease(controller) }

        guard let value = IORegistryEntryCreateCFProperty(controller, "IOLinkSpeed" as CFString,
                                                          kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber,
              value.uint64Value > 0 else { return nil }
        return value.doubleValue
    }

    /// Returns the last ifconfig speed for the interface, 0 (unknown) until
    /// one is known, and starts a lookup when there is none or it is stale.
    private func speedForInterfaceNameViaIfConfig(_ interfaceName: String) -> Double {
        if ifconfigSpeeds[interfaceName] == nil || staleIfconfigSpeeds.contains(interfaceName) {
            startIfconfigLookup(interfaceName)
        }
        return ifconfigSpeeds[interfaceName] ?? 0
    }

    private func startIfconfigLookup(_ interfaceName: String) {
        guard Self.isPlainInterfaceName(interfaceName),
              !ifconfigLookupsInFlight.contains(interfaceName) else { return }
        ifconfigLookupsInFlight.insert(interfaceName)
        let generation = ifconfigGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let speed = Self.ifconfigLinkSpeed(interfaceName)
            DispatchQueue.main.async {
                self?.ifconfigLookupFinished(interfaceName, speed: speed, generation: generation)
            }
        }
    }

    private func ifconfigLookupFinished(_ interfaceName: String, speed: Double, generation: Int) {
        ifconfigLookupsInFlight.remove(interfaceName)
        // A lookup started before the configuration changed is served for
        // now, but stays stale so the next access looks again.
        let current = generation == ifconfigGeneration
        if current {
            staleIfconfigSpeeds.remove(interfaceName)
        } else {
            staleIfconfigSpeeds.insert(interfaceName)
        }
        let changed = (ifconfigSpeeds.updateValue(speed, forKey: interfaceName) ?? 0) != speed
        guard changed || !current else { return }
        // Drop the caches derived from link speed and let the owner refresh.
        cachedDetails = nil
        cachedServiceSpeed.removeAll()
        onChange?()
    }

    /// BSD names such as en0. Anything else is never handed to ifconfig.
    private static func isPlainInterfaceName(_ interfaceName: String) -> Bool {
        interfaceName.utf8.count < Int(IFNAMSIZ)
            && interfaceName.range(of: "^[A-Za-z]+[0-9]+$", options: .regularExpression) != nil
    }

    /// Runs `/sbin/ifconfig -v <name>` (no shell), giving up after two seconds.
    private static func ifconfigLinkSpeed(_ interfaceName: String) -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        process.arguments = ["-v", interfaceName]
        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return 0
        }
        // Terminating a stuck ifconfig closes its end of the pipe, which ends
        // the read below.
        let timeout = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return 0 }
        return linkSpeed(fromIfconfigOutput: String(decoding: data, as: UTF8.self))
    }

    /// Parses the "link rate:" line of `ifconfig -v`, or the "uplink rate:"
    /// and "downlink rate:" lines it prints instead when the effective rate
    /// differs from the maximum. The largest rate found is the link speed.
    private static func linkSpeed(fromIfconfigOutput output: String) -> Double {
        let factors: [String: Double] = ["Gbps": 1_000_000_000,
                                         "Mbps": 1_000_000,
                                         "Kbps": 1_000,
                                         "bps": 1]
        var speed: Double = 0
        for line in output.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let label = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard ["link rate", "uplink rate", "downlink rate"].contains(label) else { continue }
            let words = line[line.index(after: colon)...].split(separator: " ")
            for (number, unit) in zip(words, words.dropFirst()) {
                if let value = Double(number), let factor = factors[String(unit)] {
                    speed = max(speed, value * factor)
                }
            }
        }
        return speed
    }

    // MARK: - SystemConfiguration helpers

    private func sysconfigValue(_ key: String) -> [String: Any]? {
        guard let store else { return nil }
        return SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
    }

    private func serviceOrder() -> [String]? {
        guard let dict = sysconfigValue("Setup:/Network/Global/IPv4") else { return nil }
        if let order = dict["ServiceOrder"] as? [String] { return order }
        let order = stringArray(dict["ServiceOrder"])
        return order.isEmpty ? nil : order
    }

    private func stringArray(_ value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { $0 as? String }
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let bool = value as? Bool { return bool }
        return nil
    }

    private func uint32Value(_ value: Any?) -> UInt32? {
        if let number = value as? NSNumber { return number.uint32Value }
        if let string = value as? String { return UInt32(string) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func displayText(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    func configChanged() {
        clearCaches()
        if let onChange {
            DispatchQueue.main.async { onChange() }
        }
    }

    func clearCaches() {
        cachedDetails = nil
        cachedPrimaryName = nil
        cachedPrimaryService = nil
        cachedServiceToName.removeAll()
        cachedNameToService.removeAll()
        cachedServiceSpeed.removeAll()
        cachedUnderlying.removeAll()
        cachedInterfaceUp.removeAll()
        ifconfigGeneration += 1
        staleIfconfigSpeeds = Set(ifconfigSpeeds.keys)
    }
}
