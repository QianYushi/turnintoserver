import Darwin
import Foundation
import SystemConfiguration

enum AutomaticRoutePlan {
    struct CIDR: Hashable {
        let networkAddress: UInt32
        let prefixLength: Int

        var stringValue: String {
            "\(Self.ipv4String(networkAddress))/\(prefixLength)"
        }

        var routeKey: RouteKey {
            RouteKey(
                destination: Self.ipv4String(networkAddress),
                netmask: Self.ipv4String(Self.netmask(prefixLength: prefixLength))
            )
        }

        var representativeAddress: String {
            let value = prefixLength == 32 ? networkAddress : networkAddress &+ 1
            return Self.ipv4String(value)
        }

        private static func netmask(prefixLength: Int) -> UInt32 {
            let shift = 32 - prefixLength
            return shift == 0 ? UInt32.max : UInt32.max << UInt32(shift)
        }

        private static func ipv4String(_ value: UInt32) -> String {
            [24, 16, 8, 0]
                .map { String((value >> UInt32($0)) & 0xff) }
                .joined(separator: ".")
        }
    }

    struct RouteKey: Hashable {
        let destination: String
        let netmask: String
    }

    struct ValidationError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    static let maximumCIDRCount = 256
    static let exampleCIDRStrings = [
        "10.0.0.0/8",
        "192.168.1.0/24",
        "172.16.10.20/32"
    ]

    static func configuredCIDRs(defaults: UserDefaults = .standard) -> [CIDR] {
        let savedValues = defaults.stringArray(forKey: AppDefaultsKey.automaticRoutingCIDRs)
        return (try? validatedCIDRs(savedValues ?? exampleCIDRStrings))
            ?? (try! validatedCIDRs(exampleCIDRStrings))
    }

    static func configuredCIDRStrings(defaults: UserDefaults = .standard) -> [String] {
        configuredCIDRs(defaults: defaults).map(\.stringValue)
    }

    static func validatedCIDRs(_ values: [String]) throws -> [CIDR] {
        var result: [CIDR] = []
        var seen = Set<CIDR>()

        for (index, rawValue) in values.enumerated() {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                continue
            }

            let cidr = try parseCIDR(value, lineNumber: index + 1)
            if seen.insert(cidr).inserted {
                result.append(cidr)
            }
        }

        guard !result.isEmpty else {
            throw ValidationError(message: AppText.automaticRouteCIDREmpty)
        }
        guard result.count <= maximumCIDRCount else {
            throw ValidationError(message: AppText.automaticRouteCIDRTooMany(maximum: maximumCIDRCount))
        }
        return result
    }

    static func validatedCIDRs(text: String) throws -> [CIDR] {
        try validatedCIDRs(text.components(separatedBy: .newlines))
    }

    static func routeKeys(for cidrs: [CIDR]) -> [RouteKey] {
        cidrs.map(\.routeKey)
    }

    static func broadNetworkDescriptions(for cidrs: [CIDR]) -> [String] {
        cidrs.filter { $0.prefixLength < 32 }.map(\.stringValue)
    }

    static func exactHostCount(for cidrs: [CIDR]) -> Int {
        cidrs.filter { $0.prefixLength == 32 }.count
    }

    static func modeDescription(
        for cidrs: [CIDR],
        accessPoints: AutomaticRouteAccessPointConfiguration
    ) -> String {
        "\(accessPoints.route.serviceName) + \(accessPoints.companion.serviceName): \(cidrs.count) user-managed internal CIDR routes via the first access point; all other traffic follows the macOS default route"
    }

    static func verificationDestinations(for cidrs: [CIDR]) -> [String] {
        let broad = cidrs.filter { $0.prefixLength < 32 }
        let exact = cidrs.filter { $0.prefixLength == 32 }
        var selected = Array(broad.prefix(6))
        let remainingCount = max(0, 6 - selected.count)

        if remainingCount > 0 {
            if exact.count <= remainingCount {
                selected.append(contentsOf: exact)
            } else if remainingCount == 1 {
                selected.append(exact[exact.count / 2])
            } else {
                for index in 0..<remainingCount {
                    let sourceIndex = index * (exact.count - 1) / (remainingCount - 1)
                    selected.append(exact[sourceIndex])
                }
            }
        }

        return selected.map(\.representativeAddress)
    }

    static func isLegacyObsoleteRoute(_ route: RouteKey) -> Bool {
        return route.netmask == "255.255.255.255"
            && route.destination.hasPrefix("196.")
    }

    private static func parseCIDR(_ value: String, lineNumber: Int) throws -> CIDR {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let prefixLength = Int(parts[1]),
              [8, 16, 24, 32].contains(prefixLength) else {
            throw ValidationError(message: AppText.automaticRouteCIDRInvalid(value: value, line: lineNumber))
        }

        let addressParts = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard addressParts.count == 4 else {
            throw ValidationError(message: AppText.automaticRouteCIDRInvalid(value: value, line: lineNumber))
        }

        var address: UInt32 = 0
        for part in addressParts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isNumber }),
                  let octet = UInt32(part),
                  octet <= 255 else {
                throw ValidationError(message: AppText.automaticRouteCIDRInvalid(value: value, line: lineNumber))
            }
            address = (address << 8) | octet
        }

        let shift = 32 - prefixLength
        let mask = shift == 0 ? UInt32.max : UInt32.max << UInt32(shift)
        return CIDR(networkAddress: address & mask, prefixLength: prefixLength)
    }
}

struct AutomaticRouteAccessPoint: Equatable, Hashable {
    let serviceName: String
    let detectionSignature: String
}

struct AutomaticRouteAccessPointConfiguration: Equatable, Hashable {
    let route: AutomaticRouteAccessPoint
    let companion: AutomaticRouteAccessPoint

    static let examples = AutomaticRouteAccessPointConfiguration(
        route: AutomaticRouteAccessPoint(
            serviceName: "Wi-Fi",
            detectionSignature: ""
        ),
        companion: AutomaticRouteAccessPoint(
            serviceName: "Ethernet",
            detectionSignature: ""
        )
    )

    static func configured(defaults: UserDefaults = .standard) -> AutomaticRouteAccessPointConfiguration {
        let fallback = examples
        return (try? validated(
            routeServiceName: defaults.string(
                forKey: AppDefaultsKey.automaticRoutingRouteServiceName
            ) ?? fallback.route.serviceName,
            routeDetectionSignature: defaults.string(
                forKey: AppDefaultsKey.automaticRoutingRouteDetectionSignature
            ) ?? fallback.route.detectionSignature,
            companionServiceName: defaults.string(
                forKey: AppDefaultsKey.automaticRoutingCompanionServiceName
            ) ?? fallback.companion.serviceName,
            companionDetectionSignature: defaults.string(
                forKey: AppDefaultsKey.automaticRoutingCompanionDetectionSignature
            ) ?? fallback.companion.detectionSignature
        )) ?? fallback
    }

    static func validated(
        routeServiceName: String,
        routeDetectionSignature: String,
        companionServiceName: String,
        companionDetectionSignature: String
    ) throws -> AutomaticRouteAccessPointConfiguration {
        let routeService = try normalizedRequiredValue(
            routeServiceName,
            emptyMessage: AppText.automaticRouteServiceRequired
        )
        let companionService = try normalizedRequiredValue(
            companionServiceName,
            emptyMessage: AppText.automaticRouteServiceRequired
        )
        guard routeService != companionService else {
            throw AutomaticRoutePlan.ValidationError(
                message: AppText.automaticRouteServicesMustDiffer
            )
        }

        return AutomaticRouteAccessPointConfiguration(
            route: AutomaticRouteAccessPoint(
                serviceName: routeService,
                detectionSignature: try normalizedOptionalValue(routeDetectionSignature)
            ),
            companion: AutomaticRouteAccessPoint(
                serviceName: companionService,
                detectionSignature: try normalizedOptionalValue(companionDetectionSignature)
            )
        )
    }

    func persist(to defaults: UserDefaults = .standard) {
        defaults.set(route.serviceName, forKey: AppDefaultsKey.automaticRoutingRouteServiceName)
        defaults.set(
            route.detectionSignature,
            forKey: AppDefaultsKey.automaticRoutingRouteDetectionSignature
        )
        defaults.set(
            companion.serviceName,
            forKey: AppDefaultsKey.automaticRoutingCompanionServiceName
        )
        defaults.set(
            companion.detectionSignature,
            forKey: AppDefaultsKey.automaticRoutingCompanionDetectionSignature
        )
    }

    private static func normalizedRequiredValue(
        _ value: String,
        emptyMessage: String
    ) throws -> String {
        let normalized = try normalizedOptionalValue(value)
        guard !normalized.isEmpty else {
            throw AutomaticRoutePlan.ValidationError(message: emptyMessage)
        }
        return normalized
    }

    private static func normalizedOptionalValue(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count <= 128,
              !normalized.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AutomaticRoutePlan.ValidationError(
                message: AppText.automaticRouteAccessPointValueInvalid
            )
        }
        return normalized
    }
}

struct AutomaticRouteNetworkService: Equatable, Hashable {
    let name: String
    let device: String
}

struct AutomaticRouteSnapshot {
    let isEnabled: Bool
    let routeAccessPointName: String
    let routeAccessPointDevice: String?
    let routeAccessPointIsActive: Bool
    let companionAccessPointName: String
    let companionAccessPointDevice: String?
    let companionAccessPointIsActive: Bool
    let routeGateway: String?
    let installedManagedRouteCount: Int
    let matchingManagedRouteCount: Int
    let expectedManagedRouteCount: Int
    let verifiedDestinationCount: Int
    let expectedVerificationCount: Int
    let managedDestinationInterface: String?
    let managedDestinationGateway: String?
    let defaultRouteInterface: String?
    let defaultRouteGateway: String?

    var routingConditionsAreMet: Bool {
        routeAccessPointIsActive && companionAccessPointIsActive
    }

    var expectsManagedRoutes: Bool {
        isEnabled && routingConditionsAreMet && routeGateway != nil
    }

    var managedRouteIsPresent: Bool {
        installedManagedRouteCount > 0
    }

    var managedRouteIsEffective: Bool {
        guard expectsManagedRoutes,
              let routeGateway,
              let routeAccessPointDevice,
              installedManagedRouteCount == expectedManagedRouteCount,
              matchingManagedRouteCount == expectedManagedRouteCount,
              verifiedDestinationCount == expectedVerificationCount,
              managedDestinationInterface == routeAccessPointDevice else {
            return false
        }

        return managedDestinationGateway == nil
            || managedDestinationGateway == routeGateway
    }
}

private let automaticRouteDynamicStoreCallback: SCDynamicStoreCallBack = { _, _, info in
    guard let info else {
        return
    }

    let manager = Unmanaged<AutomaticRouteManager>.fromOpaque(info).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.handleNetworkChange()
    }
}

@MainActor
final class AutomaticRouteManager {
    private struct DetectedNetworkState {
        let routeIsActive: Bool
        let companionIsActive: Bool
    }

    private struct RouteResolution {
        let interface: String?
        let gateway: String?
    }

    private struct AdditionalRoute: Hashable {
        let destination: String
        let netmask: String
        let gateway: String

        var key: AutomaticRoutePlan.RouteKey {
            AutomaticRoutePlan.RouteKey(destination: destination, netmask: netmask)
        }
    }

    private var dynamicStore: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?
    private var reconcileWorkItem: DispatchWorkItem?
    private var isReconciling = false
    private var needsAnotherReconcile = false
    private var desiredEnabled = false
    private let defaults: UserDefaults
    private var accessPoints: AutomaticRouteAccessPointConfiguration
    private var managedCIDRs: [AutomaticRoutePlan.CIDR]
    private var retiredManagedRouteKeys: Set<AutomaticRoutePlan.RouteKey>
    private var retiredRouteServiceNames: Set<String>

    init(
        defaults: UserDefaults = .standard,
        initialCIDRs: [AutomaticRoutePlan.CIDR]? = nil,
        initialAccessPoints: AutomaticRouteAccessPointConfiguration? = nil
    ) {
        self.defaults = defaults
        let configuredCIDRs = initialCIDRs ?? AutomaticRoutePlan.configuredCIDRs(defaults: defaults)
        let configuredAccessPoints = initialAccessPoints
            ?? AutomaticRouteAccessPointConfiguration.configured(defaults: defaults)
        accessPoints = configuredAccessPoints
        managedCIDRs = configuredCIDRs

        let lastAppliedStrings = defaults.stringArray(
            forKey: AppDefaultsKey.automaticRoutingLastAppliedCIDRs
        ) ?? AutomaticRoutePlan.exampleCIDRStrings
        let lastAppliedCIDRs = (try? AutomaticRoutePlan.validatedCIDRs(lastAppliedStrings))
            ?? configuredCIDRs
        retiredManagedRouteKeys = Set(AutomaticRoutePlan.routeKeys(for: lastAppliedCIDRs))
            .subtracting(AutomaticRoutePlan.routeKeys(for: configuredCIDRs))
        let lastAppliedRouteServiceName = defaults.string(
            forKey: AppDefaultsKey.automaticRoutingLastAppliedRouteServiceName
        ) ?? AutomaticRouteAccessPointConfiguration.examples.route.serviceName
        retiredRouteServiceNames = lastAppliedRouteServiceName == configuredAccessPoints.route.serviceName
            ? []
            : [lastAppliedRouteServiceName]
    }

    func configure(
        cidrs: [AutomaticRoutePlan.CIDR],
        accessPoints newAccessPoints: AutomaticRouteAccessPointConfiguration
    ) {
        retiredManagedRouteKeys.formUnion(managedRoutes)
        if accessPoints.route.serviceName != newAccessPoints.route.serviceName {
            retiredRouteServiceNames.insert(accessPoints.route.serviceName)
        }
        managedCIDRs = cidrs
        accessPoints = newAccessPoints
        retiredManagedRouteKeys.subtract(managedRoutes)
        retiredRouteServiceNames.remove(newAccessPoints.route.serviceName)
    }

    func updateConfiguration(
        cidrs: [AutomaticRoutePlan.CIDR],
        accessPoints newAccessPoints: AutomaticRouteAccessPointConfiguration
    ) async throws {
        let previousCIDRs = managedCIDRs
        let previousAccessPoints = accessPoints
        let previousRetiredKeys = retiredManagedRouteKeys
        let previousRetiredServices = retiredRouteServiceNames
        retiredManagedRouteKeys.formUnion(managedRoutes)
        if accessPoints.route.serviceName != newAccessPoints.route.serviceName {
            retiredRouteServiceNames.insert(accessPoints.route.serviceName)
        }
        managedCIDRs = cidrs
        accessPoints = newAccessPoints
        retiredManagedRouteKeys.subtract(managedRoutes)
        retiredRouteServiceNames.remove(newAccessPoints.route.serviceName)

        do {
            try await reconcile()
        } catch {
            managedCIDRs = previousCIDRs
            accessPoints = previousAccessPoints
            retiredManagedRouteKeys = previousRetiredKeys
            retiredRouteServiceNames = previousRetiredServices
            try? await reconcile()
            throw error
        }
    }

    func availableNetworkServices() async -> [AutomaticRouteNetworkService] {
        (try? await networkServices()) ?? []
    }

    private var managedRoutes: [AutomaticRoutePlan.RouteKey] {
        AutomaticRoutePlan.routeKeys(for: managedCIDRs)
    }

    private var verificationDestinations: [String] {
        AutomaticRoutePlan.verificationDestinations(for: managedCIDRs)
    }

    private func isOwnedRoute(_ route: AutomaticRoutePlan.RouteKey) -> Bool {
        managedRoutes.contains(route)
            || retiredManagedRouteKeys.contains(route)
            || (!defaults.bool(forKey: AppDefaultsKey.automaticRoutingLegacy196MigrationCompleted)
                && AutomaticRoutePlan.isLegacyObsoleteRoute(route))
    }

    func setEnabled(_ isEnabled: Bool) async throws {
        desiredEnabled = isEnabled
        if isEnabled {
            startMonitoringIfNeeded()
        } else {
            stopMonitoring()
        }

        try await reconcile()
    }

    func startMonitoring() {
        desiredEnabled = true
        startMonitoringIfNeeded()
        scheduleReconcile()
    }

    func stopMonitoring() {
        reconcileWorkItem?.cancel()
        reconcileWorkItem = nil

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        dynamicStore = nil
    }

    func handleNetworkChange() {
        scheduleReconcile()
    }

    func currentSnapshot(isEnabled: Bool) async -> AutomaticRouteSnapshot {
        do {
            let services = try await networkServices()
            let routeService = services.first { $0.name == accessPoints.route.serviceName }
            let companionService = services.first { $0.name == accessPoints.companion.serviceName }
            let networkState = try await detectedNetworkState(
                routeService: routeService,
                companionService: companionService
            )
            let routes = routeService == nil
                ? []
                : try await additionalRoutes(serviceName: accessPoints.route.serviceName)
            let installedManagedRoutes = routes.filter {
                isOwnedRoute($0.key)
            }

            var routeGateway: String?
            if networkState.routeIsActive,
               networkState.companionIsActive,
               let routeService {
                routeGateway = try? await currentGateway(device: routeService.device)
            }

            let expectedManagedRoutes: [AdditionalRoute]
            if let routeGateway {
                expectedManagedRoutes = managedRoutes.map {
                    AdditionalRoute(
                        destination: $0.destination,
                        netmask: $0.netmask,
                        gateway: routeGateway
                    )
                }
            } else {
                expectedManagedRoutes = []
            }
            let installedManagedRouteSet = Set(installedManagedRoutes)
            let matchingManagedRouteCount = expectedManagedRoutes.reduce(into: 0) { count, route in
                if installedManagedRouteSet.contains(route) {
                    count += 1
                }
            }

            var managedResolution: RouteResolution?
            var verifiedDestinationCount = 0
            for (index, destination) in verificationDestinations.enumerated() {
                let resolution = try? await routeResolution(to: destination)
                if index == 0 {
                    managedResolution = resolution
                }
                if let routeGateway,
                   let routeService,
                   resolution?.interface == routeService.device,
                   resolution?.gateway == routeGateway {
                    verifiedDestinationCount += 1
                }
            }
            let defaultResolution = try? await routeResolution(to: "default")

            return AutomaticRouteSnapshot(
                isEnabled: isEnabled,
                routeAccessPointName: accessPoints.route.serviceName,
                routeAccessPointDevice: routeService?.device,
                routeAccessPointIsActive: networkState.routeIsActive,
                companionAccessPointName: accessPoints.companion.serviceName,
                companionAccessPointDevice: companionService?.device,
                companionAccessPointIsActive: networkState.companionIsActive,
                routeGateway: routeGateway,
                installedManagedRouteCount: installedManagedRoutes.count,
                matchingManagedRouteCount: matchingManagedRouteCount,
                expectedManagedRouteCount: managedRoutes.count,
                verifiedDestinationCount: verifiedDestinationCount,
                expectedVerificationCount: verificationDestinations.count,
                managedDestinationInterface: managedResolution?.interface,
                managedDestinationGateway: managedResolution?.gateway,
                defaultRouteInterface: defaultResolution?.interface,
                defaultRouteGateway: defaultResolution?.gateway
            )
        } catch {
            return AutomaticRouteSnapshot(
                isEnabled: isEnabled,
                routeAccessPointName: accessPoints.route.serviceName,
                routeAccessPointDevice: nil,
                routeAccessPointIsActive: false,
                companionAccessPointName: accessPoints.companion.serviceName,
                companionAccessPointDevice: nil,
                companionAccessPointIsActive: false,
                routeGateway: nil,
                installedManagedRouteCount: 0,
                matchingManagedRouteCount: 0,
                expectedManagedRouteCount: managedRoutes.count,
                verifiedDestinationCount: 0,
                expectedVerificationCount: verificationDestinations.count,
                managedDestinationInterface: nil,
                managedDestinationGateway: nil,
                defaultRouteInterface: nil,
                defaultRouteGateway: nil
            )
        }
    }

    private func startMonitoringIfNeeded() {
        guard dynamicStore == nil else {
            return
        }

        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let store = SCDynamicStoreCreate(
            nil,
            "com.qianyushi.turnintoserver.automatic-route" as CFString,
            automaticRouteDynamicStoreCallback,
            &context
        ) else {
            NSLog("turnintoserver automatic route could not create a SystemConfiguration store")
            return
        }

        let keys = ["State:/Network/Global/IPv4"] as CFArray
        let patterns = [
            "State:/Network/Interface/.*/IPv4",
            "State:/Network/Interface/.*/Link",
            "State:/Network/Service/.*/DNS"
        ] as CFArray

        guard SCDynamicStoreSetNotificationKeys(store, keys, patterns),
              let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) else {
            NSLog("turnintoserver automatic route could not subscribe to network changes")
            return
        }

        dynamicStore = store
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func scheduleReconcile() {
        reconcileWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            Task { @MainActor in
                do {
                    try await self.reconcile()
                } catch {
                    NSLog("turnintoserver automatic route reconcile failed: \(error.localizedDescription)")
                }
            }
        }
        reconcileWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func reconcile() async throws {
        if isReconciling {
            needsAnotherReconcile = true
            while isReconciling {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try await reconcile()
            return
        }

        isReconciling = true
        defer {
            isReconciling = false
        }

        repeat {
            needsAnotherReconcile = false
            try await reconcileOnce(isEnabled: desiredEnabled)
        } while needsAnotherReconcile
    }

    private func reconcileOnce(isEnabled: Bool) async throws {
        let services = try await networkServices()
        try await removeManagedRoutesFromRetiredServices(availableServices: services)

        guard let routeService = services.first(where: {
            $0.name == accessPoints.route.serviceName
        }) else {
            throw AutomaticRouteError.networkServiceUnavailable(
                accessPoints.route.serviceName
            )
        }
        let companionService = services.first {
            $0.name == accessPoints.companion.serviceName
        }
        let networkState = try await detectedNetworkState(
            routeService: routeService,
            companionService: companionService
        )
        let shouldInstallManagedRoutes = isEnabled
            && networkState.routeIsActive
            && networkState.companionIsActive

        var desiredGateway: String?
        if shouldInstallManagedRoutes {
            desiredGateway = try await currentGateway(device: routeService.device)
        }

        let currentRoutes = try await additionalRoutes(
            serviceName: accessPoints.route.serviceName
        )
        let preservedRoutes = currentRoutes.filter {
            !isOwnedRoute($0.key)
        }
        let currentManagedRoutes = currentRoutes.filter {
            isOwnedRoute($0.key)
        }

        if let desiredGateway {
            let desiredRoutes = managedRoutes.map {
                AdditionalRoute(
                    destination: $0.destination,
                    netmask: $0.netmask,
                    gateway: desiredGateway
                )
            }
            guard currentManagedRoutes.count != desiredRoutes.count
                    || Set(currentManagedRoutes) != Set(desiredRoutes) else {
                finishRouteMigration()
                return
            }

            try await applyAdditionalRoutes(
                preservedRoutes + desiredRoutes,
                serviceName: accessPoints.route.serviceName
            )
            NSLog(
                "turnintoserver automatic route enabled \(desiredRoutes.count) internal routes through \(desiredGateway) on \(routeService.device)"
            )
        } else if !currentManagedRoutes.isEmpty {
            try await applyAdditionalRoutes(
                preservedRoutes,
                serviceName: accessPoints.route.serviceName
            )
            NSLog("turnintoserver automatic route removed \(currentManagedRoutes.count) managed internal routes")
        }

        finishRouteMigration()
    }

    private func finishRouteMigration() {
        retiredManagedRouteKeys.removeAll()
        retiredRouteServiceNames.removeAll()
        defaults.set(true, forKey: AppDefaultsKey.automaticRoutingLegacy196MigrationCompleted)
        defaults.set(
            managedCIDRs.map(\.stringValue),
            forKey: AppDefaultsKey.automaticRoutingLastAppliedCIDRs
        )
        defaults.set(
            accessPoints.route.serviceName,
            forKey: AppDefaultsKey.automaticRoutingLastAppliedRouteServiceName
        )
    }

    private func detectedNetworkState(
        routeService: AutomaticRouteNetworkService?,
        companionService: AutomaticRouteNetworkService?
    ) async throws -> DetectedNetworkState {
        let routeIsActive: Bool
        if let routeService {
            routeIsActive = try await accessPointIsActive(
                accessPoints.route,
                service: routeService
            )
        } else {
            routeIsActive = false
        }

        let companionIsActive: Bool
        if let companionService {
            companionIsActive = try await accessPointIsActive(
                accessPoints.companion,
                service: companionService
            )
        } else {
            companionIsActive = false
        }

        return DetectedNetworkState(
            routeIsActive: routeIsActive,
            companionIsActive: companionIsActive
        )
    }

    private func accessPointIsActive(
        _ accessPoint: AutomaticRouteAccessPoint,
        service: AutomaticRouteNetworkService
    ) async throws -> Bool {
        let summary = try await ShellRunner.run(
            "/usr/sbin/ipconfig",
            arguments: ["getsummary", service.device]
        )
        return summary.exitCode == 0
            && summary.stdout.contains("LinkStatusActive : TRUE")
            && (accessPoint.detectionSignature.isEmpty
                || summary.stdout.localizedCaseInsensitiveContains(
                    accessPoint.detectionSignature
                ))
    }

    private func currentGateway(device: String) async throws -> String {
        let result = try await ShellRunner.run(
            "/sbin/route",
            arguments: ["-n", "get", "-ifscope", device, "default"]
        )
        guard result.exitCode == 0 else {
            throw AutomaticRouteError.commandFailed(result.combinedOutput)
        }

        for line in result.stdout.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0] == "gateway:" else {
                continue
            }

            let gateway = String(fields[1])
            guard Self.isIPv4Address(gateway) else {
                break
            }
            return gateway
        }

        throw AutomaticRouteError.gatewayUnavailable
    }

    private func routeResolution(to destination: String) async throws -> RouteResolution {
        let result = try await ShellRunner.run("/sbin/route", arguments: ["-n", "get", destination])
        guard result.exitCode == 0 else {
            throw AutomaticRouteError.commandFailed(result.combinedOutput)
        }

        var interface: String?
        var gateway: String?
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else {
                continue
            }

            if fields[0] == "interface:" {
                interface = String(fields[1])
            } else if fields[0] == "gateway:" {
                gateway = String(fields[1])
            }
        }

        return RouteResolution(interface: interface, gateway: gateway)
    }

    private func additionalRoutes(serviceName: String) async throws -> [AdditionalRoute] {
        let result = try await ShellRunner.run(
            "/usr/sbin/networksetup",
            arguments: ["-getadditionalroutes", serviceName]
        )
        guard result.exitCode == 0 else {
            throw AutomaticRouteError.commandFailed(result.combinedOutput)
        }

        return result.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> AdditionalRoute? in
                let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard fields.count >= 3,
                      Self.isIPv4Address(fields[0]),
                      Self.isIPv4Address(fields[1]),
                      Self.isIPv4Address(fields[2]) else {
                    return nil
                }

                return AdditionalRoute(
                    destination: fields[0],
                    netmask: fields[1],
                    gateway: fields[2]
                )
            }
    }

    private func applyAdditionalRoutes(
        _ routes: [AdditionalRoute],
        serviceName: String
    ) async throws {
        var arguments = ["-setadditionalroutes", serviceName]
        for route in routes {
            arguments.append(contentsOf: [route.destination, route.netmask, route.gateway])
        }

        let result = try await ShellRunner.run("/usr/sbin/networksetup", arguments: arguments)
        guard result.exitCode == 0 else {
            throw AutomaticRouteError.commandFailed(result.combinedOutput)
        }
    }

    private func removeManagedRoutesFromRetiredServices(
        availableServices: [AutomaticRouteNetworkService]
    ) async throws {
        let availableNames = Set(availableServices.map(\.name))
        for serviceName in retiredRouteServiceNames.sorted() {
            guard availableNames.contains(serviceName) else {
                continue
            }
            let routes = try await additionalRoutes(serviceName: serviceName)
            let preservedRoutes = routes.filter { !isOwnedRoute($0.key) }
            guard preservedRoutes.count != routes.count else {
                continue
            }
            try await applyAdditionalRoutes(preservedRoutes, serviceName: serviceName)
            NSLog(
                "turnintoserver automatic route removed \(routes.count - preservedRoutes.count) managed routes from retired service \(serviceName)"
            )
        }
    }

    private func networkServices() async throws -> [AutomaticRouteNetworkService] {
        let result = try await ShellRunner.run(
            "/usr/sbin/networksetup",
            arguments: ["-listnetworkserviceorder"]
        )
        guard result.exitCode == 0 else {
            throw AutomaticRouteError.commandFailed(result.combinedOutput)
        }

        var services: [AutomaticRouteNetworkService] = []
        var pendingServiceName: String?
        for rawLine in result.stdout.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("("),
               let closingParenthesis = line.firstIndex(of: ")"),
               Int(line[line.index(after: line.startIndex)..<closingParenthesis]) != nil {
                var serviceName = line[line.index(after: closingParenthesis)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if serviceName.hasPrefix("*") {
                    serviceName.removeFirst()
                    serviceName = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                pendingServiceName = serviceName.isEmpty ? nil : serviceName
                continue
            }

            guard let serviceName = pendingServiceName,
                  let deviceMarker = line.range(of: "Device:") else {
                continue
            }
            let deviceSuffix = line[deviceMarker.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let device = deviceSuffix.split(separator: ")", maxSplits: 1)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !device.isEmpty {
                services.append(
                    AutomaticRouteNetworkService(name: serviceName, device: device)
                )
            }
            pendingServiceName = nil
        }
        return services
    }

    private static func isIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return false
        }

        return parts.allSatisfy { part in
            guard let number = Int(part) else {
                return false
            }
            return number >= 0 && number <= 255
        }
    }
}

enum AutomaticRouteError: LocalizedError {
    case commandFailed(String)
    case configurationChanging
    case gatewayUnavailable
    case networkServiceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? AppText.commandFailed : trimmed
        case .configurationChanging:
            return AppText.automaticRouteSaving
        case .gatewayUnavailable:
            return AppText.automaticRouteGatewayUnavailable
        case .networkServiceUnavailable(let name):
            return AppText.automaticRouteNetworkServiceUnavailable(name)
        }
    }
}

struct AudioMuteManager {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func reconcile(shouldMute: Bool) async throws {
        if shouldMute {
            try await muteAndRememberPreviousState()
        } else {
            try await restorePreviousStateIfNeeded()
        }
    }

    private func muteAndRememberPreviousState() async throws {
        let restoreIsPending = defaults.bool(forKey: AppDefaultsKey.audioMuteRestorePending)
        if !restoreIsPending {
            let wasMuted = try await currentOutputMuted()
            defaults.set(wasMuted, forKey: AppDefaultsKey.audioMuteRestoreWasMuted)
            defaults.set(true, forKey: AppDefaultsKey.audioMuteRestorePending)
        }

        do {
            try await setOutputMuted(true)
        } catch {
            if !restoreIsPending {
                defaults.removeObject(forKey: AppDefaultsKey.audioMuteRestoreWasMuted)
                defaults.removeObject(forKey: AppDefaultsKey.audioMuteRestorePending)
            }
            throw error
        }
    }

    private func restorePreviousStateIfNeeded() async throws {
        guard defaults.bool(forKey: AppDefaultsKey.audioMuteRestorePending) else {
            return
        }

        let wasMuted = defaults.bool(forKey: AppDefaultsKey.audioMuteRestoreWasMuted)
        try await setOutputMuted(wasMuted)
        defaults.removeObject(forKey: AppDefaultsKey.audioMuteRestoreWasMuted)
        defaults.removeObject(forKey: AppDefaultsKey.audioMuteRestorePending)
    }

    private func currentOutputMuted() async throws -> Bool {
        let result = try await ShellRunner.run(
            "/usr/bin/osascript",
            arguments: ["-e", "output muted of (get volume settings)"]
        )
        guard result.exitCode == 0 else {
            throw AudioMuteError.commandFailed(result.combinedOutput)
        }

        switch result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            throw AudioMuteError.invalidState
        }
    }

    private func setOutputMuted(_ isMuted: Bool) async throws {
        let script = isMuted ? "set volume with output muted" : "set volume without output muted"
        let result = try await ShellRunner.run("/usr/bin/osascript", arguments: ["-e", script])
        guard result.exitCode == 0 else {
            throw AudioMuteError.commandFailed(result.combinedOutput)
        }
    }
}

enum AudioMuteError: LocalizedError {
    case commandFailed(String)
    case invalidState

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? AppText.commandFailed : trimmed
        case .invalidState:
            return AppText.audioMuteStateUnavailable
        }
    }
}
