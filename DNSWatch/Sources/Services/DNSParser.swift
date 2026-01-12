import Foundation

/// Parses DNS protocol messages from raw packet data
final class DNSParser {
    enum ParseError: Error {
        case packetTooShort
        case invalidHeader
        case invalidQuestion
        case invalidDomainName
    }

    /// Parse a DNS message from raw UDP payload
    /// - Parameter data: Raw DNS message bytes (UDP payload, not including IP/UDP headers)
    /// - Returns: Parsed DNSQuery or nil if parsing fails
    func parse(data: Data) -> DNSQuery? {
        guard data.count >= 12 else { return nil } // DNS header is 12 bytes

        let bytes = [UInt8](data)

        // Parse DNS header
        let transactionId = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let flags = UInt16(bytes[2]) << 8 | UInt16(bytes[3])

        let isResponse = (flags & 0x8000) != 0
        let responseCode = DNSResponseCode(rawValue: UInt8(flags & 0x000F))

        let questionCount = UInt16(bytes[4]) << 8 | UInt16(bytes[5])

        guard questionCount > 0 else { return nil }

        // Parse the first question
        var offset = 12
        guard let (domain, newOffset) = parseDomainName(bytes: bytes, offset: offset) else {
            return nil
        }
        offset = newOffset

        guard offset + 4 <= bytes.count else { return nil }

        let queryTypeRaw = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        let queryType = DNSQueryType(rawValue: queryTypeRaw)

        return DNSQuery(
            domain: domain,
            queryType: queryType,
            isResponse: isResponse,
            responseCode: isResponse ? responseCode : nil,
            transactionId: transactionId
        )
    }

    /// Parse a domain name from DNS message, handling compression
    /// Protected against infinite loops from malformed compression pointers
    private func parseDomainName(bytes: [UInt8], offset: Int) -> (String, Int)? {
        var labels: [String] = []
        var currentOffset = offset
        var jumped = false
        var jumpOffset = offset

        // Track visited offsets to detect compression pointer cycles
        var visitedOffsets = Set<Int>()
        // Limit total iterations to prevent infinite loops (max domain is 253 chars)
        var iterations = 0
        let maxIterations = 128

        var foundTerminator = false
        while currentOffset < bytes.count {
            iterations += 1
            if iterations > maxIterations {
                // Malformed packet - too many iterations
                return nil
            }

            // Detect cycles in compression pointers
            if visitedOffsets.contains(currentOffset) {
                // Circular reference detected - malformed packet
                return nil
            }
            visitedOffsets.insert(currentOffset)

            let length = bytes[currentOffset]

            if length == 0 {
                // End of domain name
                if !jumped {
                    jumpOffset = currentOffset + 1
                }
                foundTerminator = true
                break
            }

            // Check top 2 bits for label type
            let labelType = length & 0xC0
            if labelType == 0xC0 {
                // Compression pointer
                guard currentOffset + 1 < bytes.count else { return nil }
                let pointerOffset = Int(UInt16(length & 0x3F) << 8 | UInt16(bytes[currentOffset + 1]))

                // Pointer must point backwards (or at least not create obvious issues)
                guard pointerOffset < bytes.count else { return nil }

                if !jumped {
                    jumpOffset = currentOffset + 2
                }
                jumped = true
                currentOffset = pointerOffset
                continue
            } else if labelType != 0x00 {
                // Reserved/extended label types (01 and 10) - reject as invalid
                return nil
            }

            // Regular label (labelType == 0x00)
            currentOffset += 1
            guard currentOffset + Int(length) <= bytes.count else { return nil }

            let labelBytes = bytes[currentOffset ..< currentOffset + Int(length)]
            // DNS labels should be valid UTF-8 (or at least ASCII)
            // If decoding fails, treat as invalid packet to avoid misattributing traffic
            guard let label = String(bytes: labelBytes, encoding: .utf8) else {
                return nil
            }
            labels.append(label)
            currentOffset += Int(length)
        }

        // Must have seen a null terminator (or followed a compression pointer that did)
        guard foundTerminator else { return nil }

        let domain = labels.joined(separator: ".")
        return (domain, jumpOffset)
    }

    /// Extract DNS payload from a full Ethernet/IP/UDP packet
    /// - Parameter packetData: Full packet including all headers
    /// - Returns: Just the DNS payload data, or nil if extraction fails
    func extractDNSPayload(from packetData: Data) -> Data? {
        let bytes = [UInt8](packetData)

        // Ethernet header: 14 bytes
        // But libpcap on loopback gives us a 4-byte header instead
        // We need to detect which type we have

        guard bytes.count > 20 else { return nil }

        var ipOffset = 0

        // Check if this looks like an Ethernet frame (starts with MAC addresses)
        // or a loopback frame (starts with protocol family)
        if bytes.count > 14 {
            // Check for IPv4 (0x0800) or IPv6 (0x86DD) EtherType at offset 12-13
            let etherType = UInt16(bytes[12]) << 8 | UInt16(bytes[13])
            if etherType == 0x0800 || etherType == 0x86DD {
                ipOffset = 14 // Standard Ethernet header
            } else {
                // Likely loopback - check for AF_INET (2) or AF_INET6 (30) at offset 0-3
                let family = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
                if family == 2 || family == 0x0200_0000 { // AF_INET in different byte orders
                    ipOffset = 4
                } else if family == 30 || family == 0x1E00_0000 { // AF_INET6
                    ipOffset = 4
                } else {
                    // Try to detect IP version directly
                    let possibleVersion = bytes[0] >> 4
                    if possibleVersion == 4 || possibleVersion == 6 {
                        ipOffset = 0 // No link layer header (raw IP)
                    } else {
                        ipOffset = 4 // Assume 4-byte loopback header
                    }
                }
            }
        }

        guard ipOffset + 20 <= bytes.count else { return nil }

        // Parse IP header
        let ipVersion = bytes[ipOffset] >> 4

        var udpOffset: Int
        if ipVersion == 4 {
            let ihl = Int(bytes[ipOffset] & 0x0F)
            // IHL must be at least 5 (20 bytes minimum IP header)
            guard ihl >= 5 else { return nil }
            let ipHeaderLength = ihl * 4
            // Validate header doesn't extend past packet
            guard ipOffset + ipHeaderLength <= bytes.count else { return nil }
            let protocol_ = bytes[ipOffset + 9]
            guard protocol_ == 17 else { return nil } // Not UDP
            udpOffset = ipOffset + ipHeaderLength
        } else if ipVersion == 6 {
            // IPv6: 40-byte fixed header, next header at offset 6
            let nextHeader = bytes[ipOffset + 6]
            guard nextHeader == 17 else { return nil } // Not UDP (simplified, ignores extension headers)
            udpOffset = ipOffset + 40
        } else {
            return nil
        }

        // UDP header: 8 bytes (src port, dst port, length, checksum)
        guard udpOffset + 8 <= bytes.count else { return nil }

        // UDP length field is at offset 4-5, includes header (8 bytes)
        let udpLength = Int(UInt16(bytes[udpOffset + 4]) << 8 | UInt16(bytes[udpOffset + 5]))
        guard udpLength >= 8 else { return nil } // Must have at least header

        let dnsOffset = udpOffset + 8
        let dnsLength = udpLength - 8

        // Validate DNS payload fits in packet
        guard dnsOffset + dnsLength <= bytes.count else { return nil }
        guard dnsLength > 0 else { return nil }

        return Data(bytes[dnsOffset ..< (dnsOffset + dnsLength)])
    }
}
