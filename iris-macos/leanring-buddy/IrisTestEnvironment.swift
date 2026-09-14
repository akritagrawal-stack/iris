//
//  IrisTestEnvironment.swift
//  leanring-buddy
//
//  Runtime identity and private storage locations for the separately built
//  Iris Test app. The ordinary Iris bundle remains on the ordinary locations.
//

import Foundation

nonisolated struct IrisRuntimeIdentity: Equatable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let applicationSupportDirectoryName: String
    let logsDirectoryName: String
    let keychainServiceName: String

    var isTestApplication: Bool {
        bundleIdentifier == IrisTestEnvironment.testBundleIdentifier
    }
}

public nonisolated enum IrisTestEnvironment {
    static let standardBundleIdentifier = "com.publikhq.iris"
    static let testBundleIdentifier = "com.publikhq.iris.test"

    static let standardIdentity = IrisRuntimeIdentity(
        bundleIdentifier: standardBundleIdentifier,
        displayName: "Iris",
        applicationSupportDirectoryName: "Iris",
        logsDirectoryName: "Iris",
        keychainServiceName: standardBundleIdentifier
    )

    static let testIdentity = IrisRuntimeIdentity(
        bundleIdentifier: testBundleIdentifier,
        displayName: "Iris Test",
        applicationSupportDirectoryName: "Iris Test",
        logsDirectoryName: "Iris Test",
        keychainServiceName: testBundleIdentifier
    )

    /// Pure mapping used by the runtime selector and isolated tests. Only the
    /// exact test bundle identifier enables the alternate identity.
    static func identity(forBundleIdentifier bundleIdentifier: String?) -> IrisRuntimeIdentity {
        bundleIdentifier == testBundleIdentifier ? testIdentity : standardIdentity
    }

    static var runtimeIdentity: IrisRuntimeIdentity {
        identity(forBundleIdentifier: Bundle.main.bundleIdentifier)
    }

    /// True only for the separately configured Iris Test bundle.
    public static var isEnabled: Bool {
        runtimeIdentity.isTestApplication
    }

    /// Marketplace guide execution is opt-in for the separately signed Test
    /// app. This keeps ordinary Test runs isolated while allowing a reviewed
    /// native acceptance session to exercise the real guide flow against an
    /// explicitly staged workspace.
    static var isNativeAcceptanceMode: Bool {
        guard isEnabled, !isUnitTestProcess else { return false }
        return ProcessInfo.processInfo.environment["IRIS_TEST_NATIVE_ACCEPTANCE"] == "1"
    }

    static func allowsMarketplaceGuides(
        hasOfflineFixture: Bool,
        nativeAcceptanceMode: Bool = isNativeAcceptanceMode
    ) -> Bool {
        hasOfflineFixture || nativeAcceptanceMode
    }

    /// XCTest loads the Iris Test product into an isolated test host. That host
    /// cannot drive a marketplace install, but it must be able to exercise the
    /// controller's local state transitions using its own stubbed guide service.
    /// Keep this distinction here rather than turning the runtime's marketplace
    /// refusal into a broad test-build exception.
    static var isUnitTestProcess: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil {
            return true
        }

        // Do not infer this from a loaded XCTest symbol. The application target
        // can load test support through Xcode previews, which would otherwise
        // make a launched native acceptance app look like a test host and
        // silently disable its explicit acceptance flag.
        return false
    }

    public static var displayName: String { runtimeIdentity.displayName }
    public static var applicationSupportDirectoryName: String {
        runtimeIdentity.applicationSupportDirectoryName
    }
    public static var logsDirectoryName: String { runtimeIdentity.logsDirectoryName }
    public static var keychainServiceName: String { runtimeIdentity.keychainServiceName }

    /// The app-specific directory below `~/Library/Application Support`.
    public static var applicationSupportDirectory: URL {
        applicationSupportDirectory(
            for: runtimeIdentity, rootDirectory: applicationSupportRootDirectory
        )
    }

    /// Alias with an explicit URL suffix for callers that name URL values this
    /// way. Both names resolve to the same directory.
    public static var applicationSupportDirectoryURL: URL { applicationSupportDirectory }

    /// The app-specific directory below `~/Library/Logs`.
    public static var logsDirectory: URL {
        logsDirectory(for: runtimeIdentity, rootDirectory: logsRootDirectory)
    }

    public static var logsDirectoryURL: URL { logsDirectory }

    /// One private scratch root for the experimental app's local commands.
    public static var commandScratchDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("CommandScratch", isDirectory: true)
    }

    static func applicationSupportDirectory(
        for identity: IrisRuntimeIdentity, rootDirectory: URL
    ) -> URL {
        rootDirectory.appendingPathComponent(
            identity.applicationSupportDirectoryName, isDirectory: true
        )
    }

    static func logsDirectory(
        for identity: IrisRuntimeIdentity, rootDirectory: URL
    ) -> URL {
        rootDirectory.appendingPathComponent(identity.logsDirectoryName, isDirectory: true)
    }

    private static var applicationSupportRootDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    private static var logsRootDirectory: URL {
        let libraryDirectory = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
        // The Foundation library URL is `~/Library`; logs live one level below
        // it, matching the original `~/Library/Logs/Iris` location.
        return libraryDirectory.appendingPathComponent("Logs", isDirectory: true)
    }
}
