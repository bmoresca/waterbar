import Foundation

/// The single place the version number lives. build.sh reads MARKETING_VERSION
/// straight out of this file and stamps it into Info.plist, so the binary and
/// the bundle can never disagree.
enum AppVersion {
    static let MARKETING_VERSION = "1.0.0"

    /// What the bundle says, falling back to the compiled-in value when the
    /// binary is run outside an app bundle (the CLI path).
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? MARKETING_VERSION
    }
}
