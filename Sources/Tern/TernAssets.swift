import AppKit

enum TernAssets {
    static let menuBarIconName = NSImage.Name("TernMenuBarIconTemplate")

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
        return image
    }()

    static let applicationIcon: NSImage = {
        guard let url = Bundle.main.url(
            forResource: "TernAppIcon-1024",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            assertionFailure("Tern application icon is missing from the application bundle")
            return NSApplication.shared.applicationIconImage
        }
        return image
    }()

    static func registerNamedImages() {
        _ = menuBarIcon
        _ = applicationIcon
    }
}
