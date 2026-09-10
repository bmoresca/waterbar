import SwiftUI
import AppKit

/// The real entry point. Subcommands are handled and exited before SwiftUI is
/// ever touched, so `WaterBar report` doesn't start a menu bar item.
@main
enum Entry {
    static func main() {
        CLI.runIfRequested()
        PreviewRenderer.runIfRequested()
        WaterBarApp.main()
    }
}

struct WaterBarApp: App {
    @StateObject private var store = WaterStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            MenuBarLabel(text: store.menuBarText)
        }
        .menuBarExtraStyle(.window)
    }
}

/// MenuBarExtra only renders a single Text or Image reliably - an HStack here
/// comes out blank. Interpolating the symbol into the Text keeps both the glyph
/// and the number, and keeps the glyph templated so it follows the menu bar's
/// own light/dark appearance.
struct MenuBarLabel: View {
    let text: String
    var body: some View {
        Text("\(Image(systemName: "drop.fill")) \(text)")
    }
}

/// `WaterBar --render-preview <path.png>` draws the popover offscreen and exits.
/// Used to produce the README screenshots without needing screen recording access.
enum PreviewRenderer {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--render-preview"), flag + 1 < args.count else { return }
        let output = args[flag + 1]

        MainActor.assumeIsolated {
            let store = WaterStore(loadSynchronously: true)
            // ImageRenderer paints no backing, so the PNG would carry alpha and
            // pick up whatever it's placed on - a dark website hero, GitHub's
            // dark theme. Composite on white here instead.
            let page = ContentView(store: store, staticRender: true)
                .frame(width: 380)
                .background(Color.white)
            guard let png = render(page, scale: 2) else {
                FileHandle.standardError.write(Data("render failed\n".utf8))
                exit(1)
            }
            try? png.write(to: URL(fileURLWithPath: output))

            // Also prove the menu bar label renders something visible.
            if let label = render(MenuBarLabel(text: store.menuBarText).padding(6), scale: 3) {
                try? label.write(to: URL(fileURLWithPath:
                    output.replacingOccurrences(of: ".png", with: "-label.png")))
            }
            print("wrote \(output)")
            exit(0)
        }
    }

    @MainActor
    private static func render<V: View>(_ view: V, scale: CGFloat) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
