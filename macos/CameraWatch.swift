import CoreMediaIO
import Dispatch
import Foundation

struct CameraWatchConfig: Decodable {
    var webhookUrl: String?
    var webhookUrlSignOff: String?
    var pollIntervalSeconds: Int?
    var shortcutTriggersEnabled: Bool?
    var cameraActiveShortcut: String?
    var cameraInactiveShortcut: String?
    var shortcutTimeoutSeconds: Int?
    var legacyFocusSyncEnabled: Bool?
    var legacyFocusOnShortcut: String?
    var legacyFocusOffShortcut: String?
    var legacyFocusShortcutTimeoutSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case webhookUrl = "WebhookUrl"
        case webhookUrlSignOff = "WebhookUrlSignOff"
        case pollIntervalSeconds = "PollIntervalSeconds"
        case shortcutTriggersEnabled = "ShortcutTriggersEnabled"
        case cameraActiveShortcut = "CameraActiveShortcut"
        case cameraInactiveShortcut = "CameraInactiveShortcut"
        case shortcutTimeoutSeconds = "ShortcutTimeoutSeconds"
        case legacyFocusSyncEnabled = "FocusSyncEnabled"
        case legacyFocusOnShortcut = "FocusOnShortcut"
        case legacyFocusOffShortcut = "FocusOffShortcut"
        case legacyFocusShortcutTimeoutSeconds = "FocusShortcutTimeoutSeconds"
    }
}

struct RuntimeOptions {
    var configPath = NSString(string: "~/Library/Application Support/CameraWatch/config.json").expandingTildeInPath
    var logPath = NSString(string: "~/Library/Logs/CameraWatch/CameraWatch.log").expandingTildeInPath
    var pollOverride: Int?
    var runOnce = false
    var dryRun = false
    var testNotification: String?
    var testShortcut: String?
}

struct Settings {
    var webhookUrl = ""
    var webhookUrlSignOff = ""
    var pollIntervalSeconds = 15
    var shortcutTriggersEnabled = false
    var cameraActiveShortcut = "CameraWatch Camera Active"
    var cameraInactiveShortcut = "CameraWatch Camera Inactive"
    var shortcutTimeoutSeconds = 20
}

final class Logger {
    private let path: String
    private let formatter: DateFormatter

    init(path: String) {
        self.path = path
        self.formatter = DateFormatter()
        self.formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    func write(_ level: String, _ message: String) {
        let entry = "[\(formatter.string(from: Date()))] \(level): \(message)"
        print(entry)

        do {
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = (entry + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: path) {
                    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                }
            }
        } catch {
            print("[\(formatter.string(from: Date()))] ERROR: Failed to write log file: \(error)")
        }
    }
}

func usage() {
    print("""
    Usage: CameraWatch [options]

    Options:
      --config PATH                 Config JSON path
      --log PATH                    Log file path
      --poll SECONDS                Override poll interval
      --once                        Check camera state once and exit
      --dry-run                     Log actions without sending webhooks or running shortcuts
      --test-notification on|off    Send or log a test webhook transition
      --test-shortcut on|off        Run or log a test camera transition shortcut
      --help                        Show this help
    """)
}

func parseArguments(_ args: [String]) -> RuntimeOptions {
    var options = RuntimeOptions()
    var index = 1

    func requireValue(_ name: String) -> String {
        guard index + 1 < args.count else {
            fputs("Missing value for \(name)\n", stderr)
            exit(64)
        }
        index += 1
        return args[index]
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--config":
            options.configPath = NSString(string: requireValue(arg)).expandingTildeInPath
        case "--log":
            options.logPath = NSString(string: requireValue(arg)).expandingTildeInPath
        case "--poll":
            let value = requireValue(arg)
            guard let seconds = Int(value), seconds > 0 else {
                fputs("--poll must be a positive integer\n", stderr)
                exit(64)
            }
            options.pollOverride = seconds
        case "--once":
            options.runOnce = true
        case "--dry-run":
            options.dryRun = true
        case "--test-notification":
            let value = requireValue(arg)
            guard value == "on" || value == "off" else {
                fputs("--test-notification must be 'on' or 'off'\n", stderr)
                exit(64)
            }
            options.testNotification = value
        case "--test-shortcut", "--test-focus":
            let value = requireValue(arg)
            guard value == "on" || value == "off" else {
                fputs("\(arg) must be 'on' or 'off'\n", stderr)
                exit(64)
            }
            options.testShortcut = value
        case "--help", "-h":
            usage()
            exit(0)
        default:
            fputs("Unknown option: \(arg)\n", stderr)
            usage()
            exit(64)
        }
        index += 1
    }

    return options
}

func loadSettings(options: RuntimeOptions, logger: Logger) -> Settings {
    var settings = Settings()

    if FileManager.default.fileExists(atPath: options.configPath) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: options.configPath))
            let config = try JSONDecoder().decode(CameraWatchConfig.self, from: data)

            settings.webhookUrl = config.webhookUrl ?? settings.webhookUrl
            settings.webhookUrlSignOff = config.webhookUrlSignOff ?? settings.webhookUrlSignOff
            settings.pollIntervalSeconds = config.pollIntervalSeconds ?? settings.pollIntervalSeconds
            settings.shortcutTriggersEnabled = config.shortcutTriggersEnabled
                ?? config.legacyFocusSyncEnabled
                ?? settings.shortcutTriggersEnabled
            settings.cameraActiveShortcut = config.cameraActiveShortcut
                ?? config.legacyFocusOnShortcut
                ?? settings.cameraActiveShortcut
            settings.cameraInactiveShortcut = config.cameraInactiveShortcut
                ?? config.legacyFocusOffShortcut
                ?? settings.cameraInactiveShortcut
            settings.shortcutTimeoutSeconds = config.shortcutTimeoutSeconds
                ?? config.legacyFocusShortcutTimeoutSeconds
                ?? settings.shortcutTimeoutSeconds
            logger.write("INFO", "Loaded config from \(options.configPath)")
        } catch {
            logger.write("ERROR", "Failed to load config from \(options.configPath): \(error)")
        }
    } else {
        logger.write("INFO", "Config file not found at \(options.configPath); using defaults and CLI options")
    }

    if let pollOverride = options.pollOverride {
        settings.pollIntervalSeconds = pollOverride
    }
    settings.pollIntervalSeconds = max(1, settings.pollIntervalSeconds)
    settings.shortcutTimeoutSeconds = max(1, settings.shortcutTimeoutSeconds)

    return settings
}

func redactedUrl(_ url: String) -> String {
    guard !url.isEmpty, let parsed = URL(string: url) else {
        return "(none)"
    }

    var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false)
    if let path = components?.path, !path.isEmpty {
        let parts = path.split(separator: "/")
        if parts.count > 1 {
            components?.path = "/" + parts.dropLast().joined(separator: "/") + "/REDACTED"
        } else {
            components?.path = "/REDACTED"
        }
    }
    components?.query = nil
    return components?.string ?? "(redacted)"
}

func propertyAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
    return CMIOObjectPropertyAddress(
        mSelector: selector,
        mScope: UInt32(kCMIOObjectPropertyScopeGlobal),
        mElement: UInt32(kCMIOObjectPropertyElementMain)
    )
}

func cameraDevices() -> [CMIODeviceID] {
    var address = propertyAddress(UInt32(kCMIOHardwarePropertyDevices))
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(
        CMIOObjectID(kCMIOObjectSystemObject),
        &address,
        0,
        nil,
        &size
    ) == noErr else {
        return []
    }

    let count = Int(size) / MemoryLayout<CMIODeviceID>.size
    guard count > 0 else {
        return []
    }

    var devices = [CMIODeviceID](repeating: 0, count: count)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(
        CMIOObjectID(kCMIOObjectSystemObject),
        &address,
        0,
        nil,
        size,
        &used,
        &devices
    ) == noErr else {
        return []
    }

    return devices
}

func cameraName(_ device: CMIODeviceID) -> String {
    var address = propertyAddress(UInt32(kCMIOObjectPropertyName))
    let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var used: UInt32 = 0
    var name: Unmanaged<CFString>?
    let status = CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &name)
    guard status == noErr, let name else {
        return "Camera \(device)"
    }
    return name.takeRetainedValue() as String
}

func isCameraRunning(_ device: CMIODeviceID) -> Bool {
    var address = propertyAddress(UInt32(kCMIODevicePropertyDeviceIsRunningSomewhere))
    let size = UInt32(MemoryLayout<UInt32>.size)
    var used: UInt32 = 0
    var isRunning: UInt32 = 0
    let status = CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &isRunning)
    return status == noErr && isRunning != 0
}

func activeCameraNames() -> [String] {
    return cameraDevices()
        .filter(isCameraRunning)
        .map(cameraName)
        .sorted()
}

func jsonBody(user: String, processes: String) -> Data {
    let payload = ["user": user, "processes": processes]
    return try! JSONSerialization.data(withJSONObject: payload, options: [])
}

func sendWebhook(url: String, processes: String, type: String, dryRun: Bool, logger: Logger) -> Bool {
    guard !url.isEmpty else {
        logger.write("INFO", "No \(type) webhook URL configured; skipping notification")
        return true
    }

    if dryRun {
        logger.write("INFO", "Dry run: would POST \(type) webhook to \(redactedUrl(url)) with processes='\(processes)'")
        return true
    }

    guard let endpoint = URL(string: url) else {
        logger.write("ERROR", "Invalid \(type) webhook URL: \(redactedUrl(url))")
        return false
    }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonBody(user: NSUserName(), processes: processes)

    let semaphore = DispatchSemaphore(value: 0)
    var succeeded = false
    var failureDescription = ""

    URLSession.shared.dataTask(with: request) { _, response, error in
        if let error = error {
            failureDescription = error.localizedDescription
        } else if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            failureDescription = "HTTP \(httpResponse.statusCode)"
        } else {
            succeeded = true
        }
        semaphore.signal()
    }.resume()

    if semaphore.wait(timeout: .now() + 30) == .timedOut {
        logger.write("ERROR", "Timed out sending \(type) webhook to \(redactedUrl(url))")
        return false
    }

    if succeeded {
        logger.write("INFO", "Sent \(type) webhook to \(redactedUrl(url))")
    } else {
        logger.write("ERROR", "Failed to send \(type) webhook to \(redactedUrl(url)): \(failureDescription)")
    }
    return succeeded
}

func runShortcut(name: String, type: String, timeoutSeconds: Int, dryRun: Bool, logger: Logger) -> Bool {
    guard !name.isEmpty else {
        logger.write("INFO", "No \(type) Shortcut configured; skipping shortcut trigger")
        return true
    }

    if dryRun {
        logger.write("INFO", "Dry run: would run \(type) Shortcut '\(name)'")
        return true
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    process.arguments = ["run", name]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
    } catch {
        logger.write("ERROR", "Failed to start \(type) Shortcut '\(name)': \(error)")
        return false
    }

    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        process.waitUntilExit()
        semaphore.signal()
    }

    if semaphore.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
        process.terminate()
        logger.write("ERROR", "Timed out running \(type) Shortcut '\(name)' after \(timeoutSeconds)s")
        return false
    }

    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if process.terminationStatus == 0 {
        logger.write("INFO", "Ran \(type) Shortcut '\(name)'")
        return true
    }

    let suffix = output.isEmpty ? "" : ": \(output)"
    logger.write("ERROR", "Shortcut '\(name)' failed with exit code \(process.terminationStatus)\(suffix)")
    return false
}

func handleTransition(active: Bool, cameraNames: [String], settings: Settings, options: RuntimeOptions, logger: Logger) -> Bool {
    let type = active ? "on" : "off"
    let processes = active ? cameraNames.joined(separator: ",") : ""
    let webhookUrl = active ? settings.webhookUrl : settings.webhookUrlSignOff

    let webhookSucceeded = sendWebhook(
        url: webhookUrl,
        processes: processes,
        type: type,
        dryRun: options.dryRun,
        logger: logger
    )

    if settings.shortcutTriggersEnabled {
        let shortcut = active ? settings.cameraActiveShortcut : settings.cameraInactiveShortcut
        _ = runShortcut(
            name: shortcut,
            type: type,
            timeoutSeconds: settings.shortcutTimeoutSeconds,
            dryRun: options.dryRun,
            logger: logger
        )
    }

    return webhookSucceeded
}

let options = parseArguments(CommandLine.arguments)
let logger = Logger(path: options.logPath)
let settings = loadSettings(options: options, logger: logger)

let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
var shouldStop = false
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
signalSource.setEventHandler {
    logger.write("INFO", "Received termination signal")
    shouldStop = true
}
signalSource.resume()

let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interruptSource.setEventHandler {
    logger.write("INFO", "Received interrupt signal")
    shouldStop = true
}
interruptSource.resume()

if let testNotification = options.testNotification {
    let active = testNotification == "on"
    _ = handleTransition(
        active: active,
        cameraNames: active ? ["CameraWatch Test Camera"] : [],
        settings: settings,
        options: options,
        logger: logger
    )
    exit(0)
}

if let testShortcut = options.testShortcut {
    let shortcut = testShortcut == "on" ? settings.cameraActiveShortcut : settings.cameraInactiveShortcut
    _ = runShortcut(
        name: shortcut,
        type: testShortcut,
        timeoutSeconds: settings.shortcutTimeoutSeconds,
        dryRun: options.dryRun,
        logger: logger
    )
    exit(0)
}

logger.write("INFO", "Starting CameraWatch for macOS; poll interval \(settings.pollIntervalSeconds)s; shortcut triggers \(settings.shortcutTriggersEnabled ? "enabled" : "disabled")")

var wasActive = false
var pendingWebhookTransition: Bool?

while !shouldStop {
    RunLoop.current.run(mode: .default, before: Date())

    let cameras = activeCameraNames()
    let isActive = !cameras.isEmpty
    logger.write("INFO", "Active camera devices: \(isActive ? cameras.joined(separator: ",") : "(none)")")

    if options.runOnce {
        exit(isActive ? 0 : 1)
    }

    if isActive != wasActive {
        logger.write("INFO", isActive ? "START \(cameras.joined(separator: ","))" : "STOP")
        let succeeded = handleTransition(
            active: isActive,
            cameraNames: cameras,
            settings: settings,
            options: options,
            logger: logger
        )
        pendingWebhookTransition = succeeded ? nil : isActive
        wasActive = isActive
    } else if let pending = pendingWebhookTransition, pending == isActive {
        logger.write("INFO", "Retrying pending \(pending ? "on" : "off") webhook transition")
        let succeeded = sendWebhook(
            url: pending ? settings.webhookUrl : settings.webhookUrlSignOff,
            processes: pending ? cameras.joined(separator: ",") : "",
            type: pending ? "on" : "off",
            dryRun: options.dryRun,
            logger: logger
        )
        if succeeded {
            pendingWebhookTransition = nil
        }
    } else {
        pendingWebhookTransition = nil
    }

    Thread.sleep(forTimeInterval: TimeInterval(settings.pollIntervalSeconds))
}

logger.write("INFO", "Stopping CameraWatch for macOS")
