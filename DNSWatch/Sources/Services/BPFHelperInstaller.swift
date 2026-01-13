import Foundation

enum BPFHelperInstaller {
    enum InstallError: LocalizedError {
        case missingResource
        case installFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingResource:
                return "Missing BPF helper installer in app bundle."
            case let .installFailed(message):
                return message.isEmpty ? "BPF helper installation failed." : message
            }
        }
    }

    private static let helperSubdirectory = "BPFHelper"
    private static let launchDaemonLabel = "com.dnswatch.bpf-permissions"
    private static let launchDaemonPath = "/Library/LaunchDaemons/\(launchDaemonLabel).plist"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: launchDaemonPath)
    }

    static func install() throws {
        try runPrivilegedScript(named: "install_bpf_helper")
    }

    static func uninstall() throws {
        try runPrivilegedScript(named: "uninstall_bpf_helper")
    }

    private static func runPrivilegedScript(named scriptName: String) throws {
        guard let scriptURL = Bundle.main.url(
            forResource: scriptName,
            withExtension: "sh",
            subdirectory: helperSubdirectory
        ) else {
            throw InstallError.missingResource
        }

        let userName = NSUserName()
        let command = "\"\(scriptURL.path)\" \"\(userName)\""
        let appleScript = "do shell script \"\(escapeForAppleScript(command))\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw InstallError.installFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
