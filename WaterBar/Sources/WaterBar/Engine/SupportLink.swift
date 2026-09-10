import Foundation

/// The "buy me a coffee" destination.
///
/// Baked in so a downloaded copy needs no setup, but overridable via
/// `support_url` in ~/.claude/water/config.json for anyone running a fork.
/// An empty URL hides the button entirely - which is the state until a real
/// Stripe payment link is dropped in below.
enum SupportLink {
    static let builtIn = "https://donate.stripe.com/9B6dR24TMbHReeTf0x9IQ0d"

    static var url: URL? {
        let configured = JSONFile.read(Paths.config)?["support_url"] as? String
        let candidate = (configured?.isEmpty == false ? configured! : builtIn)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              let url = URL(string: candidate),
              url.scheme == "https" else { return nil }
        return url
    }

    /// Coffee is roughly 140 L of embedded water a cup, which in an app that
    /// counts millilitres is too good to leave unsaid.
    static let tooltip = "One cup of coffee takes about 140 litres of water to grow. "
        + "Opens Stripe in your browser."
}
