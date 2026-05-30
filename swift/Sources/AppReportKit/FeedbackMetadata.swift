import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct FeedbackMetadata: Codable, Equatable {
    public let appVersion: String
    public let build: String
    public let osName: String
    public let osVersion: String
    public let deviceModel: String
    public let locale: String
    public let clientVersion: String
    public let screen: String?

    public init(
        appVersion: String,
        build: String,
        osName: String,
        osVersion: String,
        deviceModel: String,
        locale: String,
        clientVersion: String,
        screen: String? = nil
    ) {
        self.appVersion = appVersion
        self.build = build
        self.osName = osName
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.locale = locale
        self.clientVersion = clientVersion
        self.screen = screen
    }
}

public protocol FeedbackMetadataProviding {
    func makeMetadata(screen: String?) -> FeedbackMetadata
}

public struct OperatingSystemSnapshot: Equatable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }

    public static var current: OperatingSystemSnapshot {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        let name = "iOS"
        #elseif os(macOS)
        let name = "macOS"
        #else
        let name = "unknown"
        #endif

        return OperatingSystemSnapshot(
            name: name,
            version: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )
    }
}

public enum AppReportKitVersion {
    public static let current = "0.1.0"
}

public struct SystemFeedbackMetadataProvider: FeedbackMetadataProviding {
    private let bundle: Bundle
    private let localeProvider: () -> Locale
    private let operatingSystemProvider: () -> OperatingSystemSnapshot
    private let deviceModelProvider: () -> String

    public init(
        bundle: Bundle = .main,
        localeProvider: @escaping () -> Locale = { .autoupdatingCurrent },
        operatingSystemProvider: @escaping () -> OperatingSystemSnapshot = { .current },
        deviceModelProvider: (() -> String)? = nil
    ) {
        self.bundle = bundle
        self.localeProvider = localeProvider
        self.operatingSystemProvider = operatingSystemProvider
        self.deviceModelProvider = deviceModelProvider ?? { DeviceModel.current }
    }

    public func makeMetadata(screen: String?) -> FeedbackMetadata {
        let info = bundle.infoDictionary ?? [:]
        let os = operatingSystemProvider()
        return FeedbackMetadata(
            appVersion: (info["CFBundleShortVersionString"] as? String) ?? "unknown",
            build: (info["CFBundleVersion"] as? String) ?? "unknown",
            osName: os.name,
            osVersion: os.version,
            deviceModel: deviceModelProvider(),
            locale: localeProvider().identifier,
            clientVersion: AppReportKitVersion.current,
            screen: screen
        )
    }
}

enum DeviceModel {
    static var current: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine
    }
}
