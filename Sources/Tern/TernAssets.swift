import AppKit

enum TernAssets {
    static let menuBarIconName = NSImage.Name("TernMenuBarIconTemplate")

    /// Development builds run side by side with the installed app, so they are marked "DEV".
    static let isDevelopment = Bundle.main.bundleIdentifier == "com.dominikbura.tern.dev"
    /// "Tern" or "Tern Dev", for menus and labels.
    static let appName = isDevelopment ? "Tern Dev" : "Tern"

    static let menuBarIcon: NSImage = {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)
        // CoreSVG ignores the logo's luminance masks. Use the pre-rendered
        // template representations to preserve the overlap cutouts at every scale.
        for suffix in ["", "@2x", "@3x"] {
            guard let url = Bundle.main.url(
                forResource: "TernMenuBarIconTemplate\(suffix)",
                withExtension: "png"
            ), let data = try? Data(contentsOf: url),
            let representation = NSBitmapImageRep(data: data) else {
                assertionFailure("Tern menu-bar icon representation \(suffix) is missing")
                continue
            }
            representation.size = size
            image.addRepresentation(representation)
        }

        image.isTemplate = true
        image.setName(menuBarIconName)
        return isDevelopment ? withDevLabel(image) : image
    }()

    /// The template icon followed by a small "DEV", still a template so it adapts to the menu bar.
    private static func withDevLabel(_ icon: NSImage) -> NSImage {
        let text = NSAttributedString(string: "DEV", attributes: [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .heavy),
            .foregroundColor: NSColor.black,
            .kern: 0.3,
        ])
        let textSize = text.size()
        let size = NSSize(width: icon.size.width + 2 + ceil(textSize.width), height: icon.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            icon.draw(in: NSRect(origin: .zero, size: icon.size))
            text.draw(at: NSPoint(x: icon.size.width + 2, y: (size.height - textSize.height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    static let applicationIcon: NSImage = {
        guard let url = Bundle.main.url(
            forResource: "TernAppIcon-1024",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            assertionFailure("Tern application icon is missing from the application bundle")
            return NSApplication.shared.applicationIconImage
        }
        return isDevelopment ? withDevBadge(image) : image
    }()

    /// The app icon with an orange "DEV" ribbon along the bottom, for the Dock and windows.
    private static func withDevBadge(_ icon: NSImage) -> NSImage {
        let size = NSSize(width: 1024, height: 1024)
        return NSImage(size: size, flipped: false) { rect in
            icon.draw(in: rect)
            let badge = NSRect(x: 262, y: 118, width: 500, height: 190)
            NSColor(srgbRed: 0.93, green: 0.36, blue: 0.10, alpha: 1).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 95, yRadius: 95).fill()
            NSColor.white.setStroke()
            let outline = NSBezierPath(roundedRect: badge.insetBy(dx: 6, dy: 6), xRadius: 89, yRadius: 89)
            outline.lineWidth = 12
            outline.stroke()
            let text = NSAttributedString(string: "DEV", attributes: [
                .font: NSFont.systemFont(ofSize: 128, weight: .black),
                .foregroundColor: NSColor.white,
                .kern: 6,
            ])
            let textSize = text.size()
            text.draw(at: NSPoint(x: badge.midX - textSize.width / 2, y: badge.midY - textSize.height / 2))
            return true
        }
    }

    static func registerNamedImages() {
        _ = menuBarIcon
        _ = applicationIcon
    }
}
