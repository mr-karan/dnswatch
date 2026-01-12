import Foundation

/// Intelligently detects the best network interface(s) for DNS capture
enum InterfaceDetector {
    struct InterfaceInfo {
        let name: String
        let reason: String
    }

    /// Detect the best interface(s) to capture DNS traffic on
    /// Returns interfaces in priority order
    static func detectBestInterfaces() -> [InterfaceInfo] {
        var interfaces: [InterfaceInfo] = []

        // 1. Check DNS server configuration to find the route
        if let dnsInterface = findInterfaceForDNS() {
            interfaces.append(InterfaceInfo(
                name: dnsInterface.name,
                reason: dnsInterface.reason
            ))
        }

        // 2. Add the default route interface if different
        if let defaultInterface = findDefaultRouteInterface() {
            if !interfaces.contains(where: { $0.name == defaultInterface }) {
                interfaces.append(InterfaceInfo(
                    name: defaultInterface,
                    reason: "Default route"
                ))
            }
        }

        // 3. Add common interfaces as fallback
        let commonInterfaces = ["en0", "en1", "lo0"]
        for iface in commonInterfaces {
            if !interfaces.contains(where: { $0.name == iface }) {
                if self.interfaceExists(iface) {
                    interfaces.append(InterfaceInfo(
                        name: iface,
                        reason: "Common interface"
                    ))
                }
            }
        }

        return interfaces
    }

    /// Find which interface is used to reach the DNS server
    private static func findInterfaceForDNS() -> InterfaceInfo? {
        // Get primary DNS server from scutil
        guard let dnsServer = getPrimaryDNSServer() else { return nil }

        // Special case: Tailscale MagicDNS
        if dnsServer.hasPrefix("100.100.") {
            // Find the Tailscale utun interface
            if let tailscaleInterface = findTailscaleInterface() {
                return InterfaceInfo(
                    name: tailscaleInterface,
                    reason: "Tailscale MagicDNS (\(dnsServer))"
                )
            }
        }

        // Use route command to find interface to DNS server
        if let routeInterface = findRouteToHost(dnsServer) {
            return InterfaceInfo(
                name: routeInterface,
                reason: "Route to DNS \(dnsServer)"
            )
        }

        return nil
    }

    /// Get the primary DNS server from system configuration
    private static func getPrimaryDNSServer() -> String? {
        let task = Process()
        task.launchPath = "/usr/sbin/scutil"
        task.arguments = ["--dns"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            // Parse first nameserver
            // Format: "  nameserver[0] : 192.168.1.1" or "  nameserver[0] : 2001:4860:4860::8888"
            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("nameserver[0]") || trimmed.hasPrefix("nameserver :") {
                    // Find first " : " separator (handles IPv6 addresses with colons)
                    if let separatorRange = trimmed.range(of: " : ") {
                        let address = String(trimmed[separatorRange.upperBound...])
                            .trimmingCharacters(in: .whitespaces)
                        if !address.isEmpty {
                            return address
                        }
                    }
                }
            }
        } catch {
            print("Failed to get DNS config: \(error)")
        }

        return nil
    }

    /// Find the Tailscale tunnel interface
    private static func findTailscaleInterface() -> String? {
        let task = Process()
        task.launchPath = "/sbin/ifconfig"
        task.arguments = ["-l"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            let interfaces = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: " ")

            // Find utun interfaces and check which one has Tailscale IP (100.x.x.x)
            let utunInterfaces = interfaces.filter { $0.hasPrefix("utun") }

            for utun in utunInterfaces {
                if let ip = getInterfaceIP(utun), ip.hasPrefix("100.") {
                    return utun
                }
            }

            // Fallback: return the highest numbered utun (often Tailscale)
            return utunInterfaces.sorted { a, b in
                let numA = Int(a.dropFirst(4)) ?? 0
                let numB = Int(b.dropFirst(4)) ?? 0
                return numA > numB
            }.first
        } catch {
            print("Failed to list interfaces: \(error)")
        }

        return nil
    }

    /// Get IP address of an interface
    private static func getInterfaceIP(_ interface: String) -> String? {
        let task = Process()
        task.launchPath = "/sbin/ifconfig"
        task.arguments = [interface]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("inet ") {
                    let parts = trimmed.components(separatedBy: " ")
                    if parts.count >= 2 {
                        return parts[1]
                    }
                }
            }
        } catch {
            print("Failed to get interface IP: \(error)")
        }

        return nil
    }

    /// Find the default route interface
    private static func findDefaultRouteInterface() -> String? {
        let task = Process()
        task.launchPath = "/sbin/route"
        task.arguments = ["-n", "get", "default"]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("interface:") {
                    let parts = trimmed.components(separatedBy: ":")
                    if parts.count >= 2 {
                        return parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        } catch {
            print("Failed to get default route: \(error)")
        }

        return nil
    }

    /// Find the route to a specific host
    private static func findRouteToHost(_ host: String) -> String? {
        let task = Process()
        task.launchPath = "/sbin/route"
        task.arguments = ["-n", "get", host]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }

            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("interface:") {
                    let parts = trimmed.components(separatedBy: ":")
                    if parts.count >= 2 {
                        return parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        } catch {
            print("Failed to get route to \(host): \(error)")
        }

        return nil
    }

    /// Check if interface exists
    private static func interfaceExists(_ name: String) -> Bool {
        let task = Process()
        task.launchPath = "/sbin/ifconfig"
        task.arguments = [name]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
