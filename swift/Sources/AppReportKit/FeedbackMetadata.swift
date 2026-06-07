import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct FeedbackMetadata: Codable, Equatable {
    public struct AppInfo: Codable, Equatable {
        public let version: String
        public let build: String
        public let clientVersion: String
        public let screen: String?

        public init(
            version: String,
            build: String,
            clientVersion: String,
            screen: String? = nil
        ) {
            self.version = version
            self.build = build
            self.clientVersion = clientVersion
            self.screen = screen
        }
    }

    public struct DeviceInfo: Codable, Equatable {
        public let osName: String
        public let osVersion: String
        public let model: String
        public let locale: String

        public init(
            osName: String,
            osVersion: String,
            model: String,
            locale: String
        ) {
            self.osName = osName
            self.osVersion = osVersion
            self.model = model
            self.locale = locale
        }
    }

    public let appVersion: String
    public let build: String
    public let osName: String
    public let osVersion: String
    public let deviceModel: String
    public let locale: String
    public let clientVersion: String
    public let screen: String?

    public init(app: AppInfo, device: DeviceInfo) {
        appVersion = app.version
        build = app.build
        osName = device.osName
        osVersion = device.osVersion
        deviceModel = device.model
        locale = device.locale
        clientVersion = app.clientVersion
        screen = app.screen
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
    public static let current = "0.2.0"
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
            app: .init(
                version: (info["CFBundleShortVersionString"] as? String) ?? "unknown",
                build: (info["CFBundleVersion"] as? String) ?? "unknown",
                clientVersion: AppReportKitVersion.current,
                screen: screen
            ),
            device: .init(
                osName: os.name,
                osVersion: os.version,
                model: deviceModelProvider(),
                locale: localeProvider().identifier
            )
        )
    }
}

enum DeviceModel {
    static var current: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        return machine.isEmpty ? "unknown" : machine
    }
}
