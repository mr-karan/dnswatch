import Darwin
import Foundation

/// Callback type for received DNS queries
typealias DNSQueryHandler = (DNSQuery) -> Void

/// Wraps libpcap for capturing DNS packets
final class PacketCapture {
    // MARK: - Properties

    private var pcapHandle: OpaquePointer?
    private var captureThread: Thread?
    private var isCapturing = false
    private let dnsParser = DNSParser()
    private var queryHandler: DNSQueryHandler?

    private let captureQueue = DispatchQueue(label: "com.dnswatch.capture", qos: .userInitiated)

    // MARK: - Public Interface

    /// List available network interfaces
    static func availableInterfaces() -> [String] {
        var interfaces: [String] = []
        var alldevs: UnsafeMutablePointer<pcap_if_t>?
        var errbuf = [CChar](repeating: 0, count: Int(PCAP_ERRBUF_SIZE))

        if pcap_findalldevs(&alldevs, &errbuf) == 0 {
            var device = alldevs
            while device != nil {
                if let name = device?.pointee.name {
                    interfaces.append(String(cString: name))
                }
                device = device?.pointee.next
            }
            pcap_freealldevs(alldevs)
        }

        return interfaces
    }

    /// Start capturing DNS packets on the specified interface
    /// - Parameters:
    ///   - interface: Network interface name (e.g., "en0", "any")
    ///   - handler: Callback invoked for each DNS query
    func startCapture(interface: String = "any", handler: @escaping DNSQueryHandler) throws {
        guard !self.isCapturing else { return }

        self.queryHandler = handler

        var errbuf = [CChar](repeating: 0, count: Int(PCAP_ERRBUF_SIZE))

        // Open the capture device
        self.pcapHandle = pcap_open_live(
            interface,
            65535, // Snapshot length
            0, // Non-promiscuous mode
            100, // Read timeout in ms
            &errbuf
        )

        guard self.pcapHandle != nil else {
            let errorMessage = String(cString: errbuf)
            throw CaptureError.openFailed(errorMessage)
        }

        // Set BPF filter for DNS traffic (UDP port 53)
        var filterProgram = bpf_program()
        let filterExpression = "udp port 53"

        if pcap_compile(self.pcapHandle, &filterProgram, filterExpression, 1, UInt32(PCAP_NETMASK_UNKNOWN)) == -1 {
            let errorMessage = String(cString: pcap_geterr(pcapHandle))
            if let handle = pcapHandle {
                pcap_close(handle)
            }
            self.pcapHandle = nil
            throw CaptureError.filterCompileFailed(errorMessage)
        }

        if pcap_setfilter(self.pcapHandle, &filterProgram) == -1 {
            let errorMessage = String(cString: pcap_geterr(pcapHandle))
            pcap_freecode(&filterProgram)
            if let handle = pcapHandle {
                pcap_close(handle)
            }
            self.pcapHandle = nil
            throw CaptureError.filterSetFailed(errorMessage)
        }

        pcap_freecode(&filterProgram)

        self.isCapturing = true

        // Start capture loop on background thread
        self.captureThread = Thread { [weak self] in
            self?.captureLoop()
        }
        self.captureThread?.name = "DNSWatch.PacketCapture"
        self.captureThread?.start()
    }

    /// Stop capturing packets
    func stopCapture() {
        guard self.isCapturing else { return }

        self.isCapturing = false

        if let handle = pcapHandle {
            pcap_breakloop(handle)
        }

        // Wait for thread to finish
        while self.captureThread?.isExecuting == true {
            Thread.sleep(forTimeInterval: 0.01)
        }

        if let handle = pcapHandle {
            pcap_close(handle)
            self.pcapHandle = nil
        }

        self.captureThread = nil
    }

    /// Check if currently capturing
    var capturing: Bool {
        self.isCapturing
    }

    // MARK: - Private Methods

    private func captureLoop() {
        guard let handle = pcapHandle else { return }

        while self.isCapturing {
            var header: UnsafeMutablePointer<pcap_pkthdr>?
            var packetData: UnsafePointer<UInt8>?

            let result = pcap_next_ex(handle, &header, &packetData)

            switch result {
            case 1:
                // Packet received
                if let header, let packetData {
                    let length = Int(header.pointee.caplen)
                    let data = Data(bytes: packetData, count: length)
                    self.processPacket(data)
                }
            case 0:
                // Timeout, continue
                continue
            case -1:
                // Error
                if self.isCapturing {
                    let errorMessage = String(cString: pcap_geterr(handle))
                    print("Capture error: \(errorMessage)")
                }
            case -2:
                // Breakloop called
                break
            default:
                break
            }
        }
    }

    private func processPacket(_ packetData: Data) {
        guard let dnsPayload = dnsParser.extractDNSPayload(from: packetData),
              let query = dnsParser.parse(data: dnsPayload)
        else {
            return
        }

        // Only report queries (not responses) to avoid duplicates
        // Or report both if we want to track response times
        if !query.isResponse {
            DispatchQueue.main.async { [weak self] in
                self?.queryHandler?(query)
            }
        }
    }

    // MARK: - Errors

    enum CaptureError: Error, LocalizedError {
        case openFailed(String)
        case filterCompileFailed(String)
        case filterSetFailed(String)

        var errorDescription: String? {
            switch self {
            case let .openFailed(msg):
                "Failed to open capture device: \(msg)"
            case let .filterCompileFailed(msg):
                "Failed to compile BPF filter: \(msg)"
            case let .filterSetFailed(msg):
                "Failed to set BPF filter: \(msg)"
            }
        }
    }
}

// MARK: - libpcap C Interface

// These declarations allow Swift to use the libpcap C library
// The actual symbols are resolved at link time against libpcap

private let PCAP_ERRBUF_SIZE: Int32 = 256
private let PCAP_NETMASK_UNKNOWN: UInt32 = 0xFFFF_FFFF

private struct pcap_if_t {
    var next: UnsafeMutablePointer<pcap_if_t>?
    var name: UnsafePointer<CChar>?
    var description: UnsafePointer<CChar>?
    var addresses: OpaquePointer?
    var flags: UInt32
}

private struct pcap_pkthdr {
    var ts: timeval
    var caplen: UInt32
    var len: UInt32
}

private struct bpf_program {
    var bf_len: UInt32
    var bf_insns: OpaquePointer?

    init() {
        self.bf_len = 0
        self.bf_insns = nil
    }
}

@_silgen_name("pcap_findalldevs")
private func pcap_findalldevs(
    _ alldevsp: UnsafeMutablePointer<UnsafeMutablePointer<pcap_if_t>?>,
    _ errbuf: UnsafeMutablePointer<CChar>
) -> Int32

@_silgen_name("pcap_freealldevs")
private func pcap_freealldevs(_ alldevs: UnsafeMutablePointer<pcap_if_t>?)

@_silgen_name("pcap_open_live")
private func pcap_open_live(
    _ device: UnsafePointer<CChar>,
    _ snaplen: Int32,
    _ promisc: Int32,
    _ to_ms: Int32,
    _ errbuf: UnsafeMutablePointer<CChar>
) -> OpaquePointer?

@_silgen_name("pcap_close")
private func pcap_close(_ p: OpaquePointer)

@_silgen_name("pcap_compile")
private func pcap_compile(
    _ p: OpaquePointer?,
    _ fp: UnsafeMutablePointer<bpf_program>,
    _ str: UnsafePointer<CChar>,
    _ optimize: Int32,
    _ netmask: UInt32
) -> Int32

@_silgen_name("pcap_setfilter")
private func pcap_setfilter(
    _ p: OpaquePointer?,
    _ fp: UnsafeMutablePointer<bpf_program>
) -> Int32

@_silgen_name("pcap_freecode")
private func pcap_freecode(_ fp: UnsafeMutablePointer<bpf_program>)

@_silgen_name("pcap_next_ex")
private func pcap_next_ex(
    _ p: OpaquePointer?,
    _ pkt_header: UnsafeMutablePointer<UnsafeMutablePointer<pcap_pkthdr>?>,
    _ pkt_data: UnsafeMutablePointer<UnsafePointer<UInt8>?>
) -> Int32

@_silgen_name("pcap_breakloop")
private func pcap_breakloop(_ p: OpaquePointer?)

@_silgen_name("pcap_geterr")
private func pcap_geterr(_ p: OpaquePointer?) -> UnsafePointer<CChar>
