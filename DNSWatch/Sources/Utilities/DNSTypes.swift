import Foundation

/// DNS Query Types (RFC 1035 + extensions)
enum DNSQueryType: UInt16, CaseIterable, Identifiable {
    case A = 1
    case NS = 2
    case CNAME = 5
    case SOA = 6
    case PTR = 12
    case MX = 15
    case TXT = 16
    case AAAA = 28
    case SRV = 33
    case HTTPS = 65
    case ANY = 255
    case unknown = 0

    var id: UInt16 { rawValue }

    var displayName: String {
        switch self {
        case .A: "A"
        case .NS: "NS"
        case .CNAME: "CNAME"
        case .SOA: "SOA"
        case .PTR: "PTR"
        case .MX: "MX"
        case .TXT: "TXT"
        case .AAAA: "AAAA"
        case .SRV: "SRV"
        case .HTTPS: "HTTPS"
        case .ANY: "ANY"
        case .unknown: "Unknown"
        }
    }

    var description: String {
        switch self {
        case .A: "IPv4 Address"
        case .NS: "Name Server"
        case .CNAME: "Canonical Name"
        case .SOA: "Start of Authority"
        case .PTR: "Pointer"
        case .MX: "Mail Exchange"
        case .TXT: "Text Record"
        case .AAAA: "IPv6 Address"
        case .SRV: "Service"
        case .HTTPS: "HTTPS Binding"
        case .ANY: "Any Record"
        case .unknown: "Unknown Type"
        }
    }

    init(rawValue: UInt16) {
        switch rawValue {
        case 1: self = .A
        case 2: self = .NS
        case 5: self = .CNAME
        case 6: self = .SOA
        case 12: self = .PTR
        case 15: self = .MX
        case 16: self = .TXT
        case 28: self = .AAAA
        case 33: self = .SRV
        case 65: self = .HTTPS
        case 255: self = .ANY
        default: self = .unknown
        }
    }
}

/// DNS Response Codes (RCODE)
enum DNSResponseCode: UInt8 {
    case noError = 0
    case formatError = 1
    case serverFailure = 2
    case nameError = 3 // NXDOMAIN
    case notImplemented = 4
    case refused = 5
    case unknown = 255

    var displayName: String {
        switch self {
        case .noError: "OK"
        case .formatError: "Format Error"
        case .serverFailure: "Server Failure"
        case .nameError: "NXDOMAIN"
        case .notImplemented: "Not Implemented"
        case .refused: "Refused"
        case .unknown: "Unknown"
        }
    }

    init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .noError
        case 1: self = .formatError
        case 2: self = .serverFailure
        case 3: self = .nameError
        case 4: self = .notImplemented
        case 5: self = .refused
        default: self = .unknown
        }
    }
}
